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
