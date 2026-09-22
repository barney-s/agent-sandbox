# Overview of Agent Sandbox

`agent-sandbox` is a Kubernetes-native sandbox management system designed to rapidly provision, securely isolate, and route traffic to thousands of ephemeral, short-lived runtime environments (sandboxes). It is built specifically to power AI agent applications, code interpreters, and web scraping runtimes that execute untrusted code.

## Why It Exists

Modern AI agents and developer tools need to run code written by users or LLMs. Executing untrusted code directly on critical infrastructure is a severe security risk. While Kubernetes provides a solid foundation for containerized execution, standard Kubernetes workflows suffer from two major limitations for agentic workloads:

1. **Slow Pod Startup Latency:** Standard Pod scheduling, image pulling, and container startup typically take several seconds (or minutes in auto-scaling clusters), which is unacceptable for interactive user experiences.
2. **Slow Service/DNS Propagation:** Creating a Kubernetes `Service` for every single ephemeral sandbox puts high pressure on the API server and results in slow, unpredictable DNS propagation across CoreDNS.

`agent-sandbox` solves these issues by splitting **provisioning** from **routing**, introducing a layered architecture that delivers secure, isolated environments with **sub-second startup times** and **highly scalable, low-latency routing**.

---

## Who It Is For

- **AI Agent Platforms:** Teams building LLM-based agents that require a secure Python execution environment, terminal emulator, or browser sandbox to accomplish tasks.
- **Interactive Developer Tools:** Platforms that run ephemeral user-provided code, such as browser-based playgrounds, online IDEs, or automated workflow tools (e.g., n8n, LangChain, crewAI).
- **Security-Conscious Platform Teams:** Kubernetes platform administrators who need to expose secure, multi-tenant sandboxing capabilities to application developers while enforcing strict network boundaries, default-deny postures, and automated resource cleanup.

---

## Key Capabilities

- **Secure Pod Isolation by Default:** Restricts `AutomountServiceAccountToken` to `false` by default, enforces strict single-tenant `NetworkPolicy` ingress/egress rules (Default Deny ingress, Internet-only egress), and supports custom security contexts.
- **Sub-Second Warm Pools:** Supports pre-warmed pools of ready sandboxes via `SandboxWarmPool` and `SandboxTemplate` resources, bringing environment checkouts down to sub-second latencies.
- **Stateless Reverse Proxy (`sandbox-router`):** A high-performance, stateless Go router that fans HTTP/WebSocket traffic to thousands of sandboxes using an informer-based Pod-IP cache, completely bypassing the Kubernetes Service/DNS propagation bottleneck.
- **Automated Lifecycle & TTL Expiry:** Provides built-in absolute expiration times (`shutdownTime`) and post-completion cleanup policies (`ttlSecondsAfterFinished`), ensuring that sandboxes are aggressively reaped and do not leak cluster resources.
- **SSRF and Abuse Protection:** The router validates upstream destinations, implements robust server-side request forgery (SSRF) defenses (such as blocking link-local and loopback IPs), and strips sensitive headers like Kubernetes `Authorization` tokens.
