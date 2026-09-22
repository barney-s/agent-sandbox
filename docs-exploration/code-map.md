# Code Map

This document maps the directory layout of `agent-sandbox` and highlights the ~20 most critical files in the codebase, along with structural warnings for files that are dangerous to edit.

---

## Directory-by-Directory Layout

```text
/workspaces/agent-sandbox/
├── api/v1beta1/             # Core API definitions (Sandbox CRD)
├── cmd/                     # Entrypoints for controllers and documentation generators
│   ├── agent-sandbox-controller/  # Main operator binary
│   └── metrics-docs-gen/    # Automated metrics doc generator
├── controllers/             # Reconcilers for the core Sandbox API
├── extensions/              # Extension APIs & Controllers (Claims, Templates, Warm Pools)
│   ├── api/v1beta1/         # Extended API definitions (claims, templates, warm pools)
│   └── controllers/         # Extended reconcilers (and concurrency/expectation queues)
├── sandbox-router/          # Data plane: Stateless reverse proxy written in Go
│   ├── authz/               # K8s TokenReview, scoped tokens, and authentication logic
│   ├── cache/               # Informer-based Pod-IP liveness lookup cache
│   ├── cmd/                 # Entrypoint for the router binary
│   ├── server/              # HTTP/WebSocket reverse proxy routing logic
│   └── proxy/               # Upstream dialers, retriers, and HTTP transport
├── internal/                # Shared internal helper packages
│   ├── lifecycle/           # Sandbox & Claim TTL expiration checks
│   ├── rawpatch/            # High-performance hand-marshaled metadata patching
│   ├── metrics/             # Prometheus/OTel controller metrics
│   ├── tlsutil/             # TLS and mTLS configuration helpers
│   └── utils/               # Common string and slice utilities
├── clients/                 # Language-specific SDKs (Go, Python, TypeScript)
├── docs/                    # Extensive technical and operational documentation
├── examples/                # Quickstarts and configurations for various use-cases
└── helm/                    # Helm charts for deploying the system
```

---

## The ~20 Files That Matter Most

Below are the most critical files in the repository, organized by functional area.

### 1. Entry Points
- **`cmd/agent-sandbox-controller/main.go`:** The controller manager entry point. Parses flags, configures API connections, sets up informer caches, and registers the reconcilers with the manager.
- **`sandbox-router/cmd/main.go`:** The entry point for the stateless `sandbox-router` data-plane proxy. Sets up certificates, caching, and authenticators.

### 2. Core APIs & Controllers
- **`api/v1beta1/sandbox_types.go`:** Declares the schema for `Sandbox` (the core CRD that reconciles directly into a Kubernetes Pod, PVs, and optional Service).
- **`controllers/sandbox_controller.go`:** Implements `SandboxReconciler`. Handles the translation of `SandboxSpec` into active workloads, updates status conditions, and handles graceful absolute expiration.
- **`controllers/writebehind_requeue.go`:** Manages write deferral/write-behind, coalescing multiple rapid status and label updates on Pods to prevent hot-looping the API server.

### 3. Extended APIs & Controllers
- **`extensions/api/v1beta1/sandboxtemplate_types.go`:** Schema definitions for `SandboxTemplate`, managing the network boundary policies and environmental restrictions.
- **`extensions/controllers/sandboxtemplate_controller.go`:** Reconciles `SandboxTemplate` and automatically sets up shared `NetworkPolicy` objects based on template isolation specs.
- **`extensions/api/v1beta1/sandboxwarmpool_types.go`:** Schema definitions for the `SandboxWarmPool` controller, which pre-warms resources to eliminate cold startup delays.
- **`extensions/controllers/sandboxwarmpool_controller.go`:** Reconciles the warm pool size, triggers scaling up/down, handles replacements for stale sandboxes, and implements updating strategies (`Recreate`/`OnReplenish`).
- **`extensions/controllers/warmpool_expectations.go`:** Prevents race conditions and duplicate creation/deletion commands in warm pool scaling via replica expectations, mirroring replica-set scale mechanics.
- **`extensions/api/v1beta1/sandboxclaim_types.go`:** Schema definitions for `SandboxClaim`, which lets SDKs checkout low-latency environments.
- **`extensions/controllers/sandboxclaim_controller.go`:** Reconciles claims by adopting pre-warmed Sandboxes from warm pools or cold-starting custom ones, updating liveness, and processing TTL reaps.

### 4. Data Plane (`sandbox-router`)
- **`sandbox-router/server/server.go`:** Implements the proxy HTTP/WS server, routing incoming requests, managing headers, and rewriting WebSocket `Origin` headers.
- **`sandbox-router/cache/cache.go`:** Implements the high-speed Pod-IP informer cache. Resolves Sandbox names/UIDs to active Pod IPs in O(1) time.
- **`sandbox-router/authz/authorizer.go`:** Core abstraction for verifying requests against K8s TokenReviews and enforcing access policies.

### 5. Infrastructure & Utilities
- **`internal/rawpatch/rawpatch.go`:** Optimizes hot checkout loops. Compiles hand-marshaled metadata JSON merge patches (annotations/labels) at O(patch) speed, bypassing expensive `DeepCopy+MergeFrom` reflection.
- **`internal/lifecycle/expiry.go`:** Shared logic for determining when `Sandbox` or `SandboxClaim` resources exceed their TTLs.
- **`Makefile`:** Core orchestrator of compilation, mock generation, CRD generation, and development deployment loops.
- **`go.mod`:** Declares the Go environment, compiler toolchain requirements, and dependency locks.

---

## Dangerous Files (Modify with Extreme Care)

Certain parts of the codebase implement high-concurrency, performance-sensitive, or security-sensitive features. Modifying them can lead to critical bugs.

### 1. Concurrency Controls
*   **`extensions/controllers/warmpool_expectations.go`**
    *   **Why it's dangerous:** This file implements expectations tracking to prevent controllers from spamming API creations before the informer catches up. Bugs here will result in massive over-provisioning (infinite create loops) or scaling locks.
*   **`controllers/writebehind_requeue.go`**
    *   **Why it's dangerous:** Coalesces writes. Mistakes in calculating deferral windows or tracking state will cause status sync delays, stale Pod details, or silent failures where the controller ceases to requeue tasks.

### 2. High-Performance Hot Paths
*   **`extensions/controllers/sandboxclaim_controller.go`**
    *   **Why it's dangerous:** This is the core "warm adoption" hot path. Under high checkout loads, tiny race conditions or locking errors can lead to "double adoptions" (the same warm sandbox assigned to two different claims) or high lock contention.
*   **`internal/rawpatch/rawpatch.go`**
    *   **Why it's dangerous:** Since it manually serializes JSON string blocks for speed instead of using standard Go structs/reflection, minor edits to string templates can lead to malformed JSON payloads. This bypasses structural type safety entirely.

### 3. Edge-Security & Network Plane
*   **`sandbox-router/server/server.go` & `sandbox-router/authz/tokenreview.go`**
    *   **Why it's dangerous:** The router is exposed directly to external HTTP traffic. Edits to header validation, SSRF IP class screening, or Bearer Token stripping will expose internal Kubernetes endpoints or cloud metadata servers (`169.254.169.254`) to untrusted execution environments.
