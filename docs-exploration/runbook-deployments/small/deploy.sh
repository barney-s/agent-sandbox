#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/../../.." && pwd)"

source "${SCRIPT_DIR}/params.env"
export KOPS_STATE_STORE

cd "${REPO_ROOT}"

# Step 1: Install kOps if not available
if ! command -v kops &> /dev/null; then
  echo "kOps not found in PATH. Installing kops v1.36.0 to ${HOME}/go/bin..."
  GOBIN="${HOME}/go/bin" go install k8s.io/kops/cmd/kops@v1.36.0
  export PATH="${HOME}/go/bin:${PATH}"
fi

# Step 2: Configure GCP Auth and Docker Helper
echo "Configuring Docker authentication for GCR..."
gcloud auth configure-docker --quiet gcr.io

# Step 3: Build and Push Controller Images
echo "Building and pushing controller images with prefix ${IMAGE_PREFIX}..."
./dev/tools/push-images --image-prefix="${IMAGE_PREFIX}"

# Step 4: Create the GCS State Store Bucket
echo "Creating GCS state store bucket ${BUCKET_NAME}..."
gcloud storage buckets create "gs://${BUCKET_NAME}" --project="${PROJECT_ID}" --location="${REGION}"
gcloud storage buckets update "gs://${BUCKET_NAME}" --update-labels="repo-agent-instance=${RESOURCE_PREFIX}" || true

# Step 5: Generate kOps Cluster Configuration
echo "Generating kOps cluster configuration for ${CLUSTER_NAME}..."
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

# Step 7: Provision the Infrastructure
echo "Provisioning kOps cluster infrastructure..."
kops update cluster --name="${CLUSTER_NAME}" --yes

# Step 8: Export Kubeconfig
echo "Exporting admin kubeconfig for ${CLUSTER_NAME}..."
kops export kubeconfig --name="${CLUSTER_NAME}" --admin

# Step 9: Validate Cluster Liveness
echo "Validating cluster readiness (waiting up to 25m)..."
kops validate cluster --wait 25m

# Step 10: Deploy Agent Sandbox to the Cluster
echo "Deploying Agent Sandbox manifests to the cluster..."
./dev/tools/deploy-to-kube --image-prefix="${IMAGE_PREFIX}" --extensions

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
