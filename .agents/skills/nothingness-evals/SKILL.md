---
name: nothingness-evals
description: Build and operate isolated Nothingness Linux evaluations.
---

# Nothingness Evaluator

**Changing this harness means adding a changelog entry.** `evals/CHANGELOG.md` holds the version, in its topmost `## <x.y.z>` heading — it is stamped into every run at prepare time and shown per run in the index. Bump it whenever a change could move a score or change what a number means (rubric semantics, scoring bands, evidence rules, isolation, what the candidate is given); a typo or a clearer error message needs no bump. Never add a `VERSION` file — the changelog is the source, so the number and the reason for it are one edit.

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

Together they cost about ten minutes on a cold image and about a second afterwards: each records what it proved against the image id, the fixture commit and its own code, and skips when all three are unchanged (`"skipped": "unchanged_since_last_pass"`). Re-verify on purpose with `--force`. **Do not skip them by hand** — they are cheap now precisely so they never have to be.

## 2. Create the campaign, then hand the user the dashboard — before any task starts

Pick the suite matching the requested model (e.g. `evals/suites/t1-t7-gpt-5.4-mini-medium.json` for `gpt-5.4-mini`). Create exactly one campaign for the requested provider/model/thinking triple by default:

```
uv run python .agents/skills/nothingness-evals/scripts/campaign.py new evals/suites/<suite>.json --campaign-id <id>
```

For an intentional variability attempt after a completed campaign, pass `--allow-repeat` and use a new campaign id. Keep each campaign's results separate; do not combine attempts into one campaign or silently replace an existing result.

This returns a `dashboard_command` (`watch-eval.py <campaign-id>`). Print that command to the user **immediately**, before starting the first task, so they can follow along live in their own terminal. Do not wait until the end of the run to surface it.

**noVNC is one URL per campaign.** `campaign.py new` reserves a host port and returns `novnc_url`; every task (and retry) of that campaign binds the same `127.0.0.1` port. Print it once as a markdown link (`[live GUI](<novnc_url>)`) when the campaign is created — do not reprint a new URL per task. The page is dead between tasks until the next container is up; refresh after `start`. `watch-eval.py` repeats that same campaign URL on its `Live GUI` line.

Then start the watchdog, so an orphaned run reaches you instead of waiting to be noticed. It prints one line per state change on stdout, so run it however your harness streams a long-running command (a background/monitor facility if it has one, otherwise a second terminal you glance at):

```
uv run python .agents/skills/nothingness-evals/scripts/watchdog.py <campaign-id>
```

It reports a candidate stuck in `awaiting_judge`, a run near its deadline, and a container still up with no judge attached. An orphan is discarded and recorded as a retry; no judge is re-attached. It exits when the campaign is complete or aborted.

## 3. Per-task loop — ask the campaign what's next, never a list you keep in your head

**You do not run tasks. Judges do.** Your job is to stand each fresh run up, notice when one is stuck,
and aggregate at the end. A judge owns one fresh run only; it never attaches to a run left by another
judge. If the judge or parent is interrupted, record a retry and restart the task from a clean container.

Loop until `next` reports `"done": true`:

```
uv run python .agents/skills/nothingness-evals/scripts/campaign.py next <campaign-id>
```

It returns the next incomplete task and the whole brief for it: `task_id`, `retry`, `suite_path`,
`rubric_path`, `timeout_seconds`, `judge_wall_seconds`, `sandbox`, `create_sandbox_command`,
`judge_environment`. Never pick the next task yourself. A task is done only when it has one valid
scored `result.json`; a failed run must be recorded with `campaign.py retry` before a fresh run can
start.

For each task `next` hands you:

1. **Create the judge's sandbox** with the command it printed:
   ```
   uv run python .agents/skills/nothingness-evals/scripts/judge-sandbox.py create <sandbox>
   ```
   A worktree with `evals/results/` deleted — the judge can write a result without being able to
   read anyone else's. It refuses if the harness has uncommitted changes, because a worktree is
   pinned to HEAD and would silently run the old code.

2. **Spawn a judge subagent** on the `nothingness-eval-judge` skill. Give it the assignment block —
   `suite_path`, `task_id`, `campaign_id`, rubric path, its working directory (`sandbox`),
   `NOTHINGNESS_EVAL_RUNS_ROOT` from `judge_environment`, and **`judge_wall_seconds` from `next`** —
   **plus [`references/judge-brief.md`](references/judge-brief.md) verbatim, every time, unchanged.**

   Passing that file verbatim is not a nicety: judges that learn the environment at different rates
   are not scoring under the same conditions, and across models that silently breaks the comparison.
   Learned something new? Edit the brief, do not paste it into one judge's prompt.

   **`judge_wall_seconds` is the judge's session/tool timeout.** It is 10 minutes prepare + the
   candidate's `timeout_seconds` + 20 minutes to evidence/decide/publish. Never spawn a judge whose
   wall clock is ≤ the candidate budget. `gpt-5.4-nano-medium-20260815-0548` burned two t4 retries
   and one t6 retry that way: judges died at 30 minutes against a 30-minute candidate, so scoring
   never happened and the candidate was billed twice. If the harness hard-caps below
   `judge_wall_seconds`, stop and tell the user — a short judge against a long candidate is an
   infrastructure retry with the candidate already billed. Do not `Await`/block the judge under a
   shorter cap; background it and watch `watchdog.py`.

   The judge **starts its own fresh run**, observes it, scores it, publishes into its sandbox and
   cleans up its container. Expect `start` to take about one to three minutes before the candidate is even live.
   The `start` JSON still carries `novnc_url`; it is the campaign URL, not a new one. If the user's
   tab is stale from the previous task, tell them to refresh — do not paste a different link.
3. **Supervise, don't relay.** While the judge works, your only job is to notice it is stuck: a
   dead container, a judge repeating the same step, a run past its timeout, or watchdog reporting a
   container up with no judge attached. That last one is an orphan *now* — record the retry, do not
   wait for a 30-minute parent timeout. Step in then and only then. Do not ferry its findings —
   they are already on disk. Do not take observation back because the judge stopped early; the
   cause is almost always a Bash timeout shorter than the run, which silently backgrounds `observe`
   and ends its turn. Tell it to use at least 15 minutes for each `observe` call (that is not the
   judge's wall clock — see `judge_wall_seconds` above).

**Never score a run yourself.** If a judge or parent fails, do not attach another judge. Clean the
failed run, record `campaign.py retry <campaign> <task> --run-id <run> --reason <reason>`, and let
`next` allocate the fresh task run. Two failed retries abort the whole campaign.

When `next` reports `"done": true`, merge and aggregate in one command — one `--from-sandbox` per
judge, or a glob:

```
uv run python .agents/skills/nothingness-evals/scripts/judge-run.py finalize --campaign <campaign-id> --from-sandbox .tmp/judge-<campaign-id>-*
```

It copies every judge's published run into the results tree, regenerates each run's report (reading
the `notes.md` each judge wrote), and rebuilds the index. Then remove the sandboxes:

```
for s in .tmp/judge-<campaign-id>-*; do uv run python .agents/skills/nothingness-evals/scripts/judge-sandbox.py remove "$s"; done
```

Historically this was three commands to remember; forgetting one left a finished campaign whose
index still said otherwise.

When every task in the suite is done, produce the report, the orchestrator record, and the leaderboard. **A campaign whose results are
not stored and readable is not finished** — scoring is not the deliverable, a result someone can
act on is.

First create `evals/results/<campaign>/orchestrator.json`, even when the orchestrator cost is not available:

```
cat > evals/results/<campaign>/orchestrator.json <<'JSON'
{"orchestrator":"<model>-<reasoning_level>/pi","cost_usd":"N/A"}
JSON
```

Use the `<model>-<reasoning_level>/pi` naming convention shown above, for example
`gpt-5.6-luna-high/pi`. If the harness knows it is running under Pi and exposes the
parent session, the optional helper can discover the parent and matching Pi subagent
costs and replace `N/A` with the combined value:

```
uv run python .agents/skills/nothingness-evals/scripts/pi-orchestrator-cost.py evals/results/<campaign>
```

The helper uses `PI_SESSION_FILE`, `PI_MODEL`, and `PI_REASONING_LEVEL` by default. Pass
`--session-file`, `--async-root`, or `--orchestrator` when the harness does not expose those
environment values. If no helper is available, leave `N/A` for the user to fill manually.

```
uv run python .agents/skills/nothingness-evals/scripts/report.py evals/results/<campaign> --write
uv run python .agents/skills/nothingness-evals/scripts/leaderboard.py --write
```

`report.py` fills in every number (scores, tokens, accepted-task cost, campaign cost including retries,
$/point) and leaves `<!-- judge: ... -->` placeholders. Replace each with what the judges reported: one paragraph on the run, 1-2 plain
sentences per task on what the model actually did and what was verified, interventions in words,
up to three genuine surprises. Do not restate the table in prose, do not describe the environment
(it lives here), do not describe the tasks (they live in `evals/tasks/` and the rubrics).

`leaderboard.py --write` regenerates the roll-up in this file — one row per campaign, with retries,
accepted-task cost, campaign cost, and $/point beside the score. Never hand-edit between its markers.


## Sharp edges (cost real time last night — read before you hit them)

- **A fresh clone with a perfectly working `pi` on the host can still fail cold, for reasons `pi` working tells you nothing about.** A bundled-artifact-only pi resolver missed an npm-installed pi (`dist/cli.js`), the harness assumed `~/.pi/agent/npm` and `~/.pi/agent/git` exist (they only appear after `pi install`), and it demanded `models.json` be non-empty, valid JSON, and mode `0600`. The first two are now handled (any pi install layout resolves; absent package caches are a normal clean install, not an error) and the third fails with a specific, self-explaining `unsafe_pi_config_permissions:models.json` — but `check-host.py` catches all of them up front, so run it first instead of debugging blind from an error code.
- **`candidate awaiting judge` is a blocked candidate, not a working one.** It sits there burning its timeout until you call `judge-control.py finish`, and nothing notifies you. `judge-run.py observe` returns the moment that happens — and shows you the run as it goes, so you are not choosing between noticing the end and watching the middle.
- **Prime dependencies before launching the app in the candidate container — `flutter run` has no `--offline` flag.** The recipe `drive.py preflight` prints ends in a bare `flutter run`, which resolves against pub.dev and dies on the egress allowlist with `Proxy failed to establish tunnel (403 destination denied)`. Run `flutter pub get --offline` first (the image is already primed), then `flutter run` unchanged. Passing `--offline` to `flutter run` fails with `Could not find an option named "--offline"`; every candidate session burned turns on this.
- **Relaunching the app needs `DRIVE_FLUTTER_FIFO`, not just `DRIVE_RUN_LOG`.** Read-only calls (`inspect`, `tree`, `call`) discover a live session from the run log alone, but `drive.py restart` needs the input fifo and otherwise fails with ``no /tmp/flutter_input_... fifo; is `flutter run` running?`` — export both env vars together whenever you launch, or the write path breaks while reads keep working.
- **A failed run is not resumed.** Clean it, record one minimal retry reason and cost, and start the task fresh. The campaign allows at most two retries per task; the second failed retry aborts the campaign.
- **A judge whose wall clock is ≤ the candidate budget will die mid-observe.** `campaign.py next`
  prints `judge_wall_seconds` (10 min prepare + task `timeout_seconds` + 20 min score). That number
  is the judge subagent timeout. A 30-minute parent against a 30-minute candidate billed two t4
  retries and one t6 retry on `gpt-5.4-nano-medium-20260815-0548` before anyone scored. If the
  harness cannot grant that wall, do not spawn.
- **Expect `judge-run.py start` to take one to three minutes, not seconds.** `prepare-run.py` streams the fixture into the container, primes dependencies, and brings up network/proxy before preflight's admission probe — give `start` at least a ten-minute tool timeout. It is not stuck.
- **Read the settings sheet with `getSemantics`, never `getWidgetTree`.** With the sheet open the widget tree is ~280,000 characters against a 128,000 cap, and the rows render last, so they fall past the cutoff entirely. Semantics is a few KB and gives each row as `"label\nvalue"` with `indexInParent` and a rect — consecutive indices with abutting y-ranges is what proves adjacency, and it covers rows scrolled out of view. **Paging does not exist on the pinned fixture:** `getWidgetTree` there accepts only `depth` and hard-truncates at 128,000 chars from the top; `skipLines=`/`maxChars=` are silently ignored (they were added later, at harness HEAD). There is no way to reach the settings rows through the tree at all — `getSemantics` is the only path. Note `drive.py tree N` passes N as a LINE count, not a tree depth.
- **`dragByKey` cannot drive the hero on the pinned fixture, and it lies about it.** At the fixture commit `_invokeDragInSubtree` calls `_walkSubtree` *without* `includeSelf`, so the anchor must be an **ancestor** of the `GestureDetector` — and the hero has no such key (`hero-gesture-surface` exists only at harness HEAD; the fixture has `hero-tap-ring`, `hero-swipe-flash`, `hero-seek-hud`, all inside the detector). `kind=mouse` aborts with a `mouse_tracker.dart` assertion; **`kind=touch` returns a success payload while moving nothing**. Never accept that payload as proof of movement. Use real X11 input via XTEST (`libXtst` is in the image) — it also lets you hold the button down and capture a true mid-gesture instant. Anything in these docs that describes app widget keys is describing HEAD; verify against the fixture commit with `git show <fixture>:<path>` before trusting it.
- **Do not use `drive.py window` / `setSetting phoneFrame` to force list overflow.** It swaps the widget type at the app-shell slot and rebuilds everything below. The ten-fixture folder already overflows at the default window size, which is enough for any "scrolled out of view" scenario.
- **`decide` scores; it does not publish.** The results store has one writer. The judge runs `decide` (verdicts and validity), then `publish` into its own sandbox; the manager's `finalize --campaign` completes the one campaign, copies accepted tasks into `evals/results/<campaign>/<task>/`, records campaign costs, and rebuilds the reports and index.
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
