---
name: nothingness-evals
description: Build and operate isolated Nothingness Linux evaluations.
---

# Nothingness Evaluator

**Execute, don't deliberate.** When the user names a model — e.g. "eval gpt-5.4-nano" — run the flow below to completion without asking for confirmation, without re-litigating campaign strategy, and without reading anything beyond this skill and the referenced docs. Ask a question only in two cases: the requested provider/model/thinking triple is genuinely absent from pi's offline registry (a real blocker, not a preference), or a gate fails. Never ask which campaign to resume, whether to re-run a task, or how to handle an ambiguous task outcome — pick the documented default (below) and keep going.

Operate from the repository root. `check-host.py` is the single source of truth for whether the host is ready — not whether pi happens to work interactively on this machine, which proves nothing about the harness. Pi's install method does not matter: npm global, pnpm, bun, or a bundled artifact all resolve; `PI_ARTIFACT` overrides detection if none is found automatically. The evaluator reads only `auth.json`, `models.json`, and `settings.json` from `PI_CODING_AGENT_DIR` or `~/.pi/agent`; provider-scoped Azure settings are allowlisted separately. Credential values move only over `docker exec` stdin and are never written to host run artifacts.

## 0. Verify the host

Before anything else, run the host check against the suite you're about to run:

```
uv run python .agents/skills/nothingness-evals/scripts/check-host.py --suite evals/suites/<suite>.json
```

It checks docker/git/tar/uv, pi resolution, pi config file validity and permissions, provider env vars, the requested model triple, and image freshness — all in one pass, at no cost. If it reports failures, each one carries its own remediation; apply them and re-run until it's clean. That is a legitimate reason to stop and tell the user before proceeding.

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
   uv run python .agents/skills/nothingness-evals/scripts/judge-run.py start evals/suites/<suite>.json <task-id> --trial <n> --campaign <campaign-id> --judge <who-scores-it>
   ```
3. **Hand the trial to an isolated judge.** Spawn a subagent using the `nothingness-eval-judge`
   skill, working in a git worktree with the results tree removed:
   ```
   git worktree add .tmp/judge-<run-id> HEAD && rm -rf .tmp/judge-<run-id>/evals/results
   ```
   Give it only: the run id, the task id, and the rubric path. Never the campaign id, never a
   results path, never the model name — it cannot anchor on what it cannot see. It observes,
   finishes, collects, gathers evidence, scores and decides; it does not publish.

   **Watching is the judge's job, not yours** — it is the only party that can act on what it sees
   by intervening when the candidate is genuinely stuck. Tell it to run `observe` with a Bash
   timeout of at least 15 minutes; on the default 2-minute timeout the call is silently
   backgrounded, its turn ends, and a live run is left unwatched. Do not take observation back
   because the judge stopped early — fix the timeout.

4. **Supervise, don't relay.** The judge scores, writes its own `notes.md`, and publishes into its
   own sandbox. Your job while it works is to check it is alive and unblocked — a container that
   died, a judge stuck on the same step, a run past its timeout — and to step in only then. Do not
   ferry its findings; they are already on disk.

5. **Clean up**, only after publishing:
   ```
   uv run python .agents/skills/nothingness-evals/scripts/judge-run.py cleanup <run-id>
   ```

When every task in the suite is done, merge and aggregate in one command:

```
uv run python .agents/skills/nothingness-evals/scripts/judge-run.py finalize --from-sandbox .tmp/judge-wt
```

It copies the judges' published runs into the results tree, regenerates each run's report (reading
the `notes.md` each judge wrote), and rebuilds the index. Then `git worktree remove .tmp/judge-wt`.

Historically this was three commands to remember; forgetting one left a finished campaign whose
index still said otherwise.

When every task in the suite is done, produce the two documents. **A campaign whose results are
not stored and readable is not finished** — scoring is not the deliverable, a result someone can
act on is.

```
uv run python .agents/skills/nothingness-evals/scripts/report.py evals/results/<model>-<thinking>-<date> --write
uv run python .agents/skills/nothingness-evals/scripts/leaderboard.py --write
```

`report.py` fills in every number (scores, tokens, cost, $/point) and leaves `<!-- judge: ... -->`
placeholders. Replace each with what the judges reported: one paragraph on the run, 1-2 plain
sentences per task on what the model actually did and what was verified, interventions in words,
up to three genuine surprises. Do not restate the table in prose, do not describe the environment
(it lives here), do not describe the tasks (they live in `evals/tasks/` and the rubrics).

`leaderboard.py --write` regenerates the roll-up in this file — one row per run, with cost and
$/point beside the score. Never hand-edit between its markers.


## Sharp edges (cost real time last night — read before you hit them)

- **A fresh clone with a perfectly working `pi` on the host can still fail cold, for reasons `pi` working tells you nothing about.** A bundled-artifact-only pi resolver missed an npm-installed pi (`dist/cli.js`), the harness assumed `~/.pi/agent/npm` and `~/.pi/agent/git` exist (they only appear after `pi install`), and it demanded `models.json` be non-empty, valid JSON, and mode `0600`. The first two are now handled (any pi install layout resolves; absent package caches are a normal clean install, not an error) and the third fails with a specific, self-explaining `unsafe_pi_config_permissions:models.json` — but `check-host.py` catches all of them up front, so run it first instead of debugging blind from an error code.
- **`candidate awaiting judge` is a blocked candidate, not a working one.** It sits there burning its timeout until you call `judge-control.py finish`, and nothing notifies you. `judge-run.py observe` returns the moment that happens — and shows you the run as it goes, so you are not choosing between noticing the end and watching the middle.
- **Prime dependencies before launching the app in the candidate container — `flutter run` has no `--offline` flag.** The recipe `drive.py preflight` prints ends in a bare `flutter run`, which resolves against pub.dev and dies on the egress allowlist with `Proxy failed to establish tunnel (403 destination denied)`. Run `flutter pub get --offline` first (the image is already primed), then `flutter run` unchanged. Passing `--offline` to `flutter run` fails with `Could not find an option named "--offline"`; every candidate session burned turns on this.
- **Relaunching the app needs `DRIVE_FLUTTER_FIFO`, not just `DRIVE_RUN_LOG`.** Read-only calls (`inspect`, `tree`, `call`) discover a live session from the run log alone, but `drive.py restart` needs the input fifo and otherwise fails with ``no /tmp/flutter_input_... fifo; is `flutter run` running?`` — export both env vars together whenever you launch, or the write path breaks while reads keep working.
- **A trial that fails before launch gets a fresh `-attempt-NN` directory, and the failed one still belongs in the campaign.** `judge-run.py start` reports only the run id it picked, not that it incremented over a previous attempt, so `campaign.py add-run` every attempt you start — a task whose attempts are all unrecorded reports "not started" on the dashboard while it is actually running.
- **Expect `judge-run.py start` to take minutes, not seconds.** `prepare-run.py` alone (fixture export, git baseline, `chmod -R`, network, proxy, container, workspace copy) runs 2-5 minutes before preflight even begins, so a shell with a 5-minute timeout will appear to hang. It is not stuck.
- **Read the settings sheet with `getSemantics`, never `getWidgetTree`.** With the sheet open the widget tree is ~280,000 characters against a 128,000 cap, and the rows render last, so they fall past the cutoff entirely. Semantics is a few KB and gives each row as `"label\nvalue"` with `indexInParent` and a rect — consecutive indices with abutting y-ranges is what proves adjacency, and it covers rows scrolled out of view. Both dumps accept `lines=` / `skipLines=` / `maxChars=` for paging, and both report `totalLines`/`totalChars` so you can tell when you are being truncated. Note `drive.py tree N` passes N as a LINE count, not a tree depth.
- **Drag the hero with `key=hero-gesture-surface`.** That key is on the gesture surface itself. `dragByKey` resolves a handler by walking the keyed element and its descendants, so anchoring on `hero-song` or any other in-band key can never reach the detector (they are its children) and falls through to synthetic pointers, which abort on Linux desktop with a `mouse_tracker.dart` assertion and move nothing. Confirm the reply reads `"mode": "descendant-callback"`.
- **Do not use `drive.py window` / `setSetting phoneFrame` to force list overflow.** It swaps the widget type at the app-shell slot and rebuilds everything below. The ten-fixture folder already overflows at the default window size, which is enough for any "scrolled out of view" scenario.
- **`judge-run.py decide` now publishes.** Each judged run is copied to `evals/results/<model>/<task>/trial-N/` (verdict, manifest, scorecard, cited evidence gzipped, screenshots) so results survive outside gitignored `.tmp/` and show up in `git status`. Publishing refuses to overwrite a slot owned by a different run; pass `--force` to `publish-run.py` only when you mean to replace it.
- **`judge-events.py` returns its own `observation_id` — cite that, don't go digging in `judge-observations.jsonl` for it.** It pages 2500 events by default; keep calling with `--after <next_sequence>` until `next_sequence` stops advancing.
- **Cite exactly one events observation per sequence range.** Two cited reads covering the same `after`→`next_sequence` span break the contiguity walk, and `decide` rejects it with `event_coverage_not_contiguous` naming the sequence it expected.
- **`judge-control.py finish` appends events** — the terminal sequence moves after you call it. Page events again *after* finishing, or coverage validation at decide-time will fail for missing terminal coverage.
- **The cited event observations must form one contiguous chain from sequence 0 to `terminal_event_sequence`.** A zero-length batch (`next_sequence == after`, i.e. nothing new arrived) breaks the chain if you cite it as a coverage step — skip it, don't cite it.
- **`classify-run.py` requires:** a cited `inspection` observation with `runtime`, `git`, and `processes` all `true`; a cited `verification` observation with at least one genuinely successful capture (not a content sentinel like `getSemantics` returning "semantics not available"); and, per scorecard entry, an `evidence_ref` of exactly the observation kind (and lens, where declared) that expectation's own rubric line requires.
- **The judge does not assert a score.** It writes per-expectation verdicts (`met`/`partial`/`unmet`) with notes and evidence refs; `classify-run.py` computes `raw`/`penalty`/`adjusted`/band/outcome deterministically from those verdicts against the hashed rubric.

## Reference

- [`references/architecture.md`](references/architecture.md) — container/network/proxy isolation model.
- [`references/run-protocol.md`](references/run-protocol.md) — full lifecycle contract for every script above.
- [`references/scoring.md`](references/scoring.md) — the scoring rubric, evidence-binding rules, and known limitations of the trust model.
- [`../../../evals/README.md`](../../../evals/README.md) — purpose, method, current results, and past-run lessons.
