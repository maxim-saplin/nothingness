# Nothingness Evaluator

This evaluator compares coding agents on real Nothingness Flutter tasks that require code changes and live-app feedback. Each trial runs in an isolated Linux container against a frozen fixture, task manifest, and image; the task suite and architecture are described in [plan.md](plan.md). Current release status is in [status-report.md](status-report.md).

Pi must already be installed and configured for the exact requested model. The committed suite manifest is the independent request contract; configured alternatives are never substituted. Operational workflow is in [the evaluator skill](../.agents/skills/nothingness-evals/SKILL.md).

The judge actively follows the actual Pi event stream, inspects the app and workspace, records any intervention, and assigns validity and score from the complete evidence. Deterministic task checks support that judgment but do not replace it. Infrastructure-invalid and unassigned runs retain diagnostics without a candidate score. Three independently judged valid trials are required for a comparable reliability-cohort result.

The evaluator records preflight admission cost separately from candidate cost, then reports their combined total when provider pricing is available; unavailable pricing remains `unknown`. It also records requested and selected model identities, Pi/config/image/task fingerprints, elapsed times, tool activity, judge commands, transactional intervention states, and digest-verified judge observations. Candidate-derived artifacts are redacted, including structured keys and filenames, and scanned in unpublished staging before collection creates the final artifact directory. Valid judge coverage is derived from contiguous event sequences in the verified evidence rather than trusted cursor metadata. Cleanup verifies and journals that the candidate container is absent after removal. A compact CLI dashboard is available for user observation; the judge uses richer structured events and inspection commands.

Working artifacts live in `.tmp/evals/<run-id>/`: `run.json`, `admission.json`, `interventions.json`, `artifacts/`, `summary.json`, and manually classified `result.json`. Consolidated, reviewed results belong in [results/](results/); historical material is in [archive/](archive/).

## Current Results

- [GPT-5.4 Nano](results/gpt-5.4-nano/README.md): T1 reliability cohort trial 1, valid candidate failure, score `0` (`1/3` trials). Seven-task campaign harness ready; no scored campaign yet.
