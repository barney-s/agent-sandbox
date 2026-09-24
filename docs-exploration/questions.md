# Open Questions

This document records ambiguities found in the code, open design trade-offs, and architecture questions for future discussion.

---

## 1. NetworkPolicy Edge-Cases and Cloud Metadata IPs
In `sandboxtemplate_controller.go`, the controller generates a "secure-by-default" NetworkPolicy that blocks access to private RFC1918 CIDRs and the Cloud Metadata IP:
- **The Question:** How robust is the cloud metadata IP block across different clouds? GCP, AWS, and OpenStack use `169.254.169.254`. Does the default-deny egress block handle non-standard metadata endpoints (such as Azure's `168.63.129.16`) or IPv6 metadata addresses (`fd00:ec2::254`) out of the box?
- **Code Ambiguity:** The exact CIDRs blocked by default are not easily discoverable from the API files themselves; we must rely on implementation details inside the controller package, making it harder for platform operators to audit.

## 2. Failed Adoption Recovery Loop
When a `SandboxClaim` attempts to adopt a warm `Sandbox` from a `SandboxWarmPool`, it performs a series of metadata patches using `rawpatch` to change the ownership labels and marks the Pod as adopted:
- **The Question:** If a network failure or node shutdown causes the adoption transaction to fail halfway through (e.g., the claim resource is written but the Pod label patch fails), does the `Sandbox` get orphaned? Can a partially adopted sandbox be accidentally checked out by another concurrent claim, or will it remain stuck in an intermediate state until the next reconcile?
- **Code Ambiguity:** The transaction bounds during adoption in `sandboxclaim_controller.go` are complicated by the fact that Kubernetes does not support multi-object ACID transactions.

## 3. Warm Pool Autoscaling Eviction Behavior
The controller manager has the flag `--enable-warm-pool-eviction=true` (enabled by default) which marks warm pool pods with `cluster-autoscaler.kubernetes.io/safe-to-evict: "true"`:
- **The Question:** If a cluster experiences severe resource pressure, will the cluster-autoscaler aggressively evict warm sandboxes to free up node space, leading to a massive warm pool replenishment loop? How does the controller coordinate with the autoscaler to maintain pool liveness without causing thrashing or API server flood?

## 4. Dual-Stack IP Routing inside the Router
`SandboxStatus.podIPs` supports multiple IPs for dual-stack clusters, and the `sandbox-router`'s informer cache indexes these.
- **The Question:** When routing HTTP/WebSocket traffic, does `sandbox-router` prioritize IPv4 or IPv6, or does it dial them in round-robin fashion? If one of the IP families is slow to bind/configure on the underlying CNI, does it fall back to the other, or does it fail with a 502 error immediately?

## 5. Token Review Authorization Orchestration
The router uses the Kubernetes `TokenReview` API (`sandbox-router/authz/tokenreview.go`) to validate Bearer tokens.
- **The Question:** Where and how do the SDK clients (Go/Python) retrieve the Bearer tokens they present in the `Authorization` header? Does the platform orchestrator expect users to pass their own personal service account tokens, or are there short-lived scoped tokens generated dynamically on the client side?

## 6. GCP Default Compute Service Account Privilege Escalation Risks
Deploying kOps clusters using `--gce-service-account=default` binds the default Compute Engine service account to all node and control plane instances.
- **The Question:** Since the default GCE service account typically holds wide Project Editor permissions, any workload inside the cluster with access to the GCE metadata server (`169.254.169.254`) can acquire high-privilege access tokens. Although `agent-sandbox` enforces strict default egress blocking via NetworkPolicies to the metadata IP, what happens if standard CNI configuration misses these rules or if a compromised control-plane container escapes to the host? How can we enforce the use of custom, least-privileged IAM service accounts for nodes in standard production deployment runbooks?

## 7. Gossip-Based DNS Performance under High Churn
kOps clusters ending with `.k8s.local` use gossip-based DNS resolution instead of a public or private DNS zone.
- **The Question:** Under severe benchmark load (e.g., launching and deleting hundreds of sandboxes per second), does the etcd/apiserver lookup or node-to-node routing latency degrade due to UDP packet loss or gossip protocol propagation delays? How does gossip-based DNS compare in reliability to Google Cloud DNS under sustained high-throughput sandbox adoption churn?
