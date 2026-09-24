# Deploying to kOps on GCP (3-Node Cluster)

> **Revision Note**: Steps 4 and 8 have been updated to support Uniform Bucket-Level Access (UBLA) and storage.objectAdmin IAM bindings, and to export and set the KUBECONFIG environment variable correctly.

This runbook guides you through deploying `agent-sandbox` to a self-managed, gossip-based, 3-node Kubernetes cluster on GCP using GCE VMs provisioned via **kOps** (Kubernetes Operations).

---

## What this needs

### Binaries, Tests, envtest, or Real Infrastructure?
This deployment **requires real infrastructure**. It cannot run "in-pod" (e.g., via envtest or local binaries) because:
- It provisions actual Google Compute Engine (GCE) VMs (1 control plane VM and 3 node VMs).
- It configures Google Cloud Storage (GCS) as a state store for kOps.
- It deploys real CNI plugins (e.g., **Cilium**) to configure secure node routing.
- It installs node-level DaemonSets (like **node-exporter**) to capture OS-level performance metrics.

### Feasibility Checklist
Before execution, verify the following prerequisites in your environment. Run the validation commands exactly as shown to check status, and run the installation/grant commands if anything is missing.

| Requirement | Verified Status | Validation Command | Installation / Grant Command |
| :--- | :--- | :--- | :--- |
| **`gcloud` CLI** | `✓ Present` | `gcloud version` | [Google Cloud SDK Install Guide](https://cloud.google.com/sdk/docs/install) |
| **`kubectl` CLI** | `✓ Present` | `kubectl version --client` | [Kubectl Install Guide](https://kubernetes.io/docs/tasks/tools/) |
| **`go` toolchain** | `✓ Present` | `go version` | [Go Install Guide](https://go.dev/doc/install) |
| **`kops` CLI** | `✗ MISSING` | `kops version` | `GOBIN="${HOME}/go/bin" go install k8s.io/kops/cmd/kops@v1.36.0` (Compiles on demand) |
| **GCP IAM Permissions** | `✓ Present` | `gcloud projects get-iam-policy $PROJECT_ID --limit=1` | Contact your GCP Organization Admin for `roles/owner` or `roles/editor` on the project. |

### GCP IAM Roles Required & Buckets Security
To run kOps, your active Google Cloud identity (user or service account) must have high-level permissions on your target GCP project:
- **`roles/owner`** or **`roles/editor`** on the target project (needed to create VPC, Firewalls, Service Accounts, GCE Instances, GCS Buckets).
- **`roles/storage.objectAdmin`** on the bucket used for the state store.
- **Uniform Bucket-Level Access (UBLA):** GCS state store bucket creation must specify `--uniform-bucket-level-access` when running in federated/Workload Identity Federation (WIF) environments to satisfy authentication requirements.

### Cost to Tear Down
Teardown will clean up all created resources:
- GCS state store bucket (if specified).
- 4 GCE VMs (1 control plane VM, 3 node VMs).
- 1 GCP VPC network and associated routes/firewall rules.
- **Teardown Command:** Included in the [Teardown](#teardown) section of this runbook.

---

## Preconditions

Prior to running the steps, set up these environment variables to configure your specific deployment instance.
All cloud resources created by this instance will be prefixed with your customized `${RESOURCE_PREFIX}` to ensure isolation and ownership.

```sh
# Set a unique prefix for your resources (lowercase, alphanumeric, max 15 chars)
export RESOURCE_PREFIX="sandbox-kops-s"

# Target GCP Config
export PROJECT_ID="barni-cnrm-20260529"   # Replace with your GCP project ID
export REGION="us-central1"
export ZONE="us-central1-a"

# Cluster Specs
export CLUSTER_NAME="${RESOURCE_PREFIX}.k8s.local" # Gossip-based cluster domain
export BUCKET_NAME="kops-state-${RESOURCE_PREFIX}"
export KOPS_STATE_STORE="gs://${BUCKET_NAME}"
export CNI="cilium"                              # "cilium" or "kindnet"

# Image Config
export IMAGE_PREFIX="gcr.io/${PROJECT_ID}/${RESOURCE_PREFIX}/"
```

---

## Steps

### 1. Compile/Install kOps
If `kops` is missing from your path, compile and install it directly via the Go toolchain:
```sh
# Install kOps v1.36.0 to your local Go bin directory
GOBIN="${HOME}/go/bin" go install k8s.io/kops/cmd/kops@v1.36.0
export PATH="${HOME}/go/bin:${PATH}"
```

### 2. Configure GCP Auth and Docker Helper
Authenticate Docker to push images to Google Container Registry (GCR) in your project:
```sh
gcloud auth configure-docker --quiet gcr.io
```

### 3. Build and Push Controller Images
Build the `agent-sandbox-controller` and related images, then push them to your project's GCR registry:
```sh
# Builds and pushes the controller & dependency images (e.g. chrome-sandbox)
./dev/tools/push-images --image-prefix="${IMAGE_PREFIX}"
```

### 4. Create the GCS State Store Bucket
Create a Google Cloud Storage bucket where kOps will store the state configuration of the cluster. We enable Uniform Bucket-Level Access (UBLA) and grant `roles/storage.objectAdmin` on the bucket to avoid authentication issues in federated/WIF environments:
```sh
gcloud storage buckets create "gs://${BUCKET_NAME}" \
  --project="${PROJECT_ID}" \
  --location="${REGION}" \
  --uniform-bucket-level-access

gcloud storage buckets update "gs://${BUCKET_NAME}" \
  --update-labels="repo-agent-instance=${RESOURCE_PREFIX}" || true

# Grant storage.objectAdmin on the state bucket to active identity
PRINCIPALS=$(gcloud projects get-iam-policy "${PROJECT_ID}" --filter="bindings.role:roles/owner" --flatten="bindings[].members" --format="value(bindings.members)")
for principal in ${PRINCIPALS}; do
  gcloud storage buckets add-iam-policy-binding "gs://${BUCKET_NAME}" --member="${principal}" --role="roles/storage.objectAdmin" &> /dev/null || true
done
```

### 5. Generate kOps Cluster Configuration
Run `kops create cluster` to generate a 3-node cluster design configuration in your GCS state store:
```sh
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
```

### 6. Apply Spec Tuning (Optional, Recommended)
To prevent the cluster's pod launch from being disk-sync bound (as identified in performance-tuning/benchmarks), update the root volume types for GCE VMs to use `pd-ssd` instead of the spinning disk `pd-standard` default:
```sh
# Change node VM root disk to SSD
kops edit instancegroup --name "${CLUSTER_NAME}" "nodes-${ZONE}" \
  --set "spec.rootVolume.type=pd-ssd"

# Change control plane VM root disk to SSD
kops edit instancegroup --name "${CLUSTER_NAME}" "control-plane-${ZONE}" \
  --set "spec.rootVolume.type=pd-ssd"
```

### 7. Provision the Infrastructure
Apply the configuration to create the virtual machines and networks on GCP:
```sh
# Instruct kOps to build and boot the cluster resources on GCP
kops update cluster --name="${CLUSTER_NAME}" --yes
```

### 8. Export Kubeconfig
Retrieve admin credentials and write them to your default kubeconfig path. We also explicitly export it to `bin/KUBECONFIG` and set the `KUBECONFIG` environment variable so verification and E2E test suites can find it easily:
```sh
mkdir -p bin
kops export kubeconfig --name="${CLUSTER_NAME}" --admin --kubeconfig="bin/KUBECONFIG"
kops export kubeconfig --name="${CLUSTER_NAME}" --admin
export KUBECONFIG="$(pwd)/bin/KUBECONFIG"
```

### 9. Validate Cluster Liveness
Wait for the cluster's control plane and nodes to report healthy:
```sh
# Wait up to 25 minutes for kOps to complete bootstrap and report as healthy
kops validate cluster --wait 25m
```

### 10. Deploy Agent Sandbox to the Cluster
Use the project's deployment tool to apply the namespace, CRDs, and core controller/extensions manifests to your newly created cluster:
```sh
# Deploys custom CRDs and controller with images pointing to your GCP registry
./dev/tools/deploy-to-kube --image-prefix="${IMAGE_PREFIX}" --extensions
```

---

## Verify

Verify that the cluster is healthy and `agent-sandbox` is running and fully functional.

### 1. Check Controller Readiness
Verify that the `agent-sandbox-controller` pods are in `Running` state:
```sh
kubectl rollout status deployment agent-sandbox-controller --namespace agent-sandbox-system --timeout=10m
```

### 2. Verify Node Exporter (If Deployed)
If node metrics are enabled (e.g. from node-exporter.yaml in benchmarks scenario):
```sh
kubectl apply -f test/benchmarks/scenarios/benchmarks-kops-gcp/node-exporter.yaml
kubectl --namespace kube-system rollout status daemonset/node-exporter --timeout=3m
```

### 3. Run E2E Verification Tests
To execute E2E validation against the remote cluster and ensure that sandboxes can be created, claimed, and successfully deleted:
```sh
./dev/tools/test-e2e --suite=benchmarks --image-prefix="${IMAGE_PREFIX}"
```

---

## Teardown

To avoid incurring GCE VM charges and clean up resources, execute these steps:

### 1. Delete the kOps Cluster
```sh
kops delete cluster --name="${CLUSTER_NAME}" --yes
```

### 2. Delete the GCS State Store Bucket
```sh
gcloud storage buckets delete "gs://${BUCKET_NAME}" --quiet
```
