# Design Note: RepoWatch Kubernetes Controller

## 1. Objective

To create a Kubernetes controller that manages the lifecycle of temporary development environments (`ReviewSandbox`) based on activity in a specified GitHub repository. The controller will watch for new and existing pull requests (PRs) and automatically provision a sandbox environment for them, subject to a concurrency limit.

## 2. Key Features

- **Automated Sandbox Provisioning:** Automatically create a `ReviewSandbox` for each open PR in a watched repository.
- **Concurrency Management:** Enforce a configurable limit on the number of simultaneously active sandboxes (e.g., 3).
- **Resource Lifecycle Management:** Clean up and delete sandboxes when their corresponding PR is closed or merged.
- **Idempotency:** Ensure that a sandbox for a given PR is created only once by using a deterministic naming convention (`<repo>-pr-<pr_number>`).
- **Initial State Reconciliation:** On startup, the controller will scan all existing open PRs and create sandboxes for them up to the concurrency limit.

## 3. Custom Resource Definition (CRD): `RepoWatch`

The controller will act on a new custom resource, `RepoWatch`.

**`RepoWatch` Spec:**

```yaml
apiVersion: review.gemini.google.com/v1alpha1
kind: RepoWatch
metadata:
  name: example-repwatch
spec:
  # The full URL of the GitHub repository to watch.
  # e.g., https://github.com/owner/repo
  repoUrl: "https://github.com/kubernetes-sigs/agent-sandbox"

  # The maximum number of sandboxes to have active (replicas > 0) at any given time.
  maxActiveSandboxes: 3

  # Secret containing the GitHub Personal Access Token (PAT) for accessing the repo.
  githubSecretRef:
    name: github-pat-secret
    key: token
```

**`RepoWatch` Status:**

```yaml
status:
  conditions:
    - type: Ready
      status: "True"
      reason: "ReconciliationSuccessful"
  activeSandboxCount: 2
  watchedPRs:
    - number: 42
      sandboxName: "agent-sandbox-pr-42"
      status: "Active"
    - number: 45
      sandboxName: "agent-sandbox-pr-45"
      status: "Active"
  pendingPRs:
    - number: 46
      status: "Pending"
```

## 4. Controller Reconciliation Logic

The core reconcile loop will perform the following steps:

1.  **Fetch `RepoWatch` Resource:** Get the `repoUrl` and `maxActiveSandboxes` from the spec.
2.  **GitHub API Interaction:**
    - Using the token from `githubSecretRef`, connect to the GitHub API.
    - Fetch all **open** pull requests for the repository specified in `repoUrl`.
3.  **Cluster State Discovery:**
    - List all `ReviewSandbox` resources in the cluster that are owned by this `RepoWatch` instance (using labels/owner references).
    - Count how many of these have `replicas > 0`. This is the `currentActiveSandboxes` count.
4.  **PR Reconciliation:**
    - **Cleanup:** Iterate through the existing sandboxes. For each sandbox, check if its corresponding PR is still open in the list fetched from GitHub.
        - If the PR is closed or merged, delete the `ReviewSandbox` resource. This frees up a slot.
    - **Creation:** Iterate through the list of open PRs from GitHub.
        - For each PR, generate the deterministic sandbox name (e.g., `agent-sandbox-pr-101`).
        - Check if a `ReviewSandbox` with this name already exists.
            - If it **exists**, do nothing.
            - If it **does not exist**:
                - Check if `currentActiveSandboxes < maxActiveSandboxes`.
                - If yes, create a new `ReviewSandbox` resource.
                    - The resource definition will be based on a template (derived from `instance.yaml` and `rgd.yaml`).
                    - The `metadata.name` will be the generated deterministic name.
                    - The `spec.template.spec.containers[0].env` variable for the git URL will be populated with the PR's clone URL.
                    - Set `spec.replicas` to `1`.
                    - Increment `currentActiveSandboxes`.
                - If no (the limit is reached), add the PR to a "pending" list and do nothing.
5.  **Status Update:** Update the `status` field of the `RepoWatch` resource with the current counts of active sandboxes and lists of watched/pending PRs.

## 5. `ReviewSandbox` Creation

- The controller will have a built-in template for the `ReviewSandbox` resource.
- When creating a new instance, it will populate the following fields dynamically:
    - `metadata.name`: `<repo_name>-pr-<pr_number>`
    - `metadata.ownerReferences`: Set to the `RepoWatch` resource.
    - `spec.template.spec.containers[0].env`: An environment variable like `GIT_CLONE_URL` will be set to the `clone_url` of the PR's source branch.

## 6. Future Enhancements

- **Bug Watching:** Extend the logic to also watch for new issues (bugs) and potentially provision a different kind of environment or perform a different action.
- **Configurable Templates:** Allow the `RepoWatch` spec to point to a ConfigMap or another resource containing the `ReviewSandbox` template, instead of having it hardcoded in the controller.
- **Idle Timeout:** Automatically scale down sandboxes (`replicas: 0`) that have been inactive for a certain period to free up "active" slots without deleting the environment entirely.
