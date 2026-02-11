---
name: github-actions-polling
description: Guidelines for polling GitHub Actions workflow runs via MCP tools. Use when working with CI/CD workflows, monitoring builds, or debugging workflow failures.
---
# GitHub Actions Polling & Feedback Loop

When using GitHub MCP tools to monitor workflow runs (CI/CD feedback loop), avoid tight, wasteful polling.

## Polling Strategy

- **Use coarse polling**:
  - After pushing a commit or triggering a workflow, wait **at least 15–20 seconds** before the first status check.
  - Between subsequent checks, **sleep 10–20 seconds** instead of calling `list_workflow_runs` or `get_workflow_run` in a tight loop.
- **Limit total wait time**:
  - Cap automated waiting for a single commit/workflow run at **5–10 minutes**.
  - If the run is still `queued` or `in_progress` after that, surface the current status to the user and stop polling.

## Tool Usage

- Use `mcp_GitHub_list_workflows` to discover workflow IDs once, then reuse them.
- Use `mcp_GitHub_list_workflow_runs` filtered by:
  - `workflow_id` (numeric ID),
  - `branch` (e.g. `main`),
  - and inspect the most recent run whose `head_sha` matches the target commit.
- Use `mcp_GitHub_get_workflow_run` or `mcp_GitHub_get_job_logs` only **after** a run reaches `status: completed` to inspect failures.

## Troubleshooting Failures

If a workflow run fails (`conclusion: failure`):

1. **Inspect Annotations first**:
   - Often, syntax errors (like invalid YAML or expression errors) appear as annotations on the run summary, not in the job logs.
   - Check the `mcp_GitHub_get_workflow_run` response for fields indicating failure reasons or annotations if available.
   - **Note:** The current MCP tools might not expose annotations directly in `get_workflow_run`. If logs are empty (`total_jobs: 0`), it strongly suggests a **workflow file syntax error** or **startup failure** that prevents jobs from running.

2. **Fetch Logs**:
   - Use `mcp_GitHub_get_job_logs` (with `failed_only: true`).
   - If `total_jobs: 0` is returned, assume it is a syntax/configuration error and **ask the user** to check the "Annotations" or "Summary" in the GitHub UI, as the API might not expose the parser error details.

## Behavior in CI/CD Tasks

- For each CI/CD change the agent makes:
  1. Push changes (or instruct the user to push).
  2. Start a **bounded polling loop** following the timing rules above.
  3. On **success**: clearly report the passing run and link to it.
  4. On **failure**:
     - Attempt to fetch logs.
     - If logs are empty/unavailable, infer a syntax error and **ask the user for the specific error message from the GitHub UI** (as annotations are often the key).
     - Summarize root cause and propose fixes.

## Handling Tool Unavailability or Errors

- If any GitHub MCP tool needed for polling is:
  - unavailable,
  - returns persistent permission errors (403/401),
  - or repeatedly fails for non-transient reasons,
  then the agent **must stop automated polling**, clearly state that status cannot be checked programmatically, and **ask the user for assistance** (e.g. to confirm run status or provide logs/screenshots from the Actions UI).
