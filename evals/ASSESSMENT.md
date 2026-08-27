# Structural assessment — does the concept hold, and is it worth scaling?

**Snapshot:** 2026-08-27, commit `7fa9500a`, over 40 published campaigns / 280 task-runs in
[results/](results/). This is a dry run being judged as a dry run: the point is not how any model
scored, it is whether the design is worth building on.

Run-to-run spread and judge-to-judge spread are *expected* at this stage and are not the headline —
they are in [§ Appendix](#appendix-the-noise-numbers) for reference. This report is about failures
**intrinsic to the design**: the ones more runs, better prompts, or a stronger judge will not fix.

It quotes no individual campaign's score; [README.md](README.md) rightly forbids that here. Every
figure is an aggregate recomputed from `results/*/*/result.json` and `scorecard.json` — see
[§ Recomputing](#recomputing).

---

## Verdict

**The concept holds and is worth scaling.** The core bet — that a judge agent driving the real app
and looking at it beats assertions over a candidate's write-up — pays off, and it pays off cheaply.

But the harness currently throws away most of what it collects. It runs an hour of agent work,
captures a full event trail, diffs, screenshots and semantics dumps, has the judge render 8–10
separate verdicts, computes a continuous score — and then publishes **one integer per task**. The
supervision signal is condensed by orders of magnitude at the last step, and the thrown-away part is
already sitting on disk.

That is the headline. [DIMENSIONS.md](DIMENSIONS.md) is the fix applied to the existing corpus —
seven axes over all 280 runs, no new campaigns. It does not make the benchmark more precise (that
was tested; see § Intrinsic failure 1), but it does make it say *what* went wrong, which is what
you need before choosing where to spend on tasks or judges.

Two intrinsic limits are worth knowing before committing: the suite has about **four** effective
independent tasks, not seven (§3), and it is calibrated to small models with **no headroom above
"adequate"** (§4). Neither is fixed by adding more of the same tasks.

---

## What the design gets right

Worth stating plainly, because these are the parts that are hard to buy and easy to lose:

- **The judge has eyes.** The corpus contains repeated cases the rubrics were written to catch — a
  candidate declaring success over a screenshot that, read plainly, shows the old behavior. No
  assertion suite catches that. This is the load-bearing idea and it works.
- **The artifact discipline is real.** Every published result parses, is schema-versioned, and is
  hash-bound to its task manifest and rubric. All 7 rubrics have exactly one `rubric_sha256` across
  37 campaigns — **zero silent rubric drift**, which is the failure mode most eval suites die of.
- **The isolation model holds.** Candidate at a pinned fixture with no repo history, no rubrics in
  its tree, one allowlisted egress host; judge in a worktree with `results/` deleted so it cannot
  anchor on another run's score.
- **No publication bias.** Of 31 campaigns in `.tmp/evals/campaigns`: 28 complete, 2 running,
  1 aborted — and the aborted one was re-run and published.
- **The economics work** (§7). Precision is affordable; the binding constraint is orchestration
  effort, not spend.

---

## Intrinsic failure 1 — supervision is condensed into one digit

This is the big one. Per task, the pipeline produces:

- a full pi event trail (the candidate's own tool calls and outputs),
- a git diff of everything it changed,
- judge-driven screenshots, widget trees, semantics dumps, runtime state, overflow reports,
- 8–10 individually-argued expectation verdicts with evidence references,
- token counts, cost, wall time, turn counts,
- a continuous `raw`, a `penalty`, and a continuous `adjusted` in [0,1].

Published per task: **one integer, 0–3.** Then seven integers are summed into one integer out of 21.

Three separate losses, all avoidable, none requiring a single new run:

1. **`adjusted` is computed and discarded.** It is stored in `result.json` and then flattened to a
   4-band integer, and the band mapping is a knife edge for most runs — half sit within one
   expectation verdict of a different band (appendix). Recovering it is free and makes reports
   legible, but do not expect precision from it: measured in
   [DIMENSIONS.md](DIMENSIONS.md) § "What this does not fix", the continuous axes carry the *same*
   relative noise as the integer (coefficient of variation 0.107 either way). The noise is in the
   run, not in the quantization.
2. **Distinct qualities are summed.** The rubrics already separate "the feature works" (`required`)
   from "the evidence is good and nothing adjacent broke" (`secondary`), then average them into one
   score. A model that ships working code with sloppy proof and one that ships broken code with
   beautiful proof can land on the same digit.
3. **Dimensions that are already measured never reach the score.** Cost, tokens, wall time,
   intervention need, and — most interesting — whether the candidate verified its own work.

On that last point: t4's E1/E4/E6 exist specifically to ask *did the candidate look at its own
change while it was happening?* They are met 1/34, **0/34** and 2/34 times. Right now that reads as
"three impossible required items that cap the task at 2" (§4). Read as a dimension instead, it is
the **most discriminating signal in the entire suite** — the one thing essentially no run does — and
it is currently spent as a flat penalty.

Same for honesty. Several rubrics are explicitly calibrated against "declared success, screenshot
disproves it." Whether a candidate's write-up matches what the judge independently saw is a
first-class axis, cheaply derivable from artifacts already published, and it is currently folded
into the same digit as everything else.

**Suggested minimum vector per task:** `works` · `verified-itself` · `write-up-matches-reality` ·
`nothing-adjacent-broke` · `cost` · `wall-time` · `needed-help`. All seven are derivable from
existing artifacts. None needs a new campaign.

## Intrinsic failure 2 — the suite's own natural experiment fails

t3 **is** t2 plus one extra requirement (rename a setting to exactly `color scheme`). Same app, same
region of the codebase, same required work, strictly harder.

Across 34 campaigns their scores correlate at **r = −0.03.**

Two tasks that are near-duplicates by construction carry no shared signal. That is not sampling
noise you can average away — it says the per-task digit is dominated by run-level chance rather than
by the difficulty of the ask. It is the cleanest single piece of evidence in the corpus that the
current 0–3 output is too thin a readout, and it was free: the experiment was already sitting in the
suite.

Full task-to-task correlation matrix, 34 campaigns:

```
        t1     t2     t3     t4     t5     t6     t7
t1    1.00   0.23   0.36   0.22   0.10   0.46   0.30
t2    0.23   1.00  -0.03   0.23  -0.03  -0.08  -0.08
t3    0.36  -0.03   1.00   0.12  -0.14   0.37   0.47
t4    0.22   0.23   0.12   1.00   0.11  -0.17  -0.02
t5    0.10  -0.03  -0.14   0.11   1.00   0.16   0.18
t6    0.46  -0.08   0.37  -0.17   0.16   1.00   0.12
t7    0.30  -0.08   0.47  -0.02   0.18   0.12   1.00
```

Mostly 0 to 0.2, with negatives. The seven tasks are not seven readings of one ability.

## Intrinsic failure 3 — there are about four effective tasks, not seven

```
t1  smoke-test play/pause/skip/fast-forward       — no source change required
t7  queue 10 fixtures, shuffle, one transition    — no source change required
t2  cassette variant controls below screen setting
t3  = t2 + rename one setting                     — near-duplicate of t2
t4  swipe-to-seek feedback rework
t5  conditional accessible jump-to-now-playing    — the only one given 2700s
t6  long-metadata layout hardening
```

t1 and t7 measure *operating the app and reporting honestly* — a real and valuable capability, but a
different one from writing the feature. t3 duplicates t2. That leaves **three genuinely distinct
feature-implementation tasks**, all in the Flutter UI layer, all on the same screen family, all with
the same 1800s budget and the same driving tool.

Consequence for the "add more tasks" question, and it is the important one: **adding more tasks of
this same class reduces noise but does not extend range.** Noise falls as 1/√n; discrimination
between strong models does not move at all, because no task in the suite is hard for a strong model.

## Intrinsic failure 4 — no headroom above "adequate"

Two independent ceilings, both structural:

- **Task-level.** t4 has never scored 3 in 37 campaigns and t6 has scored 3 once, because each has
  `required` expectations met 0–6% of the time, and any unmet `required` caps the task at 2. The
  reachable maximum is **19, not 21** — and the best total ever observed is exactly 19.
- **Band-level.** The top band is `adjusted ≥ 0.85`. Everything from "adequate" to "flawless"
  collapses into a 3. There is no way for a strong model to score above a competent one.

So the scale is calibrated to distinguish *bad from mediocre*, which is what it was built for and
what it does. Observed totals span 7–19, all from two families of small models. Nothing has ever
demonstrated that a strong model lands at 19–21 and a weak one at 10 — the top third of the range is
unvalidated, and by construction partly unreachable.

## Intrinsic failure 5 — the judge is an instrument with no way to measure it

The design already acknowledges it cannot constrain a *dishonest* judge, and treats that as a
property of the trust model rather than a defect. Fair. But there is a separate and fixable gap: no
mechanism exists to score a judge **at all**, honest or not.

No candidate run has ever been judged twice, so nothing in 280 runs separates "the candidate did
differently" from "the judge saw it differently." More importantly for scaling: if you want to
experiment with judges — cheaper judges, different harnesses, judge ensembles — you currently have no
dependent variable to optimize against.

This is the cheapest high-value thing to add, because it needs no new candidate runs. You have 259
scored runs with full artifacts. Mutate a handful into **known-bad** cases with ground truth you
control — revert the feature but keep the write-up, swap in a screenshot from the wrong scale, leave
a build broken, claim a persisted setting that isn't — and a judge's score becomes *did it catch the
seeded defect*. That turns judge quality into a number and makes "experiment with judges" a real
workstream instead of taste.

Related, and trivial: `result.json`'s `judge` field is free text with 90+ distinct values across 280
runs (`copilot`, `worker`, `judge-t3-retry0`, `cursor-grok-4.6-t2`, …). The judge *model* lives only
in `orchestrator.json`. You cannot currently group runs by judge without joining files.

## Intrinsic failure 6 — everything is open, with no held-out set

The repo is public (`github.com/maxim-saplin/nothingness`). Public and permanent are: all 7 task
prompts, all 7 rubrics in full, and 40 campaigns of judge notes describing exactly what passing
looks like.

One thing is *not* leaked, and it's worth being precise: **the repo does not publish reference
solutions.** The fixture commit `5fc7e04` has 81 commits after it, but only one touches `lib/`, and
that one adds a driving-harness key (`hero-gesture-surface`), not a task solution. So a model with
the repo memorized gets the questions and the marking scheme, not the answers.

That is still enough to matter, because the rubrics are unusually explicit — they name the failure
modes to avoid, and in t4's case they hand over the working technique ("drive the gesture with real
X11 input, `libXtst` is in the image, ~30 lines of `ctypes` is enough"). A future model trained on
this repo has read that hint.

For a dry run this is fine. For anything used to compare model generations over time it is a
correctness problem, and the fix is structural, not incremental: split the suite into a **public
set** (t1–t7, already burned — keep it as the worked example and the onboarding path) and a
**held-out set** that never lands in a public tree: separate private repo, rubrics never committed
here, results published as scores only.

## §7 Economics — the good news

Cost of precision, using the observed spread and recent judge costs:

```
target 95% CI on a model's mean     campaigns    task-runs    ~total cost
              ±3 points                  2            14           $21
              ±2 points                  3            21           $31
              ±1 point                  12            84          $124
              ±0.5 points               48           336          $494
```

**About $124 to place a model to within a point.** That is cheap enough that the concept scales, and
it is the strongest argument for continuing.

The structural oddity is that judging costs ~14x the candidate ($8–12 per campaign recently, against
$0.05–1.14 for the candidate; judge spend has hit $49). That is intrinsic to "the judge has eyes" and
is not a defect — but it means the right thing to optimize is **$ per unit of discrimination**, and
the lever is judge efficiency, not candidate budget. It also means cheap-judge experiments have a
large payoff, which loops back to §5: you need judge scoring before you can safely make the judge
cheaper.

One more constraint worth designing around: at 7 tasks × ~30–45 min per task, a campaign is a
half-day of wall time. Twelve campaigns for ±1 point is a week of elapsed time unless campaigns run
concurrently. Wall-clock, not dollars, is what will actually gate scaling.

---

## Recommended scaling order

Strictly ordered — each step makes the next cheaper.

**1. Turn the score into a vector.** No new runs. Done — see [DIMENSIONS.md](DIMENSIONS.md),
generated by `dimensions.py` over all 280 published runs.

Be clear about what it bought, because this was tested rather than assumed: it buys **diagnosis,
not precision.** The axes carry the same relative noise as the integer and do not separate
`gpt-5.4-nano` medium from high any better than the score does. What they do give is the *reason*
behind a number — t4, for instance, reads as 1.64/3 ("can barely do it") but decomposes to 81%
`works`, 59% `proof`, 3% `self-ev`: models mostly build the feature and almost never watch
themselves build it. That is a different problem, with a different fix, than "the task is too
hard", and the integer cannot tell the two apart.

Remaining work on this axis: extend `self-ev` beyond t4 (only one rubric currently asks the
question, and at 3% it is the most discriminating one in the suite), and open the per-run event
trail to separate app-driving calls from file edits.

**2. Add judge scoring via seeded known-bad runs.** No new candidate runs. Gives you a dependent
variable for every judge experiment that follows, and quantifies how much of the observed spread is
the judge.

**3. Build a difficulty ladder, not more of the same.** Three tiers: one a competent model should
always pass (regression floor), one that currently separates (the t4/t5/t6 class), one no current
model passes — multi-file refactors, cross-platform work, a real performance regression to find, a
concurrency bug. Range is what the suite lacks; more mid-difficulty UI tasks add none.

**4. Split public and held-out.** Keep t1–t7 public as the worked example. New tasks land held-out
by default; publish scores, never rubrics.

**5. Fix the ceilings.** Repair or demote t4/E1,E4,E6 and t6/E6,E7 (or restate the denominator as
19), and split the top band so "flawless" is distinguishable from "adequate". Do this *after* step 1,
since a vector score makes the band question much less load-bearing.

**6. Instrument $/discrimination and wall-clock per campaign** as first-class outputs, then start
cheap-judge experiments against the step-2 benchmark.

### What not to scale yet

- **More repeats of the same 7 tasks past n≈3.** You already know the answer to ±2 points; further
  repeats buy precision on a quantity too compressed to be worth measuring precisely.
- **More reasoning-effort arms.** medium vs high on one model differs by 0.14 points and would need
  ~1953 campaigns per arm to resolve. `thinking` is also never verified — pi's stream echoes
  `provider` and `model` but has no reasoning-effort field — so those rows split on a parameter that
  is both unresolvable and unconfirmed. Collapse them.
- **More judge polish before judges are measurable.** Improving an instrument you cannot score is
  taste, not engineering.
- **A third small-model family.** It will land in the same 7–19 band and teach you nothing new about
  the suite.

---

## Appendix: the noise numbers

Expected for a dry run, recorded so the scaling arguments above have something behind them.

- **Run-to-run.** `gpt-5.4-nano`/medium, identical config, 14 campaigns: `13 14 14 15 15 16 16 16 17
  17 18 18 18 19` — mean 16.1, sd 1.7. A single campaign is ±3 at 2 sd.
- **Internal consistency.** Cronbach's alpha over the 7 task scores: **+0.00** within
  gpt-5.4-nano/medium (n=14), −0.12 across gpt-5.4-nano (n=23), +0.31 within gpt-5-nano (n=11),
  +0.54 pooled (n=34). The pooled figure is manufactured by mixing two model generations — that is
  between-group signal, not task coherence. This is §2/§3 in another form.
- **Item–rest correlation.** t1 +0.56, t3 +0.37, t7 +0.32, t6 +0.31, t4 +0.17, t5 +0.12, t2 +0.08.
- **Dead expectations.** Of 61: t7/E5 met 35/35; t3/E9 35/36; t4/E4 0/34; t6/E7 0/35; t4/E1 1/34;
  t6/E6 1/35; t4/E6 2/34. Eight more sit at p ≥ 0.92.
- **Verdict-pattern collapse.** Distinct scorecard patterns per task: t4 9/34, t2 11/36, t3 11/36,
  t7 11/35, t1 15/35, t6 18/35, t5 25/36. Expectations fail as a block — t2's E1/E2/E3/E6 are unmet
  in exactly the same 3 runs, t7's E1–E4 in exactly the same 4. t5 is the only task whose items move
  independently, and is the shape to copy.
- **Band knife-edge.** Median distance of `adjusted` to the nearest band edge is 0.100; 10% of runs
  are within 0.02. Flipping one expectation met↔unmet changes the headline score in 125/247 runs
  (51%).
- **Judge spread.** Same candidate config, split by judge harness: luna-max n=8 mean 16.62;
  terra-high n=5 mean 15.00; luna-high/pi n=1 mean 18.00. Confounded with date, since the switch
  fell on a date boundary.
- **Gap resolvable at n≈3–4 per arm:** ~4 points. Below ~2 points: not measurable at any campaign
  count worth paying for.
- **Unexercised paths.** 259 runs: 0 classified infrastructure-invalid, 6 assisted (2%), max
  interventions on any run 1 (cap is 3).
- **Version churn.** 14 harness versions in 17 days; published results span 5, plus two legacy
  versions, all in one table the README says is not comparable across versions.

### Bookkeeping defects spotted in passing

- One leaderboard row (`gpt-5-nano-medium-20260827-0550`) disagrees with its own
  `orchestrator.json`; `leaderboard.py --write` wasn't re-run after commit `7fa9500a`. Only such
  mismatch in 40 rows — and it is in the judge column.
- README § "Where things live" promises a published "candidate diff" per run. There are zero diff
  files under `results/` — only a filename list in `summary.json`.
- README still says "Only one model has been run end to end so far." Two models, five triples,
  40 campaigns.
- Directory names and `campaign_id`s disagree for 4 campaigns (UTC-vs-local drift), making id-based
  lookup unreliable.
- One run is `unassigned`: it exhausted its budget before judge-finish, so `classify-run` refused to
  score it. Expected behavior, but it means a timed-out candidate silently leaves a hole in a
  campaign rather than scoring 0.

---

## Recomputing

Nothing here is hand-maintained state, and none of it should be trusted once the corpus grows.
Every figure derives from `results/*/*/result.json`, `results/*/*/scorecard.json` and
`results/*/orchestrator.json`:

- **Correlation matrix (§2), alpha and item–rest (appendix)** — per campaign with all 7 tasks
  present, take the 7 `score` values; Pearson across campaigns; alpha over the 7 as items; item–rest
  is each task against the sum of the other six. Restrict to one `selected_model` + `thinking` +
  `eval_version` — pooling model generations inflates alpha.
- **Ceilings and dead items (§4, appendix)** — tally `scorecard.expectations[].verdict` per
  `(task_id, id)`, crediting met 1.0 / partial 0.5 / unmet 0.0.
- **Band knife-edge (appendix)** — `adjusted` against edges 0.30 / 0.60 / 0.85, perturbed by
  ±1/count and ±0.5/count.
- **Judge spread (appendix)** — group by `orchestrator.orchestrator`, holding candidate config and
  eval version fixed.
- **Economics (§7)** — `n = (2·sd/target)²`; costs from `orchestrator.cost_usd` and
  `campaign.costs.campaign_usd`.

Two artifact layouts exist: current campaigns store `<campaign>/<task>/result.json`; the three
2026-08-10/11 campaigns store `<campaign>/<task>/trial-1/result.json`. Walk with a recursive glob,
as `leaderboard.py` does, or the oldest campaigns silently vanish from the counts.
