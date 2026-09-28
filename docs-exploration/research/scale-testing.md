# Scale Testing Architecture, Presubmits, and Performance Measurements

## Scope & Objectives

This document details how scale and performance load testing are implemented in the `kubernetes-sigs/agent-sandbox` repository. It covers:
1. The architectural engines used to execute load and scalability tests.
2. The specific tests executed as part of pull request (PR) presubmits.
3. The telemetry, lifecycle milestones, and metrics captured across harnesses.
4. The latest documented benchmark measurements, tuning baselines, and historical run data.
5. Items that remain unresolved from a local checkout inspection.

---

## Scale Testing Frameworks & Architecture

The repository employs three distinct scale-testing engines tailored to different testing layers:

```
+-----------------------------------------------------------------------------------+
|                               Scale Testing Engines                               |
+------------------------------------+----------------------------------------------+
| 1. Virtual Nodes (KWOK + CL2)      | 100 fake nodes, API server/controller scale  |
| 2. Cloud Stress Harness (kOps/GCP) | 3-20 real VMs, kernel I/O, CNI, pprof profiling|
| 3. In-Cluster E2E (Kind + Go test) | Go testing.B microbenchmarks, benchstat CSV   |
+------------------------------------+----------------------------------------------+
```

### 1. Virtual Node Scalability (KWOK + ClusterLoader2)
- **Primary Harness Script**: `dev/ci/presubmits/test-e2e-scalability-kwok`
- **ClusterLoader2 Configuration**: `test/benchmarks/config/agent-sandbox-continuous-burst.yaml`
- **Role**: Simulates large node counts (default: 100 virtual nodes via [KWOK](https://kwok.sigs.k8s.io/)) to exercise API server request limits, controller informer cache memory, workqueue depth, and claim adoption latency without container runtime or VM provisioning costs.
- **Tuned API Server Flags**: Sets `max-requests-inflight=2000`, `max-mutating-requests-inflight=1000`, and `etcd=unsafe-no-fsync=true` (`dev/ci/presubmits/test-e2e-scalability-kwok:134-138`).

### 2. Dedicated Cloud Stress Testing (kOps on GCP + `test/stress`)
- **Primary Scenarios**:
  - `test/benchmarks/scenarios/benchmarks-kops-gcp/run`
  - `test/benchmarks/scenarios/benchmarks-kops-gcp-claims/run`
- **Custom Go Load Engine**: Located in `test/stress/` (`main.go`, `phase.go`, `tracker.go`, `stats.go`, `promscrape.go`, `pprof.go`).
- **Phase-Based Workloads**:
  - `fill`: Long-running background sandboxes (`fill-per-node * worker-nodes`).
  - `fill-pct:N`: Tops worker pod utilization up to N% before testing churn (`test/stress/phase.go:49-75`).
  - `probe`: Low-concurrency launches measuring baseline latency.
  - `throughput-mif:N`: Closed-loop churn maintaining up to N sandboxes concurrently in flight.
  - `claims-warm`: Simultaneous burst of SandboxClaims against a provisioned warm pool.
  - `claims-warm-sustained`: Streaming Poisson claim arrival at a target rate (`test/stress/sustained.go:20-60`).
- **Reporting Engine**: `test/stress/generate-report/generate_report.py` uses DuckDB and Jinja2 to generate multi-page static HTML dashboards (covering CRI, etcd, rate limits, Cilium, API server, and flamegraphs).

### 3. In-Cluster Go Benchmarks & Density Tests (`test/e2e/`)
- **Standard Go Benchmarks (`testing.B`)**:
  - `BenchmarkWarmPoolParallelClaim` in `test/e2e/warmpool_benchmark_test.go:43`
  - `BenchmarkChromeSandboxStartup` in `test/e2e/chromesandbox_test.go:109`
  - `BenchmarkChromeSandboxClaimStartup` in `test/e2e/chromesandbox_claim_test.go:45`
  - `BenchmarkRuntimeClassColdStart` in `test/e2e/extensions/runtime_class_bench_test.go:94`
  - `BenchmarkRuntimeClassWarmClaim` in `test/e2e/extensions/runtime_class_bench_test.go:150`
- **Density & Burst Suites**:
  - `TestChromeSandboxDensity` in `test/e2e/extensions/chromesandbox_density_test.go:68`
  - `TestPythonSandboxDensity` in `test/e2e/extensions/pythonsandbox_density_test.go:78`
  - `TestRuntimeClassBurstRecovery` in `test/e2e/extensions/runtime_class_burst_test.go:232`
- **Benchstat Aggregation**: `dev/tools/test-e2e:70-105` runs benchmarks with `go test -bench=. -benchtime=1x -run=^$ ./test/e2e/...` and formats results into `benchmarks.csv` using `benchstat`.

---

## CI Presubmits and Execution Flows

Presubmits are managed via Kubernetes Prow (configured upstream in `kubernetes/test-infra` under `config/jobs/kubernetes-sigs/agent-sandbox/agent-sandbox-presubmits-main.yaml`).

| Presubmit Name | Execution Path | Target Infra | Trigger / Schedule | Purpose |
|---|---|---|---|---|
| `presubmit-agent-sandbox-test-e2e` | `dev/ci/presubmits/test-e2e` | KinD (DinD) | Required on all PRs modifying repo code | Runs all Go E2E tests, density tests, and Go benchmarks (`--suite all`). Outputs `benchmarks.csv`. |
| `presubmit-agent-sandbox-test-e2e-scalability-kwok` | `dev/ci/presubmits/test-e2e-scalability-kwok` | 100 KWOK simulated nodes | Optional / Manual (`/test presubmit-...-scalability-kwok`) | 100 nodes, 1050 warm pool sandboxes, 75 QPS burst (750 claims). Validates controller adoption latency thresholds. |
| `presubmit-agent-sandbox-benchmarks-kops-gcp-claims` | `dev/ci/presubmits/benchmarks-kops-gcp-claims` | kOps GCP (6 worker nodes, Cilium) | Conditional (Triggers on changes to controller, extensions, benchmarks) | Warm-pool adoption latency during a 300-claim simultaneous burst (`STRESS_CLAIMS_WARM=300`). |
| `presubmit-agent-sandbox-benchmarks-kops-gcp-cilium` | `dev/ci/presubmits/benchmarks-kops-gcp-cilium` | kOps GCP (3 workers, 1 CP, Cilium) | Optional / Manual (`/test presubmit-...-cilium`) | Tests Cilium endpoint creation rate limits and pod sandbox datapath under churn. |
| `presubmit-agent-sandbox-benchmarks-kops-gcp-kindnet` | `dev/ci/presubmits/benchmarks-kops-gcp-kindnet` | kOps GCP (Kindnet CNI) | Optional / Manual (`/test presubmit-...-kindnet`) | Tests control plane and sandbox throughput using Kindnet as the CNI baseline. |

### Presubmit Deep Dive: `test-e2e-scalability-kwok`

The KWOK presubmit (`dev/ci/presubmits/test-e2e-scalability-kwok:24-60`) executes the following flow:
1. Spawns a virtual cluster with 100 KWOK nodes (`kwokctl scale node --replicas=100`).
2. Applies CRDs from `k8s/crds/` and launches `cmd/agent-sandbox-controller` with:
   - `--kube-api-qps=1000`, `--kube-api-burst=2000`
   - `--sandbox-concurrent-workers=50`, `--sandbox-claim-concurrent-workers=50`
   - `--sandbox-warm-pool-max-batch-size=300`
3. Waits for `/readyz` and logs indicating reconciler workers have started (`dev/ci/presubmits/test-e2e-scalability-kwok:200-220`).
4. Executes ClusterLoader2 using `test/benchmarks/config/agent-sandbox-continuous-burst.yaml`:
   - Preheats warm pool with 1,050 sandboxes.
   - Triggers continuous burst of 750 SandboxClaims at 75 QPS across 10 seconds.
5. Invokes `dev/ci/presubmits/shared/scrape_controller_metrics.py` to query `:8081/metrics` and validate:
   - Claim Adoption Latency $P_{50} \le 300\text{ ms}$
   - Claim Adoption Latency $P_{90} \le 300\text{ ms}$
   - Claim Adoption Latency $P_{99} \le 500\text{ ms}$
   - Emits test results to `junit_controller-metrics.xml`.

### Presubmit Deep Dive: `benchmarks-kops-gcp-claims`

The claims presubmit (`test/benchmarks/scenarios/benchmarks-kops-gcp-claims/run:25-50`) executes:
1. Acquires a Google Cloud project from the Boskos pool using `resourcectl`.
2. Provisions a kOps cluster (6 worker nodes, c3-standard control plane, Cilium CNI).
3. Pre-warms 300 sandboxes in a `SandboxWarmPool`.
4. Runs `test/stress` with:
   - `--phases=claims-warm`
   - `--claims-warm-count=300`
   - `--client-connections=4` (shards client HTTP/2 streams to prevent client queueing).
   - `--enable-pprof-debug` on controller to bracket the burst with CPU and heap captures.

---

## Telemetry and Metrics Captured

### 1. Controller Internal Prometheus Metrics
- `agent_sandbox_claim_controller_startup_latency_ms`: Histogram of claim creation to `Ready=True` transition. Parsed by `dev/ci/presubmits/shared/scrape_controller_metrics.py:23-64` via bucket interpolation (`sum(...) by (le)`).
- `agent_sandbox_creation_latency_ms`: Informational histogram of pod creation latency.
- `agent_sandbox_claim_controller_startup_latency_ms_count`: Queried via PromQL irate for claim throughput.

### 2. Sandbox Lifecycle Milestone Timestamps (`test/stress/tracker.go:88-150`)
Every sandbox and claim is tracked with client-observed and server-reported timestamps:
- `CreateCalled`: Timestamp immediately preceding the API `Create` invocation.
- `CreateReturned`: Timestamp when the API `Create` call returns.
- `PodCreated`: Timestamp of first watch event for the backing Pod.
- `PodScheduled`: Timestamp when Pod condition `PodScheduled=True` is observed.
- `PodRunning`: Timestamp when Pod phase reaches `Running`.
- `PodReady`: Timestamp when Pod condition `Ready=True` is observed.
- `SandboxReady`: Timestamp when Sandbox condition `Ready=True` is observed.
- `SandboxDeleted` / `PodDeleted`: Timestamps when watch `DELETED` events are observed.

### 3. Decomposed Latency Breakdown (`test/stress/stats.go:73-125`)
Computes aggregate percentiles ($P_{50}, P_{90}, P_{95}, P_{99}$) for:
- `CreateAck`: API write latency (`CreateCalled` $\to$ `CreateReturned`).
- `CreateToPodCreated`: Reconciler pickup time.
- `PodCreatedToScheduled`: Kube-scheduler latency.
- `ScheduledToPodRunning`: Kubelet, image pull, and container creation latency.
- `PodRunningToPodReady`: Container readiness probe latency.
- `PodReadyToSandboxReady`: Status propagation to Sandbox CR.
- `EndToEndReady`: Total duration (`CreateCalled` $\to$ `SandboxReady`).
- `TimeToAllReadySeconds`: Duration from first `Create` call until *every* item in the batch is `Ready`.

### 4. Component Scrapes and Diagnostics
- **Metrics Scraper (`test/stress/promscrape.go`)**: Scrapes Prometheus endpoints from `kube-apiserver`, `kube-controller-manager`, `kube-scheduler`, `agent-sandbox-controller`, `kubelet`, `cilium-agent`, `etcd-main`, `etcd-events`, and `node-exporter` into `metrics.jsonl.gz`.
- **pprof Profiling (`test/stress/pprof.go`)**: Gathers Go CPU and heap profiles from the apiserver and controller during burst phases.
- **Diagnostics Dump (`test/benchmarks/scenarios/benchmarks-kops-gcp/run:430-449`)**: Writes `controller.log`, `pods.txt`, `nodes.txt`, and `top-nodes.txt`.

---

## Benchmark Data and Performance Measurements

### 1. PR-Level Benchmark: Warm-Adoption Latency
Tested on kOps (k8s 1.35.6, e2-standard-16 control plane, 4 pools, 113 replicas/ns, 45/s Poisson arrival rate; `docs/performance-tuning.md:109-122`):

| Configuration | $P_{50}$ Latency | $P_{90}$ Latency | $P_{99}$ Latency | Notes |
|---|---|---|---|---|
| Burst-tuned (`replenish-delay=20s`, no rate cap) | ~57 ms (first 10s) $\to$ ~1.4 s cold | 2.28 s (steady-state) | — | Pool drained after initial burst. |
| **Sustained-tuned** (`replenish-delay=0`, `max-refill-rate=100`) | **92 ms** | **182 ms** | **376 ms** | P50 held flat at 77–116 ms across all six 10s windows. |

### 2. PR-Level Benchmark: Write-Behind Coalescing Window
Tested with 300-claim warm burst + 45/s $\times$ 60s sustained Poisson on a 12-node kOps cluster (`docs/performance-tuning.md:124-145`):

| Metric | Baseline (`window=0`) | `--sandbox-write-behind-window=250ms` | Delta |
|---|---|---|---|
| **Optimistic 409 Write Conflicts** | 5,447 | **3,077** | **$-44\%$ conflicts** |
| **Burst $P_{50} / P_{90}$** | 1,465 ms / 3,201 ms | **1,271 ms / 3,158 ms** | **$-13\% P_{50}$** |
| **Sustained $P_{50} / P_{90}$** | **320 ms / 680 ms** | 507 ms / 1,027 ms | $+58\% P_{50}$ regression |
| **Pod PATCHes OK** | 2,953 | 2,997 | Neutral |

### 3. GKE Live Cluster Concurrency & Flag Sweep
Tested on GKE (k8s 1.36.2, 20 $\times$ e2-standard-16 worker nodes, 75-claim burst from a 150-sandbox warm pool; `docs/performance-tuning.md:52-90`):

| Configuration | $P_{50}$ | $P_{90}$ | $P_{99}$ | Success Rate | Findings |
|---|---|---|---|---|---|
| Baseline (1000/1000/500/100 workers, batch 500) | 50.4 s | 88.2 s | 96.8 s | 75/75 | Cold-start floor on real GKE nodes |
| Worker Sizing 50/50/1/1 + all perf flags | 55.6 s | 95.6 s | 104.5 s | 75/75 | $+11\% P_{50}$ regression; reconcile bottleneck |
| Worker Sizing 1000/1000/500/100 + all perf flags | 52.7 s | 93.5 s | 102.3 s | 75/75 | Worker contention on API server |
| Config E (`--sandbox-warm-pool-max-refill-rate=80`) | 42.2 s | 75.3 s | 82.7 s | 75/75 | **$-15\%$ latency** vs baseline |
| **Config H (Validated Optimal Sustained)** (rate=100, delay=0, workers 200/150/2/1) | **41.4 s** | **74.2 s** | **82.6 s** | **75/75** | Optimal high-throughput profile |
| Config I (`delay=20s`, `rate=100`) | 49.4 s | 204.7 s | 214.5 s | 74/75 | 1 API timeout $\to$ pool drained $\to P_{90}$ spiked to 205s |

### 4. Recorded Empirical Bottleneck Runs (kOps GCP)
Annotated in `test/benchmarks/scenarios/benchmarks-kops-gcp/run:135-235`:
- **Run 2079750013621112832 (8-core CP, Kindnet)**: Apiserver pinned at 5.6–5.7 cores; request latency 34.7 ms; `mif600` throughput capped at 60 claims/s; controller workqueue wait was 445 ms.
- **Run 2079885693798060032 (16-core CP, Cilium)**: Apiserver burned 9.25 cores; request latency dropped to 6.6 ms; `mif600` throughput reached 91 claims/s; controller workqueue wait fell to 3 ms.
- **Run 2080606920242106368 (20 nodes, `pd-standard` spinning disk)**: Pod launch pipeline disk-sync bound; containerd spent 2,718 s blocked across 923k fsync calls; kubelet spent 987 s; `run_podsandbox` rose from ~130 ms to 1.0–1.2 s under load.
- **Run 2080670751672766464 (`pd-ssd` CP and nodes)**: Lifted disk bottlenecks, reaching 151 claims/s with apiserver at 10.5 cores and 8 ms latency.
- **Run 2077526390265090048 & 2077921435870826496 (Cilium defaults)**: Default 0.5/s endpoint-create limit caused 20.8 s mean limiter wait and ~7 s per endpoint create. Overriding limits to 100/s rate, 32 parallel requests, and client-go QPS 50/100 removed this bottleneck.

---

## Open and Unresolved Questions

1. **Transient CI Log Telemetry**: Live metrics from recent pull request presubmits are not persisted in Git; they are written to Google Cloud Storage (`gs://kubernetes-ci-logs/pr-logs/...`). Downloading raw artifacts requires feeding a specific build URL to `test/stress/generate-report/download_results.py`.
2. **Cloud Infrastructure Access**: Re-running the full kOps GCP benchmark scenarios (`benchmarks-kops-gcp-claims`, `benchmarks-kops-gcp-cilium`, `benchmarks-kops-gcp-kindnet`) requires active Boskos GCP project leases and cannot be run purely offline or in an unauthenticated local environment.
3. **Capacity Cliff Baseline on Modern Releases**: While the recipe exists in `dev/load-test/test-recipes/run_capacity_cliff.sh` to determine the maximum Sandbox convergence threshold, the specific cliff number for current controller builds is not hard-coded in the repository documentation.
