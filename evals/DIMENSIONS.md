# Extended leaderboard — the axes the score throws away

The published score condenses each task to one integer 0–3, then sums seven of them.
This sidecar reports the same runs on seven axes instead. **No new campaigns were
run:** every number here is derived from artifacts already in [results/](results/).

Regenerate with `uv run python .agents/skills/nothingness-evals/scripts/dimensions.py --write`.
Do not hand-edit between the markers. `--json` emits the per-run values.

## What the axes mean

Four are rubric-derived. Each expectation in `evals/tasks/rubrics/` is assigned to exactly
one axis by matching its heading and its declared `**Evidence:**` kind — never by a
hardcoded list of ids, so editing a rubric moves its expectations automatically. The
assignment is printed in the last table below so it can be audited rather than trusted.
Each axis is the mean credit over its expectations (met 1.0 / partial 0.5 / unmet 0.0),
as a percentage, equal-weighted across tasks.

| Axis | Question | Assigned when the heading… |
| --- | --- | --- |
| **works** | Does the feature do what was asked? | matches none of the below (the residual — placement, labels, behavior, persistence, transitions) |
| **self-ev** | Did the candidate observe its own change *as it happened*? | is an `events` expectation about capturing the action live |
| **proof** | Does the write-up match what the judge independently saw? | is about a deliverable "actually captured and on-point", an independent corroboration, claims "traceable to an actual observation", or "narrating over" faults |
| **intact** | Did anything adjacent break? | is about behavior "unaffected"/"undisturbed", scope containment, crashes, new errors, or unrequested source changes |

Three are measured directly, not judged:

| Column | Source |
| --- | --- |
| **Candidate $** | `result.json` → `cost_usd.candidate`, summed over the campaign's tasks |
| **Wall min** | `summary.json` → `timing.elapsed_seconds`, summed over tasks |
| **Tools** | `result.json` → `candidate.tool_executions`, mean per task — how many tool calls the candidate made |
| **Help** | `intervention_count`, summed over tasks |

## What this immediately shows

Read the per-task table below against its `Score mean` column:

- **t4 is not a task models fail at — it is a task they do without proving.** `works` is 81%
  while `proof` is 59% and `self-ev` is **3%**. The integer score, 1.64, reads as "can barely
  do it". The vector says "mostly builds it, almost never watches itself build it". Those are
  different findings with different fixes, and the integer cannot distinguish them.
- **`self-ev` is only probed on t4.** Every other task shows `–` because no other rubric asks
  whether the candidate observed its own work. That is a gap in the rubrics, not in the models —
  and given the 3%, it is the most discriminating question in the suite, currently asked once.
- **`proof` separates where the score saturates.** t2 and t3 sit at 91–92% `works`, so the score
  is at its ceiling and cannot rank anything; `proof` still has 18 points of headroom there.
- **`proof` is the weakest axis everywhere** (32–82%) and falls fastest on the hard tasks
  (t6 32%, t5 43%). Evidence quality, not implementation, is what the current candidate pool is
  worst at.
## What this does *not* fix — a measured negative result

Vectorizing the score was expected to sharpen model comparison. Tested against the one
comparison the integer score demonstrably cannot make — `gpt-5.4-nano` medium vs high, which
differ by 0.14 points and would need ~1953 campaigns per arm — **it does not help:**

```
axis        medium      high    diff   pooled sd   campaigns/arm for 80% power
score        16.14     16.00    0.14        1.58                         1953
works        87.19     85.08    2.11        9.30                          310
proof        74.06     74.01    0.06        7.77                       300797
intact       83.42     84.33    0.91       10.81                         2273
```

And the relative noise is unchanged — within `gpt-5.4-nano`/medium (n=14) the coefficient of
variation is 0.107 for the integer score and 0.107 for `works`, 0.094 for `proof`, 0.141 for
`intact`.

The conclusion matters for planning: **the noise lives in the run, not in the quantization.**
Flattening a continuous score into four bands is not what was destroying the signal, so
recovering the continuous value buys diagnosis, not precision. Better model discrimination
needs harder tasks (range) and more campaigns (noise) — the axes will not substitute for either.

What the axes *do* buy is knowing which of those to spend on, and being able to say what a model
is actually bad at rather than only how bad.

- **Cost and wall time separate model families cleanly** and cost nothing to collect: the
  `gpt-5.4-nano` campaigns spend ~10x the candidate dollars and ~2x the tool calls of the
  `gpt-5-nano` ones.

## Caveats

- `Tools` counts every tool call, including file edits — it is a work-volume measure, not a
  "did it drive the app" measure. Isolating app-driving calls needs the per-call event trail in
  each run's `evidence/`, which this script does not open. (`candidate.event_counts.extension_ui_request`
  looks like a driving counter but is not: it correlates with `tool_executions` at only 0.26 and
  ranges to 22,105, so it is pi's UI-streaming traffic, not app drives.)
- Axis percentages are means over unequal numbers of expectations, so a task with two `proof`
  items moves in coarser steps than one with three.
- Rows span eval versions 1.0.0 → 1.7.3 and are not comparable across them, exactly as in the
  main leaderboard. `self-ev` before 1.7.x reflects older rubrics.
- Campaigns with a task missing a `summary.json` (the three legacy 2026-08-10/11 layouts) show
  partial wall-time sums.

See [ASSESSMENT.md](ASSESSMENT.md) § "Intrinsic failure 1" for why this sidecar exists.

<!-- BEGIN GENERATED DIMENSIONS -->
### Per campaign

| Campaign | Model | Eval | Score | works | self-ev | proof | intact | Candidate $ | Wall min | Tools | Help |
| --- | --- | --- | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: |
| [gpt-5-nano-high-20260824-2323](results/gpt-5-nano-high-20260824-2323/README.md) | `gpt-5-nano` high | 1.7.3 | **10** | 53 | 0 | 27 | 63 | 0.150 | 65 | 33 | 0 |
| [gpt-5-nano-high-20260825-0304](results/gpt-5-nano-high-20260825-0304/README.md) | `gpt-5-nano` high | 1.7.3 | **10** | 63 | 0 | 40 | 64 | 0.111 | 66 | 25 | 0 |
| [gpt-5-nano-high-20260825-0536](results/gpt-5-nano-high-20260825-0536/README.md) | `gpt-5-nano` high | 1.7.3 | **14** | 84 | 0 | 39 | 86 | 0.101 | 61 | 25 | 0 |
| [gpt-5-nano-high-20260825-0938](results/gpt-5-nano-high-20260825-0938/README.md) | `gpt-5-nano` high | 1.7.3 | **15** | 82 | 0 | 57 | 89 | 0.132 | 71 | 31 | 0 |
| [gpt-5-nano-high-20260825-1643](results/gpt-5-nano-high-20260825-1643/README.md) | `gpt-5-nano` high | 1.7.3 | **11** | 74 | 0 | 33 | 71 | 0.130 | 68 | 31 | 0 |
| [gpt-5-nano-medium-20260824-0741](results/gpt-5-nano-medium-20260824-0741/README.md) | `gpt-5-nano` medium | 1.7.3 | **8** | 51 | 0 | 43 | 57 | 0.052 | 56 | 16 | 0 |
| [gpt-5-nano-medium-20260824-1023](results/gpt-5-nano-medium-20260824-1023/README.md) | `gpt-5-nano` medium | 1.7.3 | **12** | 75 | 0 | 48 | 65 | 0.071 | 43 | 22 | 0 |
| [gpt-5-nano-medium-20260824-1230](results/gpt-5-nano-medium-20260824-1230/README.md) | `gpt-5-nano` medium | 1.7.3 | **14** | 84 | 0 | 50 | 93 | 0.075 | 43 | 22 | 0 |
| [gpt-5-nano-medium-20260824-1451](results/gpt-5-nano-medium-20260824-1451/README.md) | `gpt-5-nano` medium | 1.7.3 | **14** | 83 | 0 | 50 | 82 | 0.066 | 43 | 25 | 0 |
| [gpt-5-nano-medium-20260824-1800](results/gpt-5-nano-medium-20260824-1800/README.md) | `gpt-5-nano` medium | 1.7.3 | **9** | 48 | 0 | 45 | 64 | 0.072 | 40 | 22 | 0 |
| [gpt-5-nano-medium-20260827-0550](results/gpt-5-nano-medium-20260827-0550/README.md) | `gpt-5-nano` medium | 1.7.3 | **7** | 47 | 0 | 38 | 48 | 0.081 | 62 | 24 | 1 |
| [gpt-5.4-nano-high-20260821-0517](results/gpt-5.4-nano-high-20260821-0517/README.md) | `gpt-5.4-nano` high | 1.7.2 | **14** | 69 | 0 | 67 | 68 | 0.688 | 94 | 66 | 0 |
| [gpt-5.4-nano-high-20260821-0749](results/gpt-5.4-nano-high-20260821-0749/README.md) | `gpt-5.4-nano` high | 1.7.2 | **17** | 91 | 0 | 86 | 93 | 0.651 | 93 | 61 | 1 |
| [gpt-5.4-nano-high-20260821-1216](results/gpt-5.4-nano-high-20260821-1216/README.md) | `gpt-5.4-nano` high | 1.7.2 | **18** | 94 | 0 | 83 | 96 | 0.835 | 106 | 73 | 0 |
| [gpt-5.4-nano-high-20260822-0637](results/gpt-5.4-nano-high-20260822-0637/README.md) | `gpt-5.4-nano` high | 1.7.3 | **15** | 81 | 0 | 71 | 82 | 1.133 | 127 | 90 | 0 |
| [gpt-5.4-nano-high-20260822-0958](results/gpt-5.4-nano-high-20260822-0958/README.md) | `gpt-5.4-nano` high | 1.7.3 | **15** | 81 | 0 | 75 | 77 | 1.064 | 123 | 77 | 0 |
| [gpt-5.4-nano-high-20260822-1306](results/gpt-5.4-nano-high-20260822-1306/README.md) | `gpt-5.4-nano` high | 1.7.3 | **17** | 94 | 0 | 62 | 89 | 0.933 | 118 | 81 | 0 |
| [gpt-5.4-nano-low-20260823-2200](results/gpt-5.4-nano-low-20260823-2200/README.md) | `gpt-5.4-nano` low | 1.7.3 | **16** | 89 | 0 | 71 | 82 | 0.202 | 37 | 39 | 0 |
| [gpt-5.4-nano-low-20260824-0118](results/gpt-5.4-nano-low-20260824-0118/README.md) | `gpt-5.4-nano` low | 1.7.3 | **13** | 76 | 0 | 64 | 79 | 0.242 | 58 | 43 | 0 |
| [gpt-5.4-nano-low-20260824-0323](results/gpt-5.4-nano-low-20260824-0323/README.md) | `gpt-5.4-nano` low | 1.7.3 | **13** | 80 | 0 | 56 | 82 | 0.217 | 85 | 40 | 0 |
| [gpt-5.4-nano-medium-20260810-0750](results/gpt-5.4-nano-medium-20260810-0750/README.md) | `gpt-5.4-nano` medium | 1.0.0 | **11** | 70 | – | 61 | 88 | 0.880 | 86 | 77 | 0 |
| [gpt-5.4-nano-medium-20260810-2027](results/gpt-5.4-nano-medium-20260810-2027/README.md) | `gpt-5.4-nano` medium | 1.3.0 | **14** | 77 | 50 | 74 | 75 | 0.452 | 81 | 57 | 0 |
| [gpt-5.4-nano-medium-20260811-0506](results/gpt-5.4-nano-medium-20260811-0506/README.md) | `gpt-5.4-nano` medium | 1.3.0 | **15** | 88 | 0 | 65 | 89 | 0.615 | 111 | 67 | 0 |
| [gpt-5.4-nano-medium-20260814-1944](results/gpt-5.4-nano-medium-20260814-1944/README.md) | `gpt-5.4-nano` medium | 1.5.1 | **16** | 83 | 50 | 83 | 73 | 0.582 | 91 | 59 | 0 |
| [gpt-5.4-nano-medium-20260815-0548](results/gpt-5.4-nano-medium-20260815-0548/README.md) | `gpt-5.4-nano` medium | 1.6.1 | **13** | 75 | 0 | 46 | 80 | 0.605 | 108 | 66 | 0 |
| [gpt-5.4-nano-medium-20260819-1441](results/gpt-5.4-nano-medium-20260819-1441/README.md) | `gpt-5.4-nano` medium | 1.7.0 | **16** | 91 | 0 | 74 | 95 | 0.756 | 88 | 68 | 0 |
| [gpt-5.4-nano-medium-20260819-2000](results/gpt-5.4-nano-medium-20260819-2000/README.md) | `gpt-5.4-nano` medium | 1.7.2 | **13** | 63 | 0 | 81 | 65 | 0.917 | 96 | 79 | 0 |
| [gpt-5.4-nano-medium-20260820-0444](results/gpt-5.4-nano-medium-20260820-0444/README.md) | `gpt-5.4-nano` medium | 1.7.2 | **16** | 94 | 0 | 75 | 77 | 0.721 | 104 | 71 | 0 |
| [gpt-5.4-nano-medium-20260820-0810](results/gpt-5.4-nano-medium-20260820-0810/README.md) | `gpt-5.4-nano` medium | 1.7.2 | **17** | 95 | 0 | 71 | 95 | 0.731 | 94 | 73 | 0 |
| [gpt-5.4-nano-medium-20260820-1113](results/gpt-5.4-nano-medium-20260820-1113/README.md) | `gpt-5.4-nano` medium | 1.7.2 | **19** | 97 | 0 | 86 | 94 | 0.754 | 106 | 74 | 0 |
| [gpt-5.4-nano-medium-20260822-2050](results/gpt-5.4-nano-medium-20260822-2050/README.md) | `gpt-5.4-nano` medium | 1.7.3 | **18** | 93 | 0 | 76 | 96 | 0.637 | 88 | 73 | 0 |
| [gpt-5.4-nano-medium-20260822-2327](results/gpt-5.4-nano-medium-20260822-2327/README.md) | `gpt-5.4-nano` medium | 1.7.3 | **18** | 92 | 0 | 76 | 93 | 0.629 | 102 | 66 | 0 |
| [gpt-5.4-nano-medium-20260823-0614](results/gpt-5.4-nano-medium-20260823-0614/README.md) | `gpt-5.4-nano` medium | 1.7.3 | **17** | 94 | 0 | 73 | 86 | 0.484 | 69 | 53 | 0 |
| [gpt-5.4-nano-medium-20260823-0925](results/gpt-5.4-nano-medium-20260823-0925/README.md) | `gpt-5.4-nano` medium | 1.7.3 | **18** | 97 | 0 | 86 | 96 | 0.548 | 73 | 65 | 0 |
| [gpt-5.4-nano-medium-20260823-1221](results/gpt-5.4-nano-medium-20260823-1221/README.md) | `gpt-5.4-nano` medium | 1.7.3 | **15** | 88 | 0 | 62 | 86 | 0.879 | 95 | 83 | 0 |
| [gpt-5.4-nano-medium-20260826-0623](results/gpt-5.4-nano-medium-20260826-0623/README.md) | `gpt-5.4-nano` medium | 1.7.3 | **14** | 83 | 0 | 74 | 65 | 0.604 | 126 | 61 | 2 |
| [gpt-5.4-nano-medium-20260826-1933](results/gpt-5.4-nano-medium-20260826-1933/README.md) | `gpt-5.4-nano` medium | 1.7.3 | **15** | 79 | 0 | 68 | 63 | 0.653 | 89 | 61 | 1 |
| [gpt-5.4-nano-medium-20260826-2153](results/gpt-5.4-nano-medium-20260826-2153/README.md) | `gpt-5.4-nano` medium | 1.7.3 | **14** | 80 | 0 | 62 | 85 | 1.073 | 110 | 92 | 0 |
| [gpt-5.4-nano-medium-20260827-0033](results/gpt-5.4-nano-medium-20260827-0033/README.md) | `gpt-5.4-nano` medium | 1.7.3 | **16** | 83 | 0 | 71 | 74 | 0.679 | 90 | 68 | 1 |
| [gpt-5.4-nano-medium-20260827-0246](results/gpt-5.4-nano-medium-20260827-0246/README.md) | `gpt-5.4-nano` medium | 1.7.3 | **16** | 83 | 0 | 76 | 92 | 0.716 | 98 | 75 | 0 |

### Per task, pooled over every campaign

| Task | n | Score mean | works | self-ev | proof | intact | Candidate $ | Wall min | Tools |
| --- | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: |
| t1-playback-smoke-linux | 40 | 2.17 | 76 | – | 78 | 82 | 0.027 | 8 | 35 |
| t2-settings-placement-linux | 40 | 2.50 | 91 | – | 82 | 90 | 0.045 | 10 | 43 |
| t3-settings-placement-color-scheme-linux | 40 | 2.58 | 92 | – | 82 | 90 | 0.045 | 9 | 45 |
| t4-swipe-to-seek-linux | 40 | 1.64 | 81 | 3 | 59 | 79 | 0.121 | 16 | 78 |
| t5-jump-to-now-playing-linux | 40 | 1.73 | 69 | – | 43 | 79 | 0.133 | 17 | 82 |
| t6-dot-song-info-hardening-linux | 40 | 1.40 | 64 | – | 32 | 65 | 0.109 | 15 | 72 |
| t7-opus-shuffled-playlist-linux | 40 | 2.35 | 89 | – | 70 | 75 | 0.043 | 9 | 36 |

### How each expectation was assigned

| Task | works | self-ev | proof | intact |
| --- | --- | --- | --- | --- |
| t1-playback-smoke-linux | E1, E2, E3, E4 | – | E5, E7 | E6 |
| t2-settings-placement-linux | E1, E2, E3 | – | E5, E6 | E4, E7, E8 |
| t3-settings-placement-color-scheme-linux | E1, E2, E3, E4 | – | E6, E7 | E5, E8, E9 |
| t4-swipe-to-seek-linux | E2, E3, E5 | E1, E4 | E6, E7, E8 | E9, E10 |
| t5-jump-to-now-playing-linux | E1, E2, E3, E4, E5 | – | E6, E7, E8 | E9, E10 |
| t6-dot-song-info-hardening-linux | E1, E2, E3, E4, E5 | – | E6, E7, E8 | E9, E10 |
| t7-opus-shuffled-playlist-linux | E1, E2, E3, E4, E5 | – | E6, E8 | E7 |
<!-- END GENERATED DIMENSIONS -->
