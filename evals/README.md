# Nothingness Evaluator

A benchmark for coding agents. A candidate agent gets a real feature request against
Nothingness — this ~15k-LOC Flutter media controller app — and works it in an isolated Linux
container with no network beyond its model provider. A judge agent then decides whether the
app actually does the thing, **by driving it and looking at it**, not by reading the
candidate's write-up.

## Results

<!-- BEGIN GENERATED LEADERBOARD -->
| Model | Thinking | Date | Eval | Orchestrator/Judge | Orchestrator/Judge cost | Retries | Score | Assisted | Tokens (in/out) | Accepted task cost | Campaign cost | $/point | Report |
| --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- |
| `gpt-5.4-nano` | medium | 2026-08-15 | 1.6.1 | gpt-5.6-luna-high/pi | $0.30 | 2 | **13/21** | no | 427k / 122k | $0.6089 | $1.1899 | $0.0915 | [detail](results/gpt-5.4-nano-medium-20260815-0548/README.md) |
| `gpt-5.4-nano` | medium | 2026-08-14 | 1.5.1 | gpt-5.6-luna-high/pi | $1.25 | 0 | **16/21** | no | 513k / 139k | $0.5888 | $0.5888 | $0.0368 | [detail](results/gpt-5.4-nano-medium-20260814-1944/README.md) |
| `gpt-5.4-nano` | medium | 2026-08-11 | 1.3.0 | claude.opus-5-high | $57.18 | – | **15/21** | no | 488k / 126k | $0.6164 | $0.6164 | $0.0411 | [detail](results/gpt-5.4-nano-medium-20260811-0506/README.md) |
| `gpt-5.4-nano` | medium | 2026-08-10 | 1.3.0 | unrecorded | – | – | **14/21** | no | 377k / 117k | $0.4537 | $0.4537 | $0.0324 | [detail](results/gpt-5.4-nano-medium-20260810-2027/README.md) |
| `gpt-5.4-nano` | medium | 2026-08-10 | 1.0.0 | claude.opus-5-high | $50.56 | – | **11/18** | no | 742k / 167k | $0.8818 | $0.8818 | $0.0802 | [detail](results/gpt-5.4-nano-medium-20260810-0750/README.md) |

`Retries` counts fresh task restarts in the current campaign. `Accepted task cost` uses only the accepted run for each completed task. `Campaign cost` includes accepted runs and retry spend. `Orchestrator/Judge cost` is supplied separately because those agent sessions are outside the measured containers. Regenerate with `leaderboard.py --write`; do not hand-edit between the markers.
<!-- END GENERATED LEADERBOARD -->

One row per campaign, generated from the published `result.json` files and campaign manifest. Every
number in it, and in each linked report, is read from run artifacts; none is typed by hand. **Do not summarise scores
here** — a hand-written recap of the last campaign sat in this file for weeks quoting three
task scores and a total cost that no longer matched anything on disk.

The `Eval` column is the harness version each run was produced under, from
[CHANGELOG.md](CHANGELOG.md) — bump it there whenever a change could move a score or change
what a number means. **Results under different versions are not directly comparable.** Every
run since versioning existed is stamped at prepare time; the first campaign predates it and
carries a backfilled `1.0.0`, flagged as such in its own `result.json`.

Only one model has been run end to end so far. Nothing here supports a broad comparison yet.

## How a campaign runs

The user names a model; nothing else is asked of them.

1. **Host check, then two zero-credential gates.** `check-host.py` verifies the host in one
   pass. `verify-offline-baseline.py` proves the image builds the app offline against a clean
   fixture; `verify-runtime-baseline.py` launches the real Linux app and proves play, pause,
   skip, seek, spectrum, screenshot and zero overflows. Both record what they proved against
   the image id, fixture commit and their own code, so an unchanged image re-verifies in about
   a second instead of ten minutes.
2. **A campaign is created**, and the user gets a dashboard command (`watch-eval.py`) before
   the first task starts.
3. **`campaign.py next` drives the loop.** It returns the next task with no accepted run, plus
   the full brief for it. A judge failure records a retry and starts the task fresh; the second
   failed retry aborts the campaign instead of continuing with contaminated state.
4. **One judge owns each run, end to end** — it starts a fresh task run, watches it live, scores it
   against the rubric, writes its own account, publishes, and tears down its container. It
   works in a git worktree with `evals/results/` deleted, so it can write a result without
   being able to read anyone else's.
5. **The manager supervises and aggregates.** It stands each judge up and steps in only when
   one is blocked. It never scores. `finalize` merges the judges' published runs, regenerates
   each report from the judge's own notes, and rebuilds the table above.

Operational detail is in [the evaluator skill](../.agents/skills/nothingness-evals/SKILL.md)
and [the judge skill](../.agents/skills/nothingness-eval-judge/SKILL.md).

## Setup

The harness needs, on the host (not in the candidate container):

- `docker` (daemon running), `git`, `tar`, `uv`, `ffmpeg`, `pi` on `PATH`. Pi's install
  method doesn't matter — npm global, pnpm, bun, or a bundled artifact all
  work; set `PI_ARTIFACT` if none is found automatically.
- `~/.pi/agent/auth.json`, `models.json`, and `settings.json` all present,
  valid JSON, and mode `0600` (`chmod 600 ~/.pi/agent/*.json`). `models.json`
  may be as bare as `{"providers": {}}` if you have no custom providers, but
  it must exist and not be empty.
- Provider credentials via env — e.g. `AZURE_OPENAI_BASE_URL` and
  `AZURE_OPENAI_API_KEY` for `azure-openai-responses`.

Run `uv run python .agents/skills/nothingness-evals/scripts/check-host.py
--suite evals/suites/<suite>.json` before anything else — it verifies all of
the above plus the requested model triple and image freshness, reports every
failure in one pass with a fix for each, and costs nothing.

## Isolation model

Each task run uses a container built from a pinned image. Preparation exports
the app fixture at commit `5fc7e04` and initializes a one-commit Git
baseline — the candidate never sees repository history. The candidate
container has all Linux capabilities dropped and `no-new-privileges`, and
joins only a fresh internal Docker network. Its only route out is through a
second, equally restricted proxy sidecar that allows HTTPS CONNECT to a
single allowlisted hostname — the exact host derived from the requested
provider's configured `baseUrl` — and rejects literal IPs and other ports.
Provider credentials are never written to container config; they're sent
over stdin to a short-lived bootstrap process at launch. noVNC, used to
observe the running app, is published from the candidate on `127.0.0.1`
only, never exposed beyond the host.

Neither side can look up the answer. The fixture commit carries no rubrics,
suites, published results or evaluator skill — a gate asserts this, so the
candidate cannot read the rubric it is graded against. The judge's worktree
carries the rubrics but no results, so it cannot anchor on another run's score.

## Scoring rubric

Score is an aggregate over a per-task **expectations bundle**, not a judge
gut-number. Outcome is derived from the score; assistance is tracked
separately and never hidden.

Every task ships `evals/tasks/rubrics/<task-id>.md`: an ordered list of
expectations, each with an `id`, a prose `statement`, and a tier —
`required` (the core ask; any unmet `required` expectation caps the run at
`partial`, never a pass) or `secondary` (polish, evidence quality, not
breaking adjacent behavior). The rubric file is hashed into `result.json`
alongside the task manifest, so a score is reproducible against the exact
expectations it was judged under.

The judge records one verdict per expectation — `met` (1.0), `partial`
(0.5), `unmet` (0.0) — each with a justification and a reference to the
supporting observation. From the scorecard:

```
raw       = Σ(credit) / count                     # over all expectations
penalty   = 0.05 × min(delivered_interventions, 3)   # low weight, max 0.15
adjusted  = clamp(raw − penalty, 0, 1)
```

`adjusted` maps to one of four bands, each with a headline score and
outcome:

| `adjusted` | Score | Meaning | Outcome |
| --- | --- | --- | --- |
| ≥ 0.85 | **3** | GOOD — clean, verified, evidence matches | `pass` |
| 0.60–0.85 | **2** | AVG — works, but nudged or rough | `partial` |
| 0.30–0.60 | **1** | BAD — barely; broken or invented behavior | `partial` |
| < 0.30 | **0** | FAIL — didn't do it, or no evidence | `fail` |

Hard rule: any unmet `required` expectation caps the score at 2, regardless
of `adjusted` — a run cannot pass while missing the core ask.

Assistance is a separate field, never folded into outcome: `assisted: bool`
is true iff any intervention was delivered, and `intervention_count` is
hard-capped at 3 — the judge is refused a fourth delivery and must
terminalize the run instead. An assisted pass is still reported as a pass,
and reported as assisted; the two facts sit side by side, never laundered
into one.

## Trust model

The scorecard is the judge's testimony about what it saw. All the machinery
above — frozen rubric hashes, per-expectation evidence binding, genuine-capture
checks, the intervention lock — exists to catch *mistakes*: a capture that
silently failed, a rubric that drifted between authoring and scoring, two
judge processes racing. None of it constrains a judge that deliberately
misreports what it saw; a judge willing to mark every expectation `met`
against a genuine screenshot that doesn't show what it claims defeats any
scheme built on top of its own attestation. That is a property of the trust
model, not a defect to be fixed. Harden against mistakes, not the operator.
Documented, un-patched limitations of this model live in
[`references/scoring.md`](../.agents/skills/nothingness-evals/references/scoring.md)
§ Known limitations.

## The deterministic/agentic split

The agent orchestrates; scripts are its hands; the dashboard is a dumb
renderer. Nothing that requires judgment is scripted, and nothing
deterministic is left to agent narration.

| Deterministic CLI (no judgment) | Agent (no scripts) |
| --- | --- |
| Build/verify image; offline + runtime baselines | Read the pi event stream, understand what's happening |
| Fixture export, container/network/proxy, app-data reset | Drive the app, look at it, decide if the feature works |
| Launch candidate with the frozen prompt | Decide whether to intervene, which class, what to say |
| Stream events; dump runtime/git/process state | Decide valid vs. infrastructure-invalid |
| Deliver an intervention **and record it verbatim** | Assign outcome and score; write the rationale |
| Capture screenshots/semantics on demand | Decide a run is terminal vs. merely stuck |
| Store the agent's decision, schema-validated | Record a retry after an operational failure |
| Track which tasks still have no scored run | |
| Cleanup + prove absence; token/cost accounting | |
| Write campaign progress; render dashboard; render report | |

**Honesty rule:** progress is a side effect of deterministic calls, never
agent narration. The one exception is a `current_activity` string the judge
sets explicitly, because "the judge is thinking" is real information only it
has.

## Guiding principles

These exist to prevent a specific failure this repo already had: hundreds of
lines of scoring machinery built and "frozen" against runs that never
happened.

1. **A run that never ran is worth nothing.** Nothing is "frozen" or
   "release-ready" until a real scored run exercised it. The unit of done is
   a `result.json` with real cost on it.
2. **The judge has eyes, not schemas.** Verification means an agent driving
   the actual app and looking at it. If a judge can't tell whether it worked
   by using the app, the *task* is badly written — fix the task, don't add
   an assertion.
3. **Measure behavior, never implementation.** A check that fails a
   correct-but-different implementation is broken. The now-deleted oracle
   layer hardcoding `key: "void-settings-cassette-variant"` was the
   anti-pattern in one line.
4. **Tasks are real asks in the user's voice.** Terse, like you'd actually
   type. Ambiguous where real life is ambiguous — coping with that is part
   of what's measured.
5. **Assisted is a result, not a rescue.** Interventions allowed, classed,
   recorded. An assisted pass is never reported as unassisted.
6. **Smallest thing that produces a number.** Add machinery only after a
   real run proves it's needed.

## Where things live

Working artifacts for an in-progress run live under `.tmp/evals/<run-id>/`
and are gitignored. Published results live in [results/](results/), one
directory per run, named `<model>-<thinking>-<YYYYMMDD>-<HHMM>` from the
campaign's start time, so the tree is navigable without opening anything and
three runs of one model in a day sit side by side instead of overwriting each
other. Each holds the per-run report plus, per task, the verdict, scorecard,
judge notes, candidate diff and cited evidence.

The harness version lives in [CHANGELOG.md](CHANGELOG.md) and nowhere else —
its topmost `## <x.y.z>` heading is parsed, stamped into every run at prepare
time, and shown per run in the index. There is no `VERSION` file to fall out of
sync, and a bump cannot happen without an entry describing it.
Superseded material — the oracle-based design, prior campaign records, the
macOS field test this benchmark's bands are aligned to — is in
[archive/](archive/).
