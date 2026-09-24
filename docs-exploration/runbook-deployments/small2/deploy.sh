#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/../../.." && pwd)"

# shellcheck source=/dev/null
source "${SCRIPT_DIR}/params.env"

cd "${REPO_ROOT}"

# Step 1: Compile/Install kOps
if ! command -v kops &> /dev/null; then
  export PATH="${HOME}/go/bin:${PATH}"
fi
if ! command -v kops &> /dev/null; then
  echo "kOps CLI not found. Installing kops@v1.36.0..."
  GOBIN="${HOME}/go/bin" go install k8s.io/kops/cmd/kops@v1.36.0
  export PATH="${HOME}/go/bin:${PATH}"
fi

# Export kOps state store
export KOPS_STATE_STORE

# Step 2: Configure GCP Auth and Docker Helper
echo "Configuring docker authentication for gcr.io..."
gcloud auth configure-docker --quiet gcr.io

# Step 3: Build and Push Controller Images
echo "Building and pushing controller images with prefix ${IMAGE_PREFIX}..."
./dev/tools/push-images --image-prefix="${IMAGE_PREFIX}"

# Step 4: Create the GCS State Store Bucket
echo "Creating GCS state store bucket ${BUCKET_NAME}..."
gcloud storage buckets create "gs://${BUCKET_NAME}" \
  --project="${PROJECT_ID}" \
  --location="${REGION}" \
  --uniform-bucket-level-access || true

gcloud storage buckets update "gs://${BUCKET_NAME}" \
  --update-labels="repo-agent-instance=${RESOURCE_PREFIX}" || true

# Grant storage.objectAdmin on the state bucket to active identity
PRINCIPALS=$(gcloud projects get-iam-policy "${PROJECT_ID}" --filter="bindings.role:roles/owner" --flatten="bindings[].members" --format="value(bindings.members)")
for principal in ${PRINCIPALS}; do
  gcloud storage buckets add-iam-policy-binding "gs://${BUCKET_NAME}" --member="${principal}" --role="roles/storage.objectAdmin" &> /dev/null || true
done

# Step 5: Generate kOps Cluster Configuration
echo "Creating kOps cluster configuration for ${CLUSTER_NAME}..."
kops create cluster \
  --cloud=gce \
  --gce-service-account=default \
  --networking="${CNI}" \
  --name="${CLUSTER_NAME}" \
  --zones="${ZONE}" \
  --project="${PROJECT_ID}" \
  --control-plane-count=1 \
  --control-plane-size=n2-standard-4 \
  --node-count=3 \
  --node-size=n2-standard-4

# Step 6: Apply Spec Tuning (pd-ssd root volumes)
echo "Applying SSD disk spec tuning..."
kops edit instancegroup --name "${CLUSTER_NAME}" "nodes-${ZONE}" \
  --set "spec.rootVolume.type=pd-ssd"

kops edit instancegroup --name "${CLUSTER_NAME}" "control-plane-${ZONE}" \
  --set "spec.rootVolume.type=pd-ssd"

# Step 7: Provision the Infrastructure
echo "Provisioning cluster infrastructure on GCP..."
kops update cluster --name="${CLUSTER_NAME}" --yes

# Step 8: Export Kubeconfig
echo "Exporting kubeconfig..."
mkdir -p bin
kops export kubeconfig --name="${CLUSTER_NAME}" --admin --kubeconfig="bin/KUBECONFIG"
kops export kubeconfig --name="${CLUSTER_NAME}" --admin
export KUBECONFIG="$(pwd)/bin/KUBECONFIG"

# Step 9: Validate Cluster Liveness
echo "Waiting for cluster validation..."
kops validate cluster --wait 25m

# Step 10: Deploy Agent Sandbox to the Cluster
echo "Deploying agent-sandbox to the cluster..."
./dev/tools/deploy-to-kube --image-prefix="${IMAGE_PREFIX}" --extensions

echo "Deployment complete for instance ${RESOURCE_PREFIX}."
