#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/../../.." && pwd)"

# shellcheck source=/dev/null
source "${SCRIPT_DIR}/params.env"

export KOPS_STATE_STORE
export PATH="${HOME}/go/bin:${PATH}"

cd "${REPO_ROOT}"

# Step 1: Delete the kOps Cluster
echo "Deleting kOps cluster ${CLUSTER_NAME}..."
kops delete cluster --name="${CLUSTER_NAME}" --yes || true

# Step 2: Delete the GCS State Store Bucket
echo "Deleting GCS state store bucket ${BUCKET_NAME}..."
gcloud storage buckets delete "gs://${BUCKET_NAME}" --quiet || true

echo "Teardown complete for instance ${RESOURCE_PREFIX}."
