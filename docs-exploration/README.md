# Repository Exploration Notes Index

This directory contains living documentation maintained to help new and returning contributors ramp up fast on the `agent-sandbox` codebase. These notes represent deep architectural and code analysis, derived directly from the source.

## Documents

- **[architecture.md](architecture.md)** (Updated: Sept 22, 2026) — Detailed technical breakdowns of the Control Plane (CRDs & Controllers) and Data Plane (`sandbox-router`), complete with corrected, fully rendering Mermaid sequence and component diagrams.
- **[questions.md](questions.md)** (Updated: Sept 26, 2026) — Open design trade-offs, security considerations, and implementation ambiguities in warm-pool adoption, routing, and network policies.
- **[code-map.md](code-map.md)** (Updated: Sept 22, 2026) — A directory-by-directory mapping of the repository structure, highlighting the ~20 most critical files and files that are dangerous to edit.
- **[overview.md](overview.md)** (Updated: Sept 22, 2026) — What `agent-sandbox` is, for whom it is built, and why it exists as a solution for secure, sub-second code execution on Kubernetes.

## Deep-Dives & Sessions

- **[sessions/2026-09-26-scale-and-stress-testing.md](sessions/2026-09-26-scale-and-stress-testing.md)** (Updated: Sept 26, 2026) — Deep-dive into scale, stress, and performance testing suites. Covers ClusterLoader2 recipes, E2E benchmarks, worker sizing ratios, refill shaping, and actionable recommendations for improvement.

## Runbooks

- **[runbooks/deploy-kops-s.md](runbooks/deploy-kops-s.md)** (Updated: Sept 24, 2026) — Complete, executable, top-to-bottom runbook for deploying `agent-sandbox` to a self-managed, gossip-based, 3-node kOps cluster on GCP using GCE VMs and Cilium CNI.
