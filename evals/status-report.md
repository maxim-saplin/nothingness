# Nothingness Evaluator — Status Report

**Date:** 2026-07-30  
**Verdict:** Harness release-ready pending final QA; **no scored seven-task campaign has run yet.**

## Executive Summary

The Linux evaluator harness for a sequential T1–T7 campaign is implemented, frozen, and verified offline/runtime. One promoted **reliability-cohort** result exists (T1 trial 1). The campaign controller, dashboard, reporting, and README index wiring are in place. The next scored campaign remains blocked on **qa-1 + qa-2 same-round PASS** per `evals/plan.md`.

## Pinned Infrastructure

| Item | Value |
| --- | --- |
| Image | `nothingness-eval:t1` |
| Digest | `sha256:bb08b8fde7f78c251fc540ab9eca5d6f32c7422b0cfc58ca78d0b941e9caacd9` |
| Fixture | `5fc7e04` |
| Flutter / Dart | 3.44.0 / 3.12.0 |
| Opus fixtures | 10 immutable tracks |
| Proxy | exact-host allowlist |
| Target model | `azure-openai-responses` / `gpt-5.4-nano` / `medium` |

## Release Gates

| Gate | Status | Evidence |
| --- | --- | --- |
| T1–T7 public manifests | **Done** | `evals/tasks/t1-*.json` … `t7-*.json` |
| T2–T7 frozen oracle contracts | **Done** | `evals/private/oracles/*.json` (`status: frozen`) |
| T3–T7 reference bundles | **Done** | `evals/private/references/*/` with `result.json`, semantic evidence, screenshots/logs |
| I1 seven-task suite | **Done** | `evals/suites/t1-t7-gpt-5.4-nano-medium.json` |
| P4 campaign controller | **Done** | `campaign-run.py`, `campaign_common.py` |
| P5 campaign dashboard | **Done** | `watch-campaign.py` |
| P6 reports + README index | **Done** | `campaign_report.py`; auto-index on publish; `--reindex` from results |
| P7 synthetic campaign tests | **Done** | `test/evals/campaign_test.py` (6 tests) |
| Evaluator script tests | **Done** | 37 passing |
| Oracle contract tests | **Done** | 32 passing (P2/P3/settings) |
| Offline baseline | **Pass** | `verify-offline-baseline.py` |
| Runtime baseline | **Pass** | `verify-runtime-baseline.py` (health wait extended to match entrypoint) |
| Suite validate | **Pass** | 7 tasks, all oracles frozen |
| Final qa-1 + qa-2 | **Not done** | Required before first provider-scored campaign |
| First scored T1–T7 campaign | **Not started** | Operator must pick campaign ID + ceilings |

## Promoted Results (Real)

### Reliability cohort — T1 only (`1/3` valid trials)

| Field | Value |
| --- | --- |
| Path | `evals/results/gpt-5.4-nano/t1-playback-smoke-linux/trial-1/` |
| Validity | `valid` |
| Outcome | `candidate_fail` |
| Score | `0` |
| Interventions | 1 correction |
| Candidate tokens | 535,839 |
| Combined cost | $0.02561524 |

Candidate did not launch the Linux app or execute play/pause/skip/seek after one correction. Environment was independently verified healthy pre-launch.

### Seven-task campaign

**None.** Prior entries under `evals/results/.../campaigns/` were synthetic controller-test artifacts and have been removed before this commit.

## Work Completed This Cycle

1. **T6/T7 oracle freeze** — reference patches, host oracles, semantic/screenshot evidence, freeze scripts.
2. **Campaign harness (I1 + P4–P7)** — sequential controller, budget pause, retry cap, publication/archive paths, synthetic test matrix.
3. **Verification** — offline + runtime baselines pass on pinned image.
4. **README wiring** — `evals/README.md` and per-model README update on campaign publish; `campaign-run.py report --reindex` rebuilds from published trials.

## Operator Runbook (First Scored Campaign)

```sh
# 1. Validate
uv run python .agents/skills/nothingness-evals/scripts/campaign-run.py validate \
  --suite evals/suites/t1-t7-gpt-5.4-nano-medium.json

# 2. Start (pick fresh timestamp campaign ID)
uv run python .agents/skills/nothingness-evals/scripts/campaign-run.py start \
  --suite evals/suites/t1-t7-gpt-5.4-nano-medium.json \
  --campaign-id gpt-5.4-nano--t1-t7-gpt-5.4-nano-medium--<YYYYMMDDTHHMMSSZ> \
  --candidate-admission-cost-ceiling-usd 1.00 \
  --token-ceiling 5000000

# 3. Observe
uv run python .agents/skills/nothingness-evals/scripts/watch-campaign.py \
  --campaign <campaign-id> --once

# 4. Per task: judge supervises → collect/decide/cleanup → sync
uv run python .agents/skills/nothingness-evals/scripts/campaign-run.py sync \
  --campaign <campaign-id>

# 5. Budget pause resume (explicit)
uv run python .agents/skills/nothingness-evals/scripts/campaign-run.py resume \
  --campaign <campaign-id> [--allow-unknown-cost] [--token-ceiling N]

# 6. Final report + README index
uv run python .agents/skills/nothingness-evals/scripts/campaign-run.py report \
  --campaign <campaign-id> --reindex
```

## Test Summary

| Suite | Count |
| --- | ---: |
| `evaluator_scripts_test.py` | 37 |
| `campaign_test.py` | 6 |
| `p3_oracle_test.py` | 10 |
| `p2_gesture_navigation_oracle_test.py` | 11 |
| `settings_contract_oracle_test.py` | 11 |
| **Total** | **75** |

## Remaining Before Scored Run

1. qa-1 + qa-2 handoff on this commit (max three rounds).
2. Operator selects campaign ID and `$1.00` / `5,000,000` ceilings.
3. No concurrent evaluator containers (`docker ps --filter label=nothingness.eval=true`).

## Out of Scope (Unchanged)

- Three-trial-per-task reliability cohort completion (21 valid trials).
- Cumulative single-session candidate track.
- amd64 image publication.
