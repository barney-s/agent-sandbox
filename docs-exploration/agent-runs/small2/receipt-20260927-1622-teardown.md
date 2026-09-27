TORN-DOWN

## Teardown Receipt: small2 (kOps on GCP)

- **Timestamp (UTC)**: 2026-09-27 16:22
- **Resource Prefix**: `as-small2`
- **GCP Project ID**: `barni-cnrm-20260529`
- **Cluster Domain**: `as-small2.k8s.local`
- **State Store Bucket**: `gs://kops-state-as-small2`

---

## Removed Resources

All cloud infrastructure provisioned for `small2` was torn down via `teardown.sh`:

1. **kOps Cluster & Compute Instances (`us-central1-a`)**:
   - `control-plane-us-central1-a-n5m1` (Control plane VM, `n2-standard-4`)
   - `nodes-us-central1-a-602t` (Worker node VM, `n2-standard-4`)
   - `nodes-us-central1-a-qn4f` (Worker node VM, `n2-standard-4`)
   - `nodes-us-central1-a-vs15` (Worker node VM, `n2-standard-4`)
   - Instance Group Managers: `a-control-plane-us-central1-a-as-small2-k8s-local`, `a-nodes-us-central1-a-as-small2-k8s-local`
   - Instance Templates: `control-plane-us-central1-*`, `nodes-us-central1-a-as-sm-*`

2. **Persistent Storage**:
   - Root boot disks for all 4 instances (`pd-ssd`, 64GB / 128GB)
   - `a-etcd-main-as-small2-k8s-local` (`pd-ssd`, 20GB)
   - `a-etcd-events-as-small2-k8s-local` (`pd-ssd`, 20GB)
   - GCS state bucket `gs://kops-state-as-small2` and all state objects

3. **Networking & Load Balancing**:
   - VPC Network: `as-small2-k8s-local`
   - Subnet: `us-central1-as-small2-k8s-local`
   - Target pools, backend services, forwarding rules, and health checks for `api-as-small2-k8s-local` and `kops-controller`
   - All 15 firewall rules prefixed with `*-as-small2-k8s-local`
   - Custom routes prefixed with `as-small2-k8s-local-*`

---

## Verification Evidence

### 1. Compute Instances Query
```sh
$ gcloud compute instances list --project=barni-cnrm-20260529 --filter="name ~ as-small2 OR name ~ n5m1 OR name ~ 602t OR name ~ qn4f OR name ~ vs15"
Listed 0 items.
```

### 2. Persistent Disks Query
```sh
$ gcloud compute disks list --project=barni-cnrm-20260529 --filter="name ~ as-small2 OR name ~ n5m1 OR name ~ 602t OR name ~ qn4f OR name ~ vs15"
Listed 0 items.
```

### 3. Instance Groups & Templates Query
```sh
$ gcloud compute instance-groups list --project=barni-cnrm-20260529 --filter="name ~ as-small2"
Listed 0 items.
$ gcloud compute instance-templates list --project=barni-cnrm-20260529 --filter="name ~ as-small2"
Listed 0 items.
```

### 4. VPC Network, Subnets, Routes, and Firewalls Query
```sh
$ gcloud compute networks list --project=barni-cnrm-20260529 --filter="name ~ as-small2"
Listed 0 items.
$ gcloud compute networks subnets list --project=barni-cnrm-20260529 --filter="name ~ as-small2"
Listed 0 items.
$ gcloud compute routes list --project=barni-cnrm-20260529 --filter="name ~ as-small2"
Listed 0 items.
$ gcloud compute firewall-rules list --project=barni-cnrm-20260529 --filter="name ~ as-small2"
Listed 0 items.
```

### 5. GCS State Store Bucket Query
```sh
$ gcloud storage buckets list --project=barni-cnrm-20260529 --filter="name ~ as-small2 OR labels.repo-agent-instance:as-small2"
Listed 0 items.
```

### 6. kOps Cluster State Query
```sh
$ export KOPS_STATE_STORE="gs://kops-state-as-small2"
$ kops get clusters
Error: error reading state store: file does not exist
```

---

## Remaining Artifacts
- **Container Images**: `gcr.io/barni-cnrm-20260529/as-small2/agent-sandbox-controller` and `gcr.io/barni-cnrm-20260529/as-small2/chrome-sandbox` remain stored in Google Container Registry (no running compute or storage bucket infrastructure remains active).
