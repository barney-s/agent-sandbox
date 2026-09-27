TORN-DOWN

## Teardown Summary: `small`

- **Run:** `small`
- **Runbook:** `docs-exploration/runbooks/deploy-kops-s.md`
- **Resource Prefix:** `as-small`
- **GCP Project:** `barni-cnrm-20260529`
- **Teardown Script:** `docs-exploration/agent-runs/small/teardown.sh`
- **Timestamp (UTC):** 2026-09-27 16:22 UTC

---

## Resources Removed

All active compute, network, and storage infrastructure provisioned for the `small` run instance was decommissioned using `docs-exploration/agent-runs/small/teardown.sh`.

### 1. kOps Kubernetes Cluster (`as-small.k8s.local`)
- **Control Plane VM:** `control-plane-us-central1-a-4g1f` (`n2-standard-4`, `us-central1-a`) — Deleted.
- **Worker Node VMs:** `nodes-us-central1-a-3sdc`, `nodes-us-central1-a-cch3`, `nodes-us-central1-a-lm8t` (`n2-standard-4`, `us-central1-a`) — Deleted.
- **Persistent Disks:** `a-etcd-events-as-small-k8s-local`, `a-etcd-main-as-small-k8s-local`, and all VM root PD-SSD disks — Deleted.
- **Instance Groups & Templates:** `a-control-plane-us-central1-a-as-small-k8s-local`, `a-nodes-us-central1-a-as-small-k8s-local`, `control-plane-us-central1-0cvqhq-1790234732`, `nodes-us-central1-a-as-sm-v9ucl7-1790234732` — Deleted.
- **Networking & Firewalls:**
  - VPC network `as-small-k8s-local` and subnet `us-central1-as-small-k8s-local` — Deleted.
  - Firewall rules (`https-api-*`, `kops-controller-*`, `lb-health-checks-*`, `master-to-*`, `node-to-*`, `nodeport-*`, `ssh-external-*`) — Deleted.
  - Forwarding rules (`api-as-small-k8s-local`, `api-us-central1-as-small-k8s-local`, `kops-controller-us-central1-as-small-k8s-local`) — Deleted.
  - Backend services, health checks, target pools, and IP addresses (`api-as-small-k8s-local`, `api-us-central1-as-small-k8s-local`) — Deleted.

### 2. GCS State Store Bucket
- **Bucket:** `gs://kops-state-as-small` — Deleted and purged.

---

## Verification Evidence

### 1. GCE Compute Instances
```
$ gcloud compute instances list --project="barni-cnrm-20260529" --filter="name ~ as-small"
Listed 0 items.
```

### 2. GCE Disks, Instance Groups, Templates, Networks & Firewalls
```
$ gcloud compute disks list --project="barni-cnrm-20260529" --filter="name ~ as-small"
Listed 0 items.

$ gcloud compute instance-templates list --project="barni-cnrm-20260529" --filter="name ~ as-small"
Listed 0 items.

$ gcloud compute instance-groups list --project="barni-cnrm-20260529" --filter="name ~ as-small"
Listed 0 items.

$ gcloud compute firewall-rules list --project="barni-cnrm-20260529" --filter="name ~ as-small"
Listed 0 items.

$ gcloud compute networks list --project="barni-cnrm-20260529" --filter="name ~ as-small"
Listed 0 items.

$ gcloud compute networks subnets list --project="barni-cnrm-20260529" --filter="name ~ as-small"
Listed 0 items.

$ gcloud compute forwarding-rules list --project="barni-cnrm-20260529" --filter="name ~ as-small"
Listed 0 items.

$ gcloud compute backend-services list --project="barni-cnrm-20260529" --filter="name ~ as-small"
Listed 0 items.

$ gcloud compute health-checks list --project="barni-cnrm-20260529" --filter="name ~ as-small"
Listed 0 items.

$ gcloud compute addresses list --project="barni-cnrm-20260529" --filter="name ~ as-small"
Listed 0 items.
```

### 3. GCS Storage Buckets
```
$ gcloud storage buckets list --project="barni-cnrm-20260529" --filter="name ~ as-small"
Listed 0 items.
```

### 4. kOps Cluster State
```
$ export KOPS_STATE_STORE="gs://kops-state-as-small"
$ kops get clusters
Error: error reading state store: file does not exist
```

---

## What Remains and Why

- **Container Images:** `gcr.io/barni-cnrm-20260529/as-small/agent-sandbox-controller` and `gcr.io/barni-cnrm-20260529/as-small/chrome-sandbox` remain in Google Container Registry as static image artifacts. These incur zero active compute cost and can be cleaned up per standard registry retention policy or retained for image caching across runs.
- **Active Infrastructure:** None. All VM instances, load balancers, disks, network components, and GCS buckets have been completely destroyed.
