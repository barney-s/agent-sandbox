#!/usr/bin/env bash
# Updated: grant storage.objectAdmin on state bucket, enable uniform bucket-level access, export KUBECONFIG to bin/KUBECONFIG, add multi-tags for test runner compatibility, and Cloud Build fallback.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/../../.." && pwd)"

source "${SCRIPT_DIR}/params.env"
export KOPS_STATE_STORE
export IMAGE_TAG
export IMAGE_PREFIX
export PATH="${HOME}/go/bin:${PATH}"
export KUBECONFIG="${REPO_ROOT}/bin/KUBECONFIG"

cd "${REPO_ROOT}"
mkdir -p "${REPO_ROOT}/bin"

# Step 1: Install kOps if not available
if ! command -v kops &> /dev/null; then
  echo "kOps not found in PATH. Installing kops v1.36.0 to ${HOME}/go/bin..."
  GOBIN="${HOME}/go/bin" go install k8s.io/kops/cmd/kops@v1.36.0
fi

# Step 2: Configure GCP Auth and Docker Helper
echo "Configuring Docker authentication for GCR..."
gcloud auth configure-docker --quiet gcr.io || true

# Step 3: Build and Push Controller Images
echo "Checking controller images with prefix ${IMAGE_PREFIX} and tag ${IMAGE_TAG}..."
if gcloud container images describe "${IMAGE_PREFIX}agent-sandbox-controller:${IMAGE_TAG}" &> /dev/null && \
   gcloud container images describe "${IMAGE_PREFIX}chrome-sandbox:${IMAGE_TAG}" &> /dev/null; then
  echo "Images already built and available in GCR."
elif docker info &> /dev/null; then
  echo "Building images locally with Docker..."
  ./dev/tools/push-images --image-prefix="${IMAGE_PREFIX}" --image-tag="${IMAGE_TAG}" --images agent-sandbox-controller chrome-sandbox
else
  echo "Local Docker daemon unavailable. Building and pushing via Google Cloud Build..."
  cat << EOF > /tmp/cb-build.yaml
steps:
- name: 'gcr.io/k8s-staging-test-infra/gcb-docker-gcloud'
  entrypoint: 'python3'
  args:
  - './dev/tools/push-images'
  - '--image-prefix=${IMAGE_PREFIX}'
  - '--image-tag=${IMAGE_TAG}'
  - '--images'
  - 'agent-sandbox-controller'
  - 'chrome-sandbox'
options:
  machineType: 'E2_HIGHCPU_32'
EOF
  gcloud builds submit --project="${PROJECT_ID}" --config=/tmp/cb-build.yaml .
  rm -f /tmp/cb-build.yaml
fi

# Tag images with dirty and latest aliases to support local test runners in dirty worktrees
gcloud container images add-tag "${IMAGE_PREFIX}agent-sandbox-controller:${IMAGE_TAG}" "${IMAGE_PREFIX}agent-sandbox-controller:${IMAGE_TAG}-dirty" --quiet || true
gcloud container images add-tag "${IMAGE_PREFIX}agent-sandbox-controller:${IMAGE_TAG}" "${IMAGE_PREFIX}agent-sandbox-controller:latest" --quiet || true
gcloud container images add-tag "${IMAGE_PREFIX}chrome-sandbox:${IMAGE_TAG}" "${IMAGE_PREFIX}chrome-sandbox:${IMAGE_TAG}-dirty" --quiet || true
gcloud container images add-tag "${IMAGE_PREFIX}chrome-sandbox:${IMAGE_TAG}" "${IMAGE_PREFIX}chrome-sandbox:latest" --quiet || true

# Step 4: Create the GCS State Store Bucket
echo "Creating GCS state store bucket ${BUCKET_NAME}..."
if ! gcloud storage buckets describe "gs://${BUCKET_NAME}" --project="${PROJECT_ID}" &> /dev/null; then
  gcloud storage buckets create "gs://${BUCKET_NAME}" --project="${PROJECT_ID}" --location="${REGION}" --uniform-bucket-level-access
  gcloud storage buckets update "gs://${BUCKET_NAME}" --update-labels="repo-agent-instance=${RESOURCE_PREFIX}" || true
else
  echo "Bucket gs://${BUCKET_NAME} already exists. Ensuring uniform bucket level access..."
  gcloud storage buckets update "gs://${BUCKET_NAME}" --uniform-bucket-level-access || true
fi

# Ensure active owner principals have storage.objectAdmin on the state bucket
PRINCIPALS=$(gcloud projects get-iam-policy "${PROJECT_ID}" --filter="bindings.role:roles/owner" --flatten="bindings[].members" --format="value(bindings.members)")
for principal in ${PRINCIPALS}; do
  gcloud storage buckets add-iam-policy-binding "gs://${BUCKET_NAME}" --member="${principal}" --role="roles/storage.objectAdmin" &> /dev/null || true
done

# Step 5: Generate kOps Cluster Configuration
echo "Generating kOps cluster configuration for ${CLUSTER_NAME}..."
if ! kops get cluster --name="${CLUSTER_NAME}" &> /dev/null; then
  kops create cluster \
    --cloud=gce \
    --gce-service-account=default \
    --networking="${CNI}" \
    --name="${CLUSTER_NAME}" \
    --zones="${ZONE}" \
    --project="${PROJECT_ID}" \
    --control-plane-count="${CONTROL_PLANE_COUNT}" \
    --control-plane-size="${CONTROL_PLANE_SIZE}" \
    --node-count="${NODE_COUNT}" \
    --node-size="${NODE_SIZE}"

  # Step 6: Apply Spec Tuning
  echo "Tuning VM instance group root volume types to pd-ssd..."
  kops edit instancegroup --name "${CLUSTER_NAME}" "nodes-${ZONE}" \
    --set "spec.rootVolume.type=pd-ssd"

  kops edit instancegroup --name "${CLUSTER_NAME}" "control-plane-${ZONE}" \
    --set "spec.rootVolume.type=pd-ssd"
else
  echo "kOps cluster config ${CLUSTER_NAME} already exists in state store."
fi

# Step 7: Provision the Infrastructure
echo "Provisioning kOps cluster infrastructure..."
kops update cluster --name="${CLUSTER_NAME}" --yes

# Step 8: Export Kubeconfig
echo "Exporting admin kubeconfig for ${CLUSTER_NAME}..."
kops export kubeconfig --name="${CLUSTER_NAME}" --admin --kubeconfig="${KUBECONFIG}"
kops export kubeconfig --name="${CLUSTER_NAME}" --admin

# Step 9: Validate Cluster Liveness
echo "Validating cluster readiness (waiting up to 25m)..."
kops validate cluster --wait 25m

# Step 10: Deploy Agent Sandbox to the Cluster
echo "Deploying Agent Sandbox manifests to the cluster..."
./dev/tools/deploy-to-kube --image-prefix="${IMAGE_PREFIX}" --image-tag="${IMAGE_TAG}" --extensions

# Verification
echo "Verifying agent-sandbox deployment..."
kubectl rollout status deployment agent-sandbox-controller --namespace agent-sandbox-system --timeout=10m

if [ -f "test/benchmarks/scenarios/benchmarks-kops-gcp/node-exporter.yaml" ]; then
  echo "Applying node-exporter daemonset..."
  kubectl apply -f test/benchmarks/scenarios/benchmarks-kops-gcp/node-exporter.yaml
  kubectl --namespace kube-system rollout status daemonset/node-exporter --timeout=3m
fi

echo "Running benchmarks E2E verification tests..."
./dev/tools/test-e2e --suite=benchmarks --image-prefix="${IMAGE_PREFIX}"

echo "Deployment and verification completed successfully!"
