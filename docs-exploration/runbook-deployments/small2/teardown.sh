#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/../../.." && pwd)"

# shellcheck source=/dev/null
source "${SCRIPT_DIR}/params.env"

cd "${REPO_ROOT}"

if ! command -v kops &> /dev/null; then
  export PATH="${HOME}/go/bin:${PATH}"
fi

export KOPS_STATE_STORE

echo "Deleting kOps cluster ${CLUSTER_NAME}..."
kops delete cluster --name="${CLUSTER_NAME}" --yes || true

echo "Deleting GCS state store bucket ${BUCKET_NAME}..."
gcloud storage buckets delete "gs://${BUCKET_NAME}" --quiet || true

echo "Teardown complete for instance ${RESOURCE_PREFIX}."
