# Nothingness Evaluator changelog

The version of the **harness**, not of the app under test. It is the single
source of truth: `common.eval_version()` parses the topmost `## <version>`
heading below, records it into every run at prepare time, and the index table
shows it per run. There is no separate `VERSION` file to drift out of sync, and
a version bump is impossible without an entry here.

Bump when a change could move a score or change what a number means — rubric
semantics, scoring bands, evidence rules, isolation, what the candidate is
given. A typo fix or a clearer error message does not need a bump.
Results published under different versions are not directly comparable; say so
rather than averaging them.

## 1.1.0 — 2026-08-10

- The judge owns its trial end to end (start, observe, score, publish, tear
  down). The manager stands each judge up, unblocks it, and aggregates.
- Fixed the judge sandbox, which could never have worked: `RUNS_ROOT` derived
  from the repository root, so a judge in a worktree looked for its run under a
  path nothing creates.
- `campaign.py next` drives the per-task loop from campaign state instead of a
  numbered list in prose; interrupted campaigns resume exactly.
- Published results are named `<model>-<thinking>-<YYYYMMDD>-<HHMM>`, timed from
  the campaign's start. Same-day repeats previously either refused to publish or
  silently overwrote the earlier run.
- Both zero-credential gates record what they proved against the image id,
  fixture commit and their own code, and skip when all three are unchanged —
  about ten minutes of unchanged re-verification per campaign, now about a
  second. `--force` re-verifies.
- The runtime gate reports the container's state, exit code and OOM flag when
  the desktop never comes up, instead of a bare timeout that read the same
  whether the container was slow or dead.
- Deleted `consolidate.py`. There is no multi-trial aggregation, no pass-rate
  cohort, and no variance or confidence interval: a run is one run, repeats are
  separate rows, and comparing them is a human call.
- The index tracks who conducted each run and what that cost — agent sessions
  outside the measured containers, invisible to the harness, and far larger than
  the candidate spend.

## 1.0.0 — 2026-08-10

Harness state for the first published campaign (`gpt-5.4-nano` medium, seven
tasks, one trial each), at commit `fab6bd2`. Versioning did not exist when that
campaign ran, so its results carry `"eval_version": "1.0.0"` with
`"eval_version_backfilled": true` — the number is assigned from the commit that
produced it, not stamped live like every run since.

- Expectations-bundle scoring: per-task rubrics with `required`/`secondary`
  tiers, hashed into each result; bands 0–3 derived from the scorecard, never
  asserted by the judge.
- Per-expectation evidence binding, contiguous event coverage, genuine-capture
  checks, and a hard cap of three recorded interventions.
- Isolated candidate: pinned image, clean fixture at `5fc7e04`, internal Docker
  network with an exact-host egress proxy, credentials over stdin only.
- Two zero-credential gates: offline build baseline and live runtime baseline.
