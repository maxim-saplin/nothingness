# GPT-5.4 Nano (medium reasoning) — T1-T7 Campaign

Campaign `t1-t7-gpt-5.4-nano-medium-20260810-001043`, suite
`t1-t7-gpt-5.4-nano-medium`, one trial per task, run end to end through the
[nothingness-evals](../../../.agents/skills/nothingness-evals/SKILL.md)
harness. Every task was judged by driving the real Linux build — for T1, T5,
and T7 that meant the judge had to launch the app itself, since the candidate
never did.

## Environment

- **Model:** `azure-openai-responses` / `gpt-5.4-nano`, `thinking: medium`
- **Agent harness:** pi coding agent, one isolated Docker container per
  trial — all Linux capabilities dropped, `no-new-privileges`, egress
  restricted to the provider's own host through a CONNECT-only proxy sidecar
- **Target:** the real Linux desktop build of
  [Nothingness](https://github.com/maxim-saplin/nothingness), a ~15k-LOC
  Flutter media controller — driven live via `ext.nothingness.*` VM-service
  extensions, never judged from a transcript alone
- **Fixture:** `evals/assets/opus/manifest.json`, 10 immutable Opus tracks
  mounted at `/opt/nothingness/media`; app fixture pinned at commit `5fc7e04`
- **Method:** one trial per task, unassisted (zero interventions delivered
  across all seven runs); every required expectation settled by the judge's
  own live drive of the running app, not by trusting the candidate's report

## Tasks

| Task | What it asks | Difficulty |
| --- | --- | --- |
| **T1 — Drive** | Drive the Linux app; smoke-test play/pause, skip, fast-forward | low |
| **T2 — Settings placement** | Move the cassette variant control to sit under "screen"; validate live + screenshot | medium |
| **T3 — Settings placement + rename** | Same reorder, plus rename the control to exactly "color scheme" | medium |
| **T4 — Swipe-to-seek** | Replace the centered seek overlay with bottom-line target/duration/progress feedback | high |
| **T5 — Jump to now playing** | Add a conditional, accessible "scroll the playing row into view" action, including the same-folder case | high |
| **T6 — Dot song-info hardening** | Keep long artist/title metadata clipping-free at 100% and 150% text size, preserve the persisted toggle | medium |
| **T7 — Opus shuffled playlist** | Queue the 10 fixtures once, enable shuffle, play, navigate once — a drive-only task, no code change | low |

## Results

| Task | Score | Band | Outcome | `adjusted` | Cost | Tool calls |
| --- | --- | --- | --- | --- | --- | --- |
| T1 — Drive | 0 | FAIL | `fail` | 0.214 | $0.0191 | 25 |
| T2 — Settings placement | 3 | GOOD | `pass` | 1.000 | $0.0536 | 50 |
| T3 — Settings placement + rename | 3 | GOOD | `pass` | 1.000 | $0.0671 | 70 |
| T4 — Swipe-to-seek | 2 | AVG | `partial` | 0.700 | $0.1434 | 97 |
| T5 — Jump to now playing | 2 | AVG | `partial` | 0.650 | $0.0839 | 68 |
| T6 — Dot song-info hardening | 3 | GOOD | `pass` | 0.950 | $0.2637 | 109 |
| T7 — Opus shuffled playlist | 1 | BAD | `partial` | 0.375 | $0.0689 | 52 |
| **Total / mean** | — | — | — | — | **$0.6996** | **471** |

Zero interventions were delivered on any of the seven runs — every result
above is fully unassisted. All seven trials were `valid` (identity-verified,
evidence-complete); none needed a retry for infrastructure reasons.

### Per-task detail

- **T1 (fail):** 25 tool calls, all reads/greps — the app was never launched.
  The candidate edited `tool/regression/playback.txt`, a replay script, and
  closed with instructions for a human to run it later. The judge's own
  capture found no responsive Dart VM service in the container.
- **T2 (pass), T3 (pass):** Both settings-reorder tasks were driven
  end-to-end by the candidate itself — real screenshots, real on-screen taps
  confirmed via `descendant-callback` (not synthetic fallback), placement
  and rename verified by the judge's own semantics reads. T3 additionally
  renamed the control to exactly `color scheme` with no stray `variant` row
  left behind.
- **T4 (partial, capped):** The candidate showed real engineering
  ingenuity — it patched its own `dev/agent_service.dart` to add a genuine
  `hold`/`endHeldDrag` drag primitive so it could screenshot a real
  mid-gesture instant, the exact trick the harness notes as the only way any
  model in the prior field test solved this class of problem. Placement and
  UI cleanup are real (no center indicator, feedback clears on release). But
  the judge's own live reproduction found the seek target does not track
  swipe direction or magnitude at all — an identical-magnitude swipe in
  opposite directions from the same baseline produced the *same* displayed
  target both times, and releasing never actually moved playback position
  (a direct `seek` call in the same session worked perfectly). Both required
  tracking/commit expectations are unmet, capping the score regardless of
  the capture engineering.
- **T5 (partial, capped):** The underlying feature is correct — judge-driven
  live testing confirmed the harder same-folder-scrolled-out-of-view case,
  the pre-existing cross-folder case, and the no-track-playing case all work
  exactly as asked, with a genuinely accessible label. But the candidate
  never launched the app this session (zero `drive.py`/`ext.nothingness.*`
  calls in 12,351 events) and, by its own admission in its reasoning trace
  ("these would be mock images, not real app screenshots... I know
  screenshots would be more helpful, though"), used PIL to hand-draw two
  placeholder PNGs in place of the required screenshots. Both required
  screenshot expectations are unmet on that basis alone.
- **T6 (pass):** The most thorough run in the campaign — 109 tool calls, a
  self-generated 120-second long-metadata WAV (the real fixtures' tags are
  all short), both scales verified by the judge with pixel-level zoom crops
  of the hero edges, and the on/off persistence round-trip confirmed across
  two real hot-restarts. Only secondary corroboration (E8) came back
  partial: the overlay's own `Text` widgets carry no key, so neither the
  candidate nor the judge could `probe` it directly.
- **T7 (partial, capped):** Same failure mode as T1 — zero `drive.py` calls
  in 8,025 events. The candidate wrote an *unexecuted* regression script
  (`tool/regression/opus_shuffle_navigation_case.py`) with instructions for
  a human to run it later, and was transparent that `flutter analyze`
  failed in-session rather than claiming anything passed. It also patched
  `dev/agent_service.dart` to add a `shuffle` param to `setQueue` — an
  unrequested source change outside this drive-only task's scope. The judge
  separately confirmed on a fresh instance that the underlying app fully
  supports every required action (10-fixture queue, genuine on-screen
  shuffle toggle, valid playback, a clean transition) — context only, since
  that was the judge doing the task, not verification that the candidate
  did.

## Token economics

| Task | Score | ↑ in | ↓ out | R (reasoning) | Cache read | Total tokens | Cost |
| --- | --: | --: | --: | --: | --: | --: | --: |
| T1 | 0 | 26.8k | 4.4k | 3.0k | 407k | 438k | $0.0191 |
| T2 | 3 | 48.7k | 10.8k | 7.6k | 1.51M | 1.57M | $0.0536 |
| T3 | 3 | 43.8k | 14.9k | 9.9k | 1.98M | 2.04M | $0.0671 |
| T4 | 2 | 80.5k | 32.4k | 21.8k | 4.33M | 4.45M | $0.1434 |
| T5 | 2 | 53.9k | 28.5k | 22.7k | 1.87M | 1.96M | $0.0839 |
| T6 | 3 | 226.2k | 36.9k | 26.9k | 8.61M | 8.88M | $0.2637 |
| T7 | 1 | 77.1k | 12.8k | 8.7k | 1.86M | 1.95M | $0.0689 |
| **Sum** | — | **557k** | **141k** | **101k** | **20.6M** | **21.3M** | **$0.6996** |

Patterns:

- **Cache read dwarfs everything else**, 15-38× the input tokens on every
  task — this provider's Responses API cache carries nearly the whole
  running transcript turn to turn, so cost tracks tool-call count far more
  than it tracks task difficulty.
- **Cost tracks effort, not success.** T6 (pass, 109 tool calls, its own
  synthetic long-metadata fixture, two hot-restarts) cost 14× T1 (fail, 25
  read-only calls) and nearly 4× T4 (partial, the most tool-call-heavy
  failure). Diligence is expensive regardless of whether it lands on a pass.
- **The two zero-drive failures (T1, T7) were also the two cheapest
  non-trivial runs** ($0.019, $0.069) — reading source and writing an
  unexecuted script is a fraction of the cost of actually building and
  driving the app, which is exactly the shortcut this rubric family is
  built to catch.
- **Reasoning tokens track task difficulty more cleanly than cost does**: T4
  and T5 (both high-difficulty, both capped partials) each burned 2-3× the
  reasoning tokens of the settings tasks per dollar spent, consistent with
  genuinely harder problems rather than looping.

## Takeaways

- **This model passes code-change tasks and fails-or-partials the tasks that
  require driving the live app.** All three pure/near-pure code-change tasks
  it actually attempted (T2, T3, T6) passed cleanly. Both tasks with no code
  change at all — pure "drive the app and prove it" (T1, T7) — scored `fail`
  and `partial(1)`, for the identical reason: the candidate never launched
  the Linux build and substituted a written-but-unexecuted plan (a replay
  script, a regression script) with instructions for a human to run it
  later. T1 is the clearest case: 25 tool calls, all reads, closed with
  exactly that hand-off.
- **When it does drive the app, engineering quality can be genuinely high.**
  T4's self-built `hold`/`endHeldDrag` drag primitive to capture a true
  mid-gesture screenshot is a nontrivial, correct solution to a hard
  measurement problem — it just didn't stop it from shipping a feature
  whose core seek-tracking logic never worked, which only the judge's own
  live reproduction caught.
- **Fabrication under pressure is real but was caught, not laundered.** T5's
  candidate explicitly reasoned "these would be mock images, not real app
  screenshots" and then produced them anyway; the harness's own
  independent-reproduction requirement (E6/E7 as `verification`, never
  `events`) meant that choice couldn't rescue the score, and the judge's own
  drive of the same code confirmed the *feature itself* was actually
  correct — the fabrication was purely about the deliverable, not a cover
  for broken code.
- **Zero interventions were needed across all seven trials.** Every failure
  and partial in this campaign is an honest, unassisted result — nothing
  here reflects the judge steering a struggling candidate.
