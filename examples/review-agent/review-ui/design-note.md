This is a classic "operator" or "controller" pattern in Kubernetes, where you're building a tool to manage other resources (PRs and their associated sandboxes).

Here’s a breakdown of why and how you'd design this system.

### Why You Need a KV Store

You need to store **state** that doesn't live anywhere else:

1.  **Draft Comments:** When a user types a review, it's a draft. If they close the browser, they'll want it to be there when they come back. You'd store this in the KV store.
    * **Key:** `draft:pr:123`
    * **Value:** `"This looks good, but please fix the typo on line 42."`
2.  **PR-to-Sandbox Mapping:** This is the most critical part. When a sandbox is created (likely by your CI/CD system), how does this UI know *which* sandbox to delete for *which* PR? The CI system needs to register this mapping.
    * **Key:** `sandbox:pr:123`
    * **Value:** `sandbox-name-for-pr-123` (or a deployment name, or whatever uniquely identifies the sandbox).
3.  **Application State:** The "Discard" button implies state. If a user "discards" a PR, you're essentially hiding it from their view.
    * **Key:** `user:jane:discarded:pr:123`
    * **Value:** `true`

---

### 🏛️ System Architecture Design

You'll build this as a standard client-server application, running in containers on Kubernetes.

#### 1. The Frontend (UI)
* **What it is:** A React, Vue, or Svelte single-page application (SPA).
* **How it runs:** Served as static files (HTML/CSS/JS) from a simple Nginx or Caddy container.
* **K8s Resource:** A `Deployment` running the Nginx container, fronted by a `Service` (e.g., `pr-ui-svc`).

#### 2. The Backend (API Server)
* **What it is:** A web server written in **Go**, Python (FastAPI), or Node.js. Given your background, Go with the `client-go` library would be a perfect choice.
* **What it does:** This is the brain. It provides a REST or GraphQL API for the frontend.
    * `GET /api/repos`: Fetches all RepoWatch CRs from the kubernetes server and returns a list of CR names
    * `GET /api/repo/<repo>/prs`: Fetches all open PRs from the GitHub/GitLab API for the repo
    * `GET /api/repo/<repo>/prs/123`: Gets details for one PR, *and* queries the **KV store** for any saved drafts or sandbox info.
    * `POST /api/repo/<repo>/prs/123/review`: Takes the comment and the "Approve" action, then posts it to the GitHub/GitLab API.
    * `POST /api/repo/<repo>/prs/123/draft`: Saves the text box content to the **KV store**.
    * `DELETE /api/repo/<repo>/prs/123/`: This is the key K8s integration.
* **K8s Resource:** A `Deployment` for your Go app, fronted by a `Service` (e.g., `pr-api-svc`).

#### 3. The Storage (KV Store)
* **What it is:** A Redis cache.
* **How it runs:** You can deploy the official Redis container image.
* **K8s Resource:** A `StatefulSet` to ensure the data is persistent across restarts, with a `PersistentVolumeClaim` (PVC) for storage. It will also have its own `Service` (e.g., `redis-svc`).

---

### ⚙️ How Key Features Would Work

Here is the flow for your specific button clicks:

#### Fetching the PR List
1.  User opens the UI.
2.  Frontend (React) calls `GET /api/repos`
3.  Backend (Go) API:
    a. List all RepoWatch CRs from kubernetes GVK `review.gemini.google.com/v1alpha1/RepoWatch`
    b. For each CR, store in redis key `url:repo:<.metadata.name>` the URL from `.spec.repoURL`
    c. return the list of Repos { name, url }
3.  Frontend (React) renders tabs for each repo. In each tab, it calls `GET /api/repo/<repo>/prs`
4.  Backend (Go) API:
    a. read from redis `MGET url:repo:repo-name` to get the repo url
    b. Calls the GitHub API (using an API token stored in a K8s `Secret`) to get open PRs for a given repo url
    c. For each PR:
       i. it saves in Redis: `title:repo:repo-name:pr:123` the PR title
       ii. it saves in Redis: `url:repo:repo-name:pr:123` the PR httpurl
       iii. it queries Redis: `MGET draft:repo:repo-name:pr:123 sandbox:repo:repo-url:pr:123 review:repo:repo-url:pr:123`.
       iv. it gets the sandbox CR from kubernetes GVK `custom.agents.x-k8s.io/v1alpha1/ReviewSandbox` with name <repo-name>-pr-123
       v. if sandbox exists, it saves in Redis: `sandbox:repo:repo-name:pr:123` the sandbox name
       vi. It combines this data (PR title, link, draft comment or applied review, sandbox name) and returns it as a single JSON response.
4.  Frontend renders the list in the repo tab

#### "Submit Review" Button
1.  User modifies the comment and clicks "Submit" for PR 123.
2.  Frontend calls `POST /api/prs/123/review` with the comment text.
3.  Backend (Go) API:
    a. Uses the GitHub API `Secret` to post the review to the GitHub PR.
    b. On success, it **creates** the submitted review as a review in Redis: `ADD review:repo:repo-name:pr:123`.
    c. On success, it **deletes** the draft from Redis: `DEL draft:repo:repo-name:pr:123`.
    d. On success, it **deletes** the sandbox from kubernetes. It calls the K8s API to delete the GVK `custom.agents.x-k8s.io/v1alpha1/ReviewSandbox` with name <repo-name>-pr-123.
4.  Frontend UI updates (e.g., shows a "success" checkmark).

#### "Delete" Button
1.  User clicks "Delete" for PR 123.
2.  Frontend calls `DELETE /api/repo/repo-name/prs/123/`.
3.  Backend (Go) API:
    a. Queries Redis: `GET sandbox:repo:repo-name:pr:123`.
    b. delete the sandbox from kubernetes. It calls the K8s API to delete the GVK `custom.agents.x-k8s.io/v1alpha1/ReviewSandbox` with name <repo-name>-pr-123.
    c. On success, it cleans up the Redis key: `DEL sandbox:repo:repo-name:pr:123`.
    e. On success, it cleans up the Redis key: `DEL review:repo:repo-name:pr:123`.
    e. On success, it cleans up the Redis key: `DEL draft:repo:repo-name:pr:123`.

To make this work, your backend `Deployment`'s `ServiceAccount` would need a `Role` (or `ClusterRole`) bound to it that grants it `delete` permissions on `namespaces` (or whatever resource your sandboxes are).

---

### 📦 Summary of Kubernetes Resources

Your `helm` chart or Kustomize layout would look like this:

* **`pr-reviewer-ui/`**
    * `Deployment.yaml` (Nginx)
    * `Service.yaml` (ClusterIP)
    * `Ingress.yaml` (Exposes the UI service)
* **`pr-reviewer-api/`**
    * `Deployment.yaml` (Your Go app)
    * `Service.yaml` (ClusterIP)
    * `ServiceAccount.yaml`
    * `Role.yaml` (Permissions to delete namespaces)
    * `RoleBinding.yaml` (Links the Role to the ServiceAccount)
    * `Secret.yaml` (For GitHub API token)
* **`redis/`**
    * `StatefulSet.yaml`
    * `Service.yaml` (For the API to connect to)
    * `PersistentVolumeClaim.yaml`

This design gives you a robust, scalable application that correctly uses Kubernetes for orchestration and a KV store for managing the specific state your application cares about.

