# Get the eval done

## Context

This branch was supposed to produce a benchmark: give a coding agent a real feature request against this Flutter app, let it work in an isolated container, then check whether the app actually does the thing. One scored run exists — T1 on `gpt-5.4-nano`, `candidate_fail`, score 0, $0.026. That run proves the container/proxy/judge plumbing works.

Everything built after it optimized for auditability of runs that never happened: seven frozen "oracle" contracts, a 509-line campaign state machine with publication barriers, 75 passing tests, a release checklist. None of it executed against a real model. The oracles are the clearest symptom — 416 lines consuming an evidence schema no code emits, invoked by nothing, hashed into fingerprints, unit-tested against handwritten fixtures.

Two concrete defects found while planning, both blocking:

1. **T2–T7 cannot be scored at all.** `classify-run.py:140` hard-requires `artifacts/task-evidence.json` for `validity=valid`, and `collect.py:273` writes it only for `task_id == "t1-playback-smoke-linux"`. Worse, `classify-run.py:147-150` gates the *outcome* on `task_evidence["passed"]` — the oracle overrides the judge, directly contradicting the documented contract that the judge owns the decision.
2. **T6 and T7 are unrunnable as committed.** Their manifests carry `network: {docker_mode: "none", egress: "none"}`, so the candidate has no route to the model. They also dropped `scoring` and `candidate.session_output` present in T1–T5.

Intended outcome: a session where the user says "eval model X", gets a dashboard command, sits back, and ends with scored results plus a consolidated report.

## Guiding principles

These are the deliverable of WP1, not decoration. They exist to prevent the failure above from recurring.

1. **A run that never ran is worth nothing.** Nothing is "frozen" or "release-ready" until a real scored run exercised it. The unit of done is a `result.json` with real cost on it.
2. **The judge has eyes, not schemas.** Verification means an agent driving the actual app and looking at it. If a judge can't tell whether it worked by using the app, the *task* is badly written — fix the task, don't add an assertion.
3. **Measure behavior, never implementation.** A check that fails a correct-but-different implementation is broken. The deleted `settings_contract_oracle.py:65` hardcoding `key: "void-settings-cassette-variant"` is the anti-pattern in one line.
4. **Tasks are real asks in the user's voice.** Terse, like you'd actually type. Ambiguous where real life is ambiguous — coping with that is part of what's measured.
5. **Assisted is a result, not a rescue.** Interventions allowed, classed, recorded. An assisted pass is never reported as unassisted.
6. **Smallest thing that produces a number.** Add machinery only after a real run proves it's needed.

## Division of labor

The agent orchestrates; scripts are its hands; the dashboard is a dumb renderer.

| Deterministic CLI (no judgment) | Agent (no scripts) |
| --- | --- |
| Build/verify image; offline + runtime baselines | Read the pi event stream, understand what's happening |
| Fixture export, container/network/proxy, app-data reset | Drive the app, look at it, decide if the feature works |
| Launch candidate with the frozen prompt | Decide whether to intervene, which class, what to say |
| Stream events; dump runtime/git/process state | Decide valid vs. infrastructure-invalid |
| Deliver an intervention **and record it verbatim** | Assign outcome and score; write the rationale |
| Capture screenshots/semantics on demand | Decide a run is terminal vs. merely stuck |
| Store the agent's decision, schema-validated | Decide whether to retry a task or move on |
| Cleanup + prove absence; token/cost accounting | Decide the campaign is done |
| Write campaign progress; render dashboard; render report | |

**Honesty rule:** progress is a side effect of deterministic calls, never agent narration. The one exception is a `current_activity` string the judge sets explicitly, because "the judge is thinking" is real information only it has.

## Scoring rubric

The score is an **aggregate over a per-task expectations bundle**, not a judge gut-number. Outcome is derived from the score. Assistance is tracked separately and never hidden.

This replaces the deleted oracles with the same rigour minus the brittleness: the assertions are prose a judge evaluates by looking at the app, and each verdict is recorded with its own justification and evidence pointer.

### Expectations bundle

Every task ships `evals/tasks/rubrics/<task-id>.md` containing an ordered list of expectations. Each has an `id`, a prose `statement`, and a tier:

- **`required`** — the core ask. Any unmet `required` expectation caps the run at `partial`; it can never be a pass.
- **`secondary`** — polish, evidence quality, not breaking adjacent behavior.

The rubric file is hashed into `result.json` alongside the task manifest, so a score is reproducible against the exact expectations it was judged under.

### Scorecard

The judge records one verdict per expectation: `met` (credit 1.0), `partial` (0.5), `unmet` (0.0) — each with a one-line justification and a reference to the `judge-verify.py` observation that supports it. The scorecard is stored in `result.json` as `scorecard: [{id, tier, verdict, note, evidence_ref}]`.

```
raw       = Σ(credit) / count                        # over all expectations
penalty   = 0.05 × min(delivered_interventions, 3)   # low weight, max 0.15
adjusted  = clamp(raw − penalty, 0, 1)
```

### Bands

| `adjusted` | Score | Meaning | Outcome |
| --- | --- | --- | --- |
| ≥ 0.85 | **3** | GOOD — clean, verified, evidence matches | `pass` |
| 0.60–0.85 | **2** | AVG — works, but nudged or rough | `partial` |
| 0.30–0.60 | **1** | BAD — barely; broken or invented behavior | `partial` |
| < 0.30 | **0** | FAIL — didn't do it, or no evidence | `fail` |

Hard rule: **any unmet `required` expectation caps the score at 2**, regardless of `adjusted`. A run cannot pass while missing the core ask.

The 0–3 headline stays deliberately aligned with `evals/archive/local-model-field-test/report.md` (FAIL/BAD/AVG/GOOD) so campaign numbers remain comparable with the archived macOS field test.

### Interventions

- `assisted: bool` — true iff any intervention was delivered. Independent of outcome; an assisted pass is reported as a pass **and** as assisted, never laundered.
- `intervention_count: int` — **hard cap of 3**. `judge-control.py` refuses a fourth delivery; the judge must terminalize the run instead. This bounds how much the judge can carry a weak model.
- Penalty weight is intentionally low (0.05) for the first campaign. Revisit after real data — if assisted runs cluster at score 3, the weight is too low.

### Code impact (WP3)

`validate_classification` (`classify-run.py:11-24`) is rewritten: outcome enum becomes `{pass, partial, fail, unassigned}`; the `candidate_fail ⇒ 0` and `pass ⇒ 1..3` rules are replaced by band derivation from the scorecard; `assisted` moves out of the outcome name into its own field. The existing `unassisted` field in `result.json` becomes `assisted` (inverted) — keep one, not both.

## Target model — `gpt-5.4-mini` at `medium`

Decided. The earlier `gpt-5.4-nano` selection rested on the archived field test, but that test used `gpt-5.4-mini-medium` (`notes.md:16,104`); `nano` appears nowhere in it. The only nano datapoint is this repo's T1 run — score 0, never launched the app.

Mini scored 3·3 on the field-test equivalents of T1 and T2, so the gate should exercise the **pass** path, which is exactly what needs proving: pass classification, screenshot evidence for a working feature, and the removed oracle veto.

Cost: mini's field-test T1+T2 was $0.117 + $0.302 ≈ $0.42, under the $1.00 ceiling. Watch Azure quota (`notes.md:226`).

Caveat carried forward: the field test was **macOS with the user driving**. This is **containerized Linux with an agent judge** — strictly harder, so 3·3 is an upper bound, not a prediction. The existing nano T1 result stays as a historical reliability-cohort datapoint; it is not part of this campaign.

## Roles

The orchestrating agent does not write product code. Each work package goes to a Sonnet **worker** subagent, then to a *separate* Sonnet **QA** subagent with no implementation history, per `.agents/skills/qa-handoff` (default mode; two-QA mode for WP3). Ambiguous verdict = FAIL. Max 3 repair rounds. QA gathers its own runtime evidence — the repo has a live harness, so implementer logs are not accepted as proof.

**QA runs against a frozen tree.** Workers with disjoint owner files may run in parallel; review may not overlap them. A reviewer told "any unexpected modification is a FAIL" will correctly fail a tree that other packages are still mutating, and the verdict says nothing about the work under review. Let every concurrent worker land, confirm the tree is quiet, then dispatch QA — and tell the reviewer which files other packages legitimately changed, so it can distinguish those from defects in its own scope.

---

## WP1 — Eval doc and principles (first, blocking)

**Owner files:** `evals/README.md`, `AGENTS.md`

Rewrite `evals/README.md` as the single explanatory doc: what this benchmark measures and why, the isolation model, the deterministic/agentic split table above, the six principles verbatim, the operator flow, and where results live. `evals/README.md:3` currently links `status-report.md`, deleted in WP2 — that link must go. The link to this `plan.md` stays valid.

Add a targeted `## Evals` section to `AGENTS.md` (new `##` after "Python Tooling"; the existing file has an oddly-nested `### WSL2` subsection — do not copy that pattern). Keep it short — it loads into every agent's context. It should say: what the eval is, that the judge is an agent not an oracle, that behavior is measured not implementation, and point at the skill and this plan.

**Acceptance:** a reader with no context understands what the eval does and why oracles were rejected. `AGENTS.md` addition is ≤15 lines.

## WP2 — Demolition

**Delete:** `evals/private/oracles/` (6), `evals/private/references/` (bundles), `scripts/oracles/` (3), `test/evals/oracles/` (3 files, 32 tests), `freeze-t6-reference.py`, `freeze-t7-reference.py`, `campaign-run.py`, `campaign_common.py`, `campaign_report.py`, `watch-campaign.py`, `test/evals/campaign_test.py` (6 tests), `evals/status-report.md`. ~1800 lines.

Audit confirms no inbound references from anything outside the deletion set except `evals/README.md:3`, handled by WP1. `test/evals/evaluator_scripts_test.py` (37 tests) imports none of these and must still pass. `.github/workflows/ci.yml` runs no Python at all — the deletion has zero CI footprint.

**Acceptance:** 37 tests still pass; `flutter analyze` and `flutter test` unaffected; no dangling references (grep clean).

## WP3 — Judge gets authority and eyes (critical path, two-QA)

**Owner files:** `collect.py`, `classify-run.py`, `judge-control.py`, new `judge-verify.py`, `evals/tasks/t6-*.json`, `evals/tasks/t7-*.json`, new mini suite

1. **`classify-run.py`** — remove the oracle veto at lines 147-150. Replace the `task-evidence.json` hard requirement (line 140) with a requirement for *judge verification evidence*: at least one verification observation in `judge-observations.jsonl` cited via `--observation-id`. Rewrite `validate_classification` (lines 11-24) for the new outcome enum and band derivation; accept a `--scorecard <path>` JSON and compute `raw`/`penalty`/`adjusted`/score/outcome deterministically from it rather than trusting a passed-in score. Reject a scorecard whose expectation IDs don't match the hashed rubric file. Keep every other integrity check (cost schema, admission identity, intervention agreement, completion reason) — those are deterministic and correct.
2. **`judge-control.py`** — enforce the hard cap of 3 delivered interventions; refuse the fourth with a distinct exit code.
3. **`collect.py`** — delete the `if metadata["task_id"] == "t1-playback-smoke-linux"` branch (272-277) and `t1_task_evidence()` (211-234). Collection becomes uniformly generic: transcript, diff, logs, git, processes, runtime state.
4. **New `judge-verify.py <run_id> --label <name>`** — the judge's eyes, on demand. Captures into `judge-verifications/<id>/`: `drive.py shoot` PNG, `drive.py inspect` runtime state, `drive.py tree`, `drive.py call ext.nothingness.getSemantics`, `getSettings`. Writes a manifest + sha256s, appends to `judge-observations.jsonl` using the existing observation-ledger pattern from `judge-inspect.py:53-55`. Reuse `common.py` helpers; do not invent a second evidence format.
5. **Fix T6/T7 manifests** — restore `network` to the `internal-proxy`/`allowlist` block used by T1–T5, restore `scoring` and `candidate.session_output`. Confirm T7's 1200s timeout is deliberate.
6. **New suite `evals/suites/t1-t7-gpt-5.4-mini-medium.json`** — same seven-task shape as the nano suite, `requested_model` = `azure-openai-responses` / `gpt-5.4-mini` / `medium`. Suite `id` must satisfy `validate_run_id` (`common.py:46-48`, charset `[A-Za-z0-9_.-]`) since it prefixes every run ID. Leave the nano suites in place.

**Acceptance:** band derivation is unit-tested at every boundary (0.30/0.60/0.85) plus the required-unmet cap; a synthetic run classifies a non-T1 task as `pass`, `partial`, and `fail`; the 4th intervention is refused; `judge-verify.py` produces a real PNG and semantic dump from the live runtime baseline container; oracle veto provably gone; `load_suite` accepts the mini suite.

## WP4 — Campaign bookkeeping and the dashboard

**Owner files:** new `campaign.py`, `watch-eval.py`

A campaign is an **ID plus a directory** — no state machine, no publication barriers. `campaign.py new|add-run|status` writes `.tmp/evals/campaigns/<id>/campaign.json`: campaign ID, model, ordered task list, and per-task run IDs as they're created. The judge calls it; it never decides anything.

Extend `watch-eval.py` rather than writing a new dashboard. It already scans all run dirs by `suite_id` and builds a per-attempt table (`watch-eval.py:60-86`) with tokens/cost/elapsed/activity/state computed per row — group by `task_id` instead of assuming one task, and add a campaign header. Live progress still comes from the container's `progress.json` via `docker exec` (`watch-eval.py:37`); that mechanism works and stays.

**Acceptance:** dashboard renders a 7-row table against fixture run dirs, shows `unknown` for missing cost without inventing totals, shows no fake completion percentage, and survives a task transition.

## WP5 — Task rubrics for T1 + T2

**Owner files:** `evals/tasks/rubrics/t1.md`, `t2.md`

The thing that replaces 14KB of oracle JSON. Each file is the task's **expectations bundle** in the format defined under "Scoring rubric": an ordered list of `required` and `secondary` expectations, each a prose statement a judge can settle by driving the app. Alongside each, the `drive.py` commands that exercise it, what to look at, and what a plausible-but-wrong result looks like — the field test's recurring failure was models declaring success their own screenshots disproved, so each expectation must name the observation that would falsify it.

Expectations describe **behavior only**. Naming a widget key, file, or implementation approach in an expectation is a defect (principle 3).

Prompts stay as committed — T2's is already in the right register. T2/T3 near-duplication is intentional (T3 = T2 + rename) and stays.

**Acceptance:** two Sonnet agents, each handed only the rubric plus a fixed evidence bundle (screenshot + semantic dump) and no repo history, independently produce scorecards that agree on every `required` verdict and land in the same band. Run against both a correct T2 implementation and a plausible-but-wrong one.

---

## GATE — real scored run of T1 + T2 on `gpt-5.4-mini`

Precondition: pi is configured on the host for `azure-openai-responses` / `gpt-5.4-mini` / `medium`. The evaluator reads the host pi config and refuses to prepare if that exact triple isn't in its offline registry.

Sequence: `verify-offline-baseline.py --build-image`, then `verify-runtime-baseline.py`, then T1 and T2 **from the real seven-task mini suite** — not a throwaway gate suite. Supervision via `judge-events.py`/`judge-inspect.py`/`judge-verify.py`; intervention only through `judge-control.py`; then decide, collect, clean up.

Using the real suite means **clean T1/T2 results are the campaign's first two results**, not discarded spend. If they're broken, we replace them and lose ~$0.42 rather than a full seven-task run.

**This gate is the point of the plan.** Nothing downstream is built until two real `result.json` files exist with real cost. Expect a pass — mini scored 3·3 on the macOS equivalents — so a fail signals the harness or the Linux/container delta, not the model.

## WP6 — Report (built from real results, not before)

**Owner files:** new `report.py`, `evals/results/<model>/README.md`

Renders a campaign directory into `report.md`: per-task outcome, score, interventions with classes, tokens, cost, links to evidence and screenshots. Built *against the actual T1+T2 output* from the gate. `consolidate.py` stays as-is for the separate 3-trial reliability cohort.

## WP7 — Rubrics T3–T7, then the full run

Rubrics for the remaining five, then the seven-task campaign, then the report.

---

## Verification

- **Per WP:** adversarial Sonnet QA with independent runtime evidence, per `.agents/skills/qa-handoff`.
- **Test invocation:** `uv run python -m unittest discover -s test/evals -p "*_test.py"`. The default `test*.py` pattern matches nothing here — files are suffix-named.
- **After WP2:** 37 pass; `flutter analyze` clean; `flutter test` 393 pass. WP3 then deletes the 4 obsolete `test_t1_oracle_*` tests along with the code they cover, leaving 33 pre-existing plus WP3's additions.
- **After WP3:** `judge-verify.py` against a live `verify-runtime-baseline.py` container produces a real screenshot and semantic dump.
- **At the gate:** two real `result.json` files, real tokens, real cost, cleanup verified, containers absent.
- **End:** seven results and a `report.md` a reader can understand without opening any JSONL.

## QA outcome on WP3 — trust model, decided

Two independent adversarial reviewers failed WP3 across three rounds. Each round closed the literal exploit and left a materially equivalent one. The pattern is not a series of coding defects; it is a threat-model mismatch worth recording, because it will recur.

**The judge authors the scorecard.** The scorecard is the judge's testimony about what it saw. A judge willing to cite degraded evidence is equally willing to mark every expectation `met` while attaching a genuine screenshot that does not show what it claims. No evidence-binding scheme can constrain that. Graded against an adversarial judge, this package fails indefinitely.

What these controls are legitimately worth is catching **honest mistakes**: a capture that silently failed, a rubric that drifted between authoring and scoring, two judge processes racing. That is the bar they are held to.

Two findings survived that reframing and were fixed:
- **The rubric is now frozen at `prepare-run`**, mirroring `task_contract.manifest_sha256` and enforced by a `validate_frozen_rubric` check. Previously the rubric hash was recomputed at scoring time and compared against a value the scorecard declared about itself — circular, and only capable of catching accidental staleness. A task with no rubric now fails preparation rather than launching unscoreable.
- **Genuine-capture is enforced per scorecard entry**, not only against the aggregate citation list, with an optional lens qualifier (`verification:screenshot`) where one artifact is the whole point of an expectation.

Everything else is documented in `references/scoring.md` § Known limitations rather than patched: the lock is defeated by deleting its own lock file mid-run; nothing verifies a declared evidence kind matches what an expectation's prose actually needs; a deliberate rubric swap with a forged hash is now blocked by the freeze but was not before. These require either a dishonest judge or filesystem interference during a campaign.

**Standing rule:** harden against mistakes, not against the operator. When a QA finding requires the judge to be dishonest, document it and move on — the alternative is unbounded rounds of hardening against a threat this architecture does not have, which is principle 1 in a new costume.

## Gate results — T1, both models, 2026-07-31

Two real scored trials on the rebuilt pipeline. Raw artifacts live under gitignored `.tmp/evals/`, so the numbers are recorded here.

| Model | Score | Outcome | `adjusted` | Assisted | Cost | Tool calls |
| --- | --- | --- | --- | --- | --- | --- |
| `gpt-5.4-nano` | 2 | `partial` | 0.7857 | no | $0.0524 | 61 |
| `gpt-5.4-mini` | 2 | `partial` | 0.7857 | no | $0.1831 | 42 |

Both failed the same `required` expectation (E3, skip) the same way: played a single file, called `next`, playback stopped because no queue was loaded. The judge proved skip works in **both** containers (`setQueue` then `next` moved index 0→1), so this is neither an environment fault nor a capability ceiling. Mini diagnosed the cause precisely and volunteered the remedy without being asked, then did not apply it; nano substituted a direct second play and called it skip. Both disclosed the failure honestly rather than overclaiming.

**Two conclusions worth carrying forward.** First, the env-vs-model control worked: identical scores in identical containers isolate the variable to candidate diligence, not infrastructure. Second, **T1 currently has a low ceiling** — no model has passed it, so it cannot discriminate at the top of the range. That is a property of the task, not a defect to patch blindly; revisit only with evidence from more models.

Cost is not proportional to score: mini spent 3.5× nano for the same result in fewer tool calls.

## What the first real run found

The T1 gate on `gpt-5.4-nano` scored `valid` / `partial` / **2** / unassisted at `$0.052`. It also surfaced four defects that three rounds of adversarial QA had missed entirely, because every one of them only exists when real containers and a real candidate are involved.

| Defect | Why QA could not find it |
| --- | --- |
| **Stale image.** `evals/image/` sources are baked into the image and nothing verified the image matched them. A fix to `candidate.py` silently ran old code in the container; preflight then failed as `pi_admission_failed`, blaming the provider for our bug. | Requires building and running an image. |
| **`judge-verify.py` blind to a non-default run log.** `drive.py` discovers the VM service from `/tmp/flutter_run.log`; the candidate is free to launch with any path, and did. All five captures reported unavailable while the app was alive and drivable. | Requires a candidate that chose its own conventions. |
| **`judge-inspect.py` — identical defect,** and worse: `validate_judge_review` requires a cited inspection with `runtime: true`, so it made a complete scored run unclassifiable. | Same. |
| **T4's rubric cited uncitable evidence.** Three `required` expectations told the judge to use "the candidate's own during-gesture screenshot", but `judge-verify.py` only makes fresh live captures — there is no path to cite a candidate artifact. Every T4 run would have capped at `partial` regardless of quality. | Requires tracing the real evidence pipeline end to end. |

Fixes: a source hash is baked into the image as a label and checked in `prepare-run.py` before any container exists; VM-service discovery moved to `common.discover_drive_endpoint` and shared by both judge scripts, recording *how* the endpoint was found; the admission failure split into five distinct reasons so "check your Azure config" is distinguishable from "we broke our own contract".

**The lesson, stated for the next person:** adversarial review of scoring logic found real defects, but every defect that would have stopped a campaign came from running the thing once. Budget a throwaway live trial before any observed or scored campaign, and treat its cost as the cheapest QA available.

## Risks

- **The judge is the measuring instrument.** Rubrics are the calibration; drift across models is the real threat. WP5's acceptance test (independent agent reaches the same verdict) is the check on it.
- **T6/T7 manifest drift** suggests those two were authored with less care than T1–T5. Treat their first real run as suspect.
- **Eval T4 = field-test T3**, the task no local model completed and only `gpt-5.3-codex` nailed. Expect it to be the hardest cell. Eval T5/T6/T7 have no field-test precedent at all.
