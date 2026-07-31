---
name: nothingness-evals
description: Build and operate isolated Nothingness Linux evaluations.
---

# Nothingness Evaluator

**Execute, don't deliberate.** When the user names a model — e.g. "eval gpt-5.4-nano" — run the flow below to completion without asking for confirmation, without re-litigating campaign strategy, and without reading anything beyond this skill and the referenced docs. Ask a question only in two cases: the requested provider/model/thinking triple is genuinely absent from pi's offline registry (a real blocker, not a preference), or a gate fails. Never ask which campaign to resume, whether to re-run a task, or how to handle an ambiguous task outcome — pick the documented default (below) and keep going.

Operate from the repository root. Pi must already work on the host for the requested provider, model, and thinking level. The evaluator reads only `auth.json`, `models.json`, and `settings.json` from `PI_CODING_AGENT_DIR` or `~/.pi/agent`; provider-scoped Azure settings are allowlisted separately. Credential values move only over `docker exec` stdin and are never written to host run artifacts.

## 1. Two mandatory zero-credential gates

Run both, in order, before spending a single admission or candidate token. Report to the user that they passed (or which one failed) — do not skip this report, and do not proceed past a failure.

```
uv run python .agents/skills/nothingness-evals/scripts/verify-offline-baseline.py --build-image
uv run python .agents/skills/nothingness-evals/scripts/verify-runtime-baseline.py
```

The first uses `--network none`, never launches Pi beyond `--version`, verifies the clean fixture, immutable media, offline package resolution, and a full Linux build, then removes its disposable container. The second launches the real Linux debug app on `--network none`, queues evaluator-owned Opus fixtures, and proves play, pause, skip, seek, final playback, spectrum output, screenshot rendering, and zero overflows, then removes its disposable container. If either fails, stop and report the failure — that is the one legitimate reason to not proceed automatically.

## 2. Create the campaign, then hand the user the dashboard — before any task starts

Pick the suite matching the requested model (e.g. `evals/suites/t1-t7-gpt-5.4-mini-medium.json` for `gpt-5.4-mini`). Create the campaign first — a trial can only be recorded against a campaign that already exists:

```
uv run python .agents/skills/nothingness-evals/scripts/campaign.py new evals/suites/<suite>.json --campaign-id <id>
```

This returns a `dashboard_command` (`watch-eval.py <campaign-id>`). Print that command to the user **immediately**, before starting the first task, so they can follow along live in their own terminal. Do not wait until the end of the run to surface it.

## 3. Per-task loop

Run every task in the suite, in suite order, without pausing between tasks to ask whether to continue. For each task:

1. **Start the trial** — generates an identity-bearing run ID and makes the real isolated admission call (prompt is exactly `Reply exactly READY`). Preparation fails outright if pi's offline registry lacks the exact provider/model/thinking triple — that failure is a legitimate stop-and-ask.
   ```
   uv run python .agents/skills/nothingness-evals/scripts/judge-run.py start evals/suites/<suite>.json <task-id> --trial <n>
   ```
2. **Record the run against the campaign immediately** so the dashboard can find it:
   ```
   uv run python .agents/skills/nothingness-evals/scripts/campaign.py add-run <campaign-id> <task-id> <run-id>
   ```
3. **Supervise.** Follow events, inspect, and capture verification evidence on demand:
   ```
   uv run python .agents/skills/nothingness-evals/scripts/judge-events.py <run-id> --after <sequence> --limit 2500
   uv run python .agents/skills/nothingness-evals/scripts/judge-inspect.py <run-id> --runtime --git --processes
   uv run python .agents/skills/nothingness-evals/scripts/judge-verify.py <run-id> --label <name>
   ```
   Send candidate-facing messages only through `judge-control.py steer|follow-up|request`, each with an intervention class, message, and reason. Passive inspection is never an intervention. Interventions are hard-capped at 3 delivered; a 4th is refused (exit `6`) — terminalize the run instead of continuing to steer. Default to **not** intervening unless the candidate is genuinely stuck; do not ask the user whether to intervene.
4. **Finish** when the candidate reaches `candidate awaiting judge`:
   ```
   uv run python .agents/skills/nothingness-evals/scripts/judge-control.py <run-id> finish --reason <reason>
   ```
   Use `abort` only for an invalid/irrecoverable attempt. Never kill Pi or Docker directly.
5. **Collect**:
   ```
   uv run python .agents/skills/nothingness-evals/scripts/judge-run.py collect <run-id>
   ```
6. **Build the scorecard** from `evals/tasks/rubrics/<task-id>.md`: one `met`/`partial`/`unmet` verdict per expectation, each with a one-line justification and an `evidence_ref` naming an observation of exactly the kind (and, where declared, the lens) the expectation's own `**Evidence:**` line requires. Write the scorecard file with the task id and the `rubric_sha256` you read.
7. **Decide**:
   ```
   uv run python .agents/skills/nothingness-evals/scripts/judge-run.py decide <run-id> \
     --validity <validity> --scorecard <path> --notes <rationale> \
     --observation-id <events-id> --observation-id <inspection-id> --observation-id <verification-id>
   ```
   The judge owns validity, the scorecard's verdicts, and the rationale. Outcome and score are never asserted directly — `classify-run.py` computes both deterministically from the scorecard against the hashed rubric, capping the score at 2 if any `required` expectation is unmet.
8. **Clean up**, only after the decision:
   ```
   uv run python .agents/skills/nothingness-evals/scripts/judge-run.py cleanup <run-id>
   ```
9. Move to the next task in the suite. Do not ask whether to proceed.

When every task in the suite is done, build the consolidated report from the real `result.json` files. Do not stop mid-suite to ask about strategy, re-runs, or scope changes — if a task's result looks wrong, record it as-is with an honest note; do not silently discard or re-run without a documented reason (a genuine infrastructure failure, not a disappointing score).

## Sharp edges (cost real time last night — read before you hit them)

- **`judge-events.py` defaults to 100 events per call and does not echo its own `observation_id`.** Read `judge-observations.jsonl` to find the observation ID for a given call. Use `--limit 2500` and keep paging with `--after <next_sequence>` until `next_sequence` stops advancing.
- **`judge-control.py finish` appends events** — the terminal sequence moves after you call it. Page events again *after* finishing, or coverage validation at decide-time will fail for missing terminal coverage.
- **The cited event observations must form one contiguous chain from sequence 0 to `terminal_event_sequence`.** A zero-length batch (`next_sequence == after`, i.e. nothing new arrived) breaks the chain if you cite it as a coverage step — skip it, don't cite it.
- **`classify-run.py` requires:** a cited `inspection` observation with `runtime`, `git`, and `processes` all `true`; a cited `verification` observation with at least one genuinely successful capture (not a content sentinel like `getSemantics` returning "semantics not available"); and, per scorecard entry, an `evidence_ref` of exactly the observation kind (and lens, where declared) that expectation's own rubric line requires.
- **The judge does not assert a score.** It writes per-expectation verdicts (`met`/`partial`/`unmet`) with notes and evidence refs; `classify-run.py` computes `raw`/`penalty`/`adjusted`/band/outcome deterministically from those verdicts against the hashed rubric.

## Reference

- [`references/architecture.md`](references/architecture.md) — container/network/proxy isolation model.
- [`references/run-protocol.md`](references/run-protocol.md) — full lifecycle contract for every script above.
- [`references/scoring.md`](references/scoring.md) — the scoring rubric, evidence-binding rules, and known limitations of the trust model.
- [`../../../evals/README.md`](../../../evals/README.md) — purpose, method, current results, and past-run lessons.
