# Nothingness Evaluator

This is a benchmark for coding agents. A candidate agent gets a real feature
request against Nothingness — this ~15k-LOC Flutter media controller app —
and works it in an isolated Linux container. A judge agent then decides
whether the app actually does the thing, by driving it and looking at it.
Operational steps are in
[the evaluator skill](../.agents/skills/nothingness-evals/SKILL.md).

Status: the harness (container, proxy, judge tooling) has completed one full
seven-task campaign — see "Current Results" below. Only one model has been
run end to end so far; nothing here should be read as a broad comparison.

## Setup

The harness needs, on the host (not in the candidate container):

- `docker` (daemon running), `git`, `tar`, `uv`, `pi` on `PATH`. Pi's install
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

Each trial runs in a container built from a pinned image. Preparation exports
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
| Store the agent's decision, schema-validated | Decide whether to retry a task or move on |
| Cleanup + prove absence; token/cost accounting | Decide the campaign is done |
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
   correct-but-different implementation is broken. The
   `settings_contract_oracle.py:65` hardcoding
   `key: "void-settings-cassette-variant"` is the anti-pattern in one line
   (see below; the oracle layer has since been deleted).
4. **Tasks are real asks in the user's voice.** Terse, like you'd actually
   type. Ambiguous where real life is ambiguous — coping with that is part
   of what's measured.
5. **Assisted is a result, not a rescue.** Interventions allowed, classed,
   recorded. An assisted pass is never reported as unassisted.
6. **Smallest thing that produces a number.** Add machinery only after a
   real run proves it's needed.

## Why oracles were rejected

An earlier design tried to make scoring deterministic with frozen JSON
"oracle" contracts and Python that replayed a candidate's recorded actions
against them — around 416 lines across three oracle scripts. It never
worked as a verification system: the oracles consumed an evidence schema no
collection code emitted, were invoked by nothing in the run pipeline, and
were unit-tested only against handwritten fixtures standing in for real
runs. One of them, `settings_contract_oracle.py:65`, hardcoded a check for
`action == {"type": "tap_by_key", "key": "void-settings-cassette-variant", ...}`.
That check passes only if the candidate happens to name a specific widget
key. A candidate that builds the identical user-visible feature with a
different key, a different widget tree, or a different settings-page layout
fails it. That is the anti-pattern this benchmark exists to avoid: an oracle
measures *how* a candidate implemented something, never *whether* the
feature works.

The replacement has no oracle layer. Verification means a judge agent
driving the running app — tapping, seeking, taking a screenshot, reading the
semantics tree — and forming a verdict against a prose expectation. If that
verdict can be disputed, the fix is a better-written expectation or a better
observation, never a script that inspects the diff or replays a recorded
action.

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

## Gate results — T1, both models, 2026-07-31

| Model | Score | Outcome | `adjusted` | Assisted | Cost | Tool calls |
| --- | --- | --- | --- | --- | --- | --- |
| `gpt-5.4-nano` | 2 | `partial` | 0.7857 | no | $0.0524 | 61 |
| `gpt-5.4-mini` | 2 | `partial` | 0.7857 | no | $0.1831 | 42 |

Both failed the same `required` skip expectation identically. The judge
proved skip works in both containers, which isolates the failure to
candidate diligence, not the environment. T1 currently has a low ceiling —
no model has passed it yet.

## Lessons from the first live run

A throwaway live trial surfaced four defects that three rounds of
adversarial QA had missed entirely, because each only exists once a real
container and a real candidate are involved:

| Defect | One-line summary |
| --- | --- |
| Stale image | Container ran old candidate code and reported the resulting failure as a provider/admission problem, not a build bug. |
| `judge-verify.py` blind to a non-default log path | `flutter run` logging somewhere other than the assumed default left every capture reporting "unavailable" while the app was alive and drivable. |
| `judge-inspect.py` — same defect | Made a scored run unclassifiable outright, since a cited inspection with `runtime: true` is required. |
| T4 rubric cited uncitable evidence | Required expectations told the judge to use "the candidate's own screenshot", but the pipeline only ever produces fresh judge-captured evidence — there is no such artifact to cite. |

**Lesson:** run a throwaway live trial before any scored campaign starts.
Adversarial review of scoring logic finds real defects, but every defect
that would have stopped a campaign came from running the thing once — it is
the cheapest QA available.

## Operator flow

The user names a model for a session. The judge agent runs the task suite in
sequence against that model, driving each trial through preparation,
candidate work, verification, and decision. A compact CLI dashboard
(`watch-eval.py`) shows live progress — model, task, elapsed time, tokens,
cost, latest activity — for the user to observe without interfering. Output
is a consolidated report per model once real scored results exist.

## Where things live

Working artifacts for an in-progress run live under `.tmp/evals/<run-id>/`.
Consolidated, reviewed results belong in [results/](results/), one directory
per model. Superseded material — the oracle-based design, prior campaign
attempts, the macOS field test this benchmark's bands are aligned to — is in
[archive/](archive/).

## Current Results

- [GPT-5.4 Nano, medium reasoning](results/gpt-5.4-nano-medium/README.md):
  the first full T1-T7 campaign, one trial per task, fully unassisted (zero
  interventions delivered across all seven runs). Scores: T1 `0` (fail),
  T2 `3` (pass), T3 `3` (pass), T4 `2` (partial), T5 `2` (partial), T6 `3`
  (pass), T7 `1` (partial) — total cost $0.6996. The pattern is consistent
  across the campaign: this model passes code-change tasks (T2, T3, T6) and
  fails or partials the tasks that require it to actually drive the live
  app (T1, T7 never launched the app at all; T4 and T5 launched it but each
  had a required expectation the judge's own live drive falsified). No
  other model has been run through the full suite yet.
