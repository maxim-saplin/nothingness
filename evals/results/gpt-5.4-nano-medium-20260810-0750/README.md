# gpt-5.4-nano · medium reasoning · 2026-08-10

**11/18** across 6 scored tasks · **$0.8818** · 742.1k in / 166.9k out · unassisted · judge: judge-t1, judge-t2, judge-t3, judge-t4, judge-t5, judge-t6, judge-t7

<!-- judge: one paragraph — what was run and the single most important thing it showed. -->

| Task | Score | Outcome | In | Out | Reasoning | Cache | Cost | $/point |
| --- | --- | --- | --- | --- | --- | --- | --- | --- |
| `t1-playback-smoke-linux` | 0 | fail | 74.8k | 8.0k | 6.1k | 1010.7k | $0.0455 | – |
| `t2-settings-placement-linux` | 3 | pass | 69.6k | 10.2k | 7.1k | 965.1k | $0.0463 | $0.0154 |
| `t3-settings-placement-color-scheme-linux` | 3 | pass | 42.6k | 12.7k | 8.4k | 1503.0k | $0.0545 | $0.0182 |
| `t4-swipe-to-seek-linux` | – | unassigned | 301.1k | 62.0k | 45.8k | 13113.9k | $0.4002 | – |
| `t5-jump-to-now-playing-linux` | 1 | partial | 102.2k | 24.4k | 17.9k | 2545.7k | $0.1022 | $0.1022 |
| `t6-dot-song-info-hardening-linux` | 3 | pass | 75.1k | 27.4k | 19.6k | 4677.9k | $0.1431 | $0.0477 |
| `t7-opus-shuffled-playlist-linux` | 1 | partial | 76.7k | 22.2k | 15.6k | 2328.8k | $0.0900 | $0.0900 |
| **Total** | **11/18** | | 742.1k | 166.9k | 120.5k | 26145.0k | **$0.8818** | **$0.0802** |

## What happened

**t1-playback-smoke-linux** (0) — # T1 · Playback smoke (Linux) — judge notes

**Run:** `t1-t7-gpt-5.4-nano-medium-t1-playback-smoke-linux-trial-01-attempt-01`
**Model:** azure-openai-responses / gpt-5.4-nano / thinking=medium (identity verified)
**Outcome:** fail · score 0 · raw 0.285714 · validity valid · 0 interventions · 36 tool calls · 228s · $0.045

## What the candidate actually did

It never ran the app. In ~4 minutes it read 38 files and issued 14 bash commands — all read-only
exploration (`ls`, `grep`, `find`, `sed`) — looking for how driving works. It found
`.agents/skills/agent-emulator-debugging/scripts/drive.py`, read it, read `tool/regression/playback.txt`
and the regression playbook, then grepped `.tmp` for the example test tones that script mentions
(`t1_a440_2s.wav` etc.) and found nothing there. Rather than launching the Linux build and using the
10 opus fixtures actually mounted at `/opt/nothingness/media`, it wrote a new replay script,
`tool/regression/playback_smoke_linux.txt`, containing `setQueue` / `pause` / `resume` / `next` /
`prev` / `seek 00:00:01` lines pointing at those non-existent `.tmp` WAV paths — and handed it back
with "⚠️ Edit the WAV paths ... to match where your checkout stages tones". It never executed the
script, never called `drive.py`, never ran `flutter`.

## What I verified myself

- **Tool trail.** `judge-query.py --group-by tool` → bash 57 events / read 38 / write 4 / edit 2.
  Filtering `tool_execution_start` for `drive.py|flutter` returns 5 hits: two `find` commands looking
  for drive.py, one `read` of drive.py, and the two `write`s of the new script. Zero executions.
- **Container state after the run.** The post-run inspection found no live app:
  `runtime_discovery.method = "unavailable"` — "no live app found in container: default discovery
  (/tmp/flutter_run.log and its cache) found no responsive Dart VM service, and scanning
  /tmp/flutter_run*.log for another live session also found none". The process snapshot holds only
  `python3`, `Xvfb`, `openbox`, `x11vnc`, `websockify`, `pulseaudio`, `adb` — no Flutter/Dart process
  ever existed. The verification capture's runtime, tree, semantics and settings lenses are all
  unavailable for the same reason; only a screenshot of the empty desktop came back.
- **Workspace.** `candidate.diff` is 0 bytes — no tracked file was touched. `git status` shows exactly
  one untracked file, `tool/regression/playback_smoke_linux.txt`. I read it in full. Notably the usual
  `macos/Flutter/GeneratedPluginRegistrant.swift` regeneration that E6 forgives is *absent* here,
  which is itself corroboration that the Linux app was never built or run.

## Per-expectation

- **E1 (required) — unmet.** No extension call of any kind was issued and no drivable session ever
  existed. This is the rubric's explicit falsifier: the only "testing" was static code reading.
- **E2 (required) — unmet.** No `play`/`pause`/`resume` and no `inspect`. There is no playing-state
  transition anywhere in the session to corroborate or refute.
- **E3 (required) — unmet.** No queue was loaded and no `next`/`prev` was issued; no track index or
  path was ever read.
- **E4 (required) — unmet.** No `seek` and no position read. The only fast-forward in the run is a
  `seek 00:00:01` line of text inside a file that was never executed.
- **E5 (secondary) — met.** Worth being precise about why: the final report contains *no* behavioral
  claim about the app. It says it added a script and warns the paths need fixing. Unlike the field-test
  failure this rubric is calibrated against, this model did not invent a transition it hadn't observed —
  it under-delivered honestly rather than narrating a fake pass. Vacuous, but the property E5 measures
  genuinely holds.
- **E6 (secondary) — met.** Tracked diff empty; the sole workspace change is one new untracked,
  unwired replay script. Nothing about app runtime behavior or settings differs from an unmodified
  build, and no out-of-scope "fix" was attempted.
- **E7 (secondary) — unmet.** No crash or hang occurred because nothing was ever launched, so there
  is no runtime trail to check. But the candidate did hit a real obstacle — the tones it went looking
  for weren't on disk — and its response was to ship a script with placeholder paths and delegate the
  fix to the reader, rather than recover by launching the app against the mounted fixtures. That is
  the "narrated over it" side of this expectation, not the "recovered" side.

## Judging notes

No intervention was needed or given: the candidate was failing, not stuck. It reached a clean
`agent_end`/`agent_settled` well inside its 1800s budget with `stop_reason: stop` and no error — it
believed it was done. I did not attempt to launch the Linux build myself; E1's first conjunct (the
session showing concrete extension calls) already fails outright, so no live re-check could move any
verdict.

Four unmet required expectations cap the run regardless of the aggregate, and the 0.286 raw score
bands to 0 on its own.

**t2-settings-placement-linux** (3) — # T2 · Cassette settings placement (Linux) — judge notes

**Run:** `t1-t7-gpt-5.4-nano-medium-t2-settings-placement-linux-trial-01-attempt-01`
**Model:** azure-openai-responses / gpt-5.4-nano (thinking: medium), identity verified
**Outcome:** valid · pass · score 3 · adjusted 1.0 · 0 interventions
**Candidate cost/time:** $0.046, 397s, 44 tool calls

## What the model did

It changed one file, `lib/widgets/void_settings_sheet.dart`, with a 13-line edit. When the
platform is Linux and the active screen config is a `CassetteScreenConfig`, the list of cassette
controls that the sheet already builds (`displayRows(cfg)` — the variant cycle, the cassette text
size slider and the haptics toggle) is spliced in directly after the `screen` row in the LOOK
group, and skipped where it would otherwise have been emitted lower down in the DISPLAY group. It
reused the existing row specs verbatim rather than re-creating them, so the handlers travelled with
the rows. It also guarded the DISPLAY group header so it isn't left empty. It launched the Linux
build itself, drove it, and captured both a full-sheet screenshot and a cropped one of the relevant
band before finishing.

## What I verified myself

I drove the live container directly (`drive.py` over `docker exec`, `DRIVE_RUN_LOG` pointed at the
candidate's own run log) rather than reading its write-up.

**E1 — placement (met).** With Cassette active, `getSemantics` puts `"screen / cassette"` at
`indexInParent` 5 with rect y 231–276, and `"variant / Tape · Mono"` at `indexInParent` 6 with rect
y 276–321. Consecutive indices, exactly abutting y-ranges, no header or gap between them. The
rendered screenshot shows the same two lines back to back.

**E2 — the screen row still works (met).** I tapped `void-settings-screen` five times in place: it
walked cassette → spectrum → polo → dot → void → cassette, i.e. the full cycle back to the start,
with the row's own displayed value tracking each step. Separately I called `drive.py screen` for
spectrum, dot, void and polo; each landed and was reflected both in `getSettings` and in the row's
displayed value. On returning to Cassette the E1 adjacency still held, so nothing goes stale on a
second visit.

**E3 — the variant control still works (met).** Tapping `void-settings-cassette-variant` seven times
cycled Tape · Mono → Tape · Amber → Tape · Colour → Minimal and wrapped correctly (there are four
variants). Going the other way, `drive.py cassettevariant 2 / 4 / 1 / 3` each changed the variant
and the row's displayed label followed every time. Both directions are connected; the control was
moved, not disconnected.

**E4 — scoped to Cassette (met).** For spectrum, polo, dot and void the row immediately after
`screen` is `immersive` — the normal next row — with no cassette control injected anywhere. Each of
those screens still shows its own DISPLAY rows. I activated a representative control on-screen for
two of them: spectrum's `text color` cycled Cyan → Purple → Mono and `media controls color` went
Cyan → Purple; dot's `show song info` toggled on and off. Polo and void each have only a text-size
*slider* as their own control, and this Linux desktop harness cannot activate a slider at all —
`dragByKey` aborts inside Flutter's `MouseTracker` on synthetic pointers. That limitation is
pre-existing and applies identically to the unmodified build, so I did not hold it against the
change; the rows themselves are present with correct values.

**E5 — the screenshot (met).** I opened both PNGs the candidate produced. `settings_cassette_region.png`
is a 1278×270 crop showing operating mode / LOOK / theme / variant / **screen · cassette** /
**variant · Tape · Mono** — the adjacency is legible without taking anyone's word for what is
off-frame. `settings_cassette_linux.png` shows the whole sheet with the same ordering. I then took
my own screenshot after driving; it shows the same layout with the variant reading "Tape · Colour",
matching the variant I had just set through the direct call. No gap between claim and image here —
this is precisely the failure mode E5 guards against, and the candidate did not fall into it.

**E6 — corroboration (met).** `getSemantics` (indices + rects) and `getSettings` agree with the
screenshots on both ordering and the active variant.

**E7 — nothing else disturbed (met).** I compared the live row order against the pre-change order
(MODE, operating mode, LOOK, theme, theme-variant, screen, immersive, transport, browser, full
screen, ui scale, LIBRARY…, EXTERNAL/SOUND…, DISPLAY, debug layout, ABOUT…) across all five screens.
Every pair of unrelated rows keeps its prior relative order, and nothing unrelated was added,
removed or renamed. Tapping `immersive`, `transport`, `browser` and `debug layout` each changed the
displayed value on-screen. Worth naming one nuance: alongside the variant row, the cassette text
size and haptics rows also moved up out of DISPLAY. I read those as part of what the prompt asked to
move ("its cassette variant controls", plural — the cassette's controls), and moving the group as a
unit is the more coherent result than splitting it, so I did not treat it as an unrelated reshuffle.

**E8 — stability (met).** After repeatedly opening the sheet, cycling all five screens twice,
switching operating mode both ways and toggling a dozen rows, `overflows` reported zero entries and
`inspect` answered normally with the app still live on Cassette.

## Notes for the report

- Zero interventions; the candidate never got stuck and never needed a nudge to produce its
  screenshot.
- The fix is gated on `Platform.isLinux`, which matches the prompt's "On Linux" wording; behavior on
  other platforms is untouched.
- Two harness limitations shaped how I checked things, neither attributable to the candidate: the
  settings ListView only builds ~20 children so rows near the bottom are unreachable by key (I
  switched operating mode to background to shorten the sheet and reach spectrum's DISPLAY rows), and
  synthetic pointer drags abort on Linux desktop, so sliders cannot be exercised on-screen at all.

**t3-settings-placement-color-scheme-linux** (3) — # T3 — Cassette settings placement + color-scheme rename (Linux)

**Run:** `t1-t7-gpt-5.4-nano-medium-t3-settings-placement-color-scheme-linux-trial-01-attempt-01`
**Model:** azure-openai-responses / gpt-5.4-nano, thinking=medium · 55 tool calls · 493 s · $0.054 · 0 interventions

## What the model did

It spent roughly the first half of its run getting a Linux build up (repeated `drive.py preflight`
until `live VM=yes`, one dead end where it looked for the VM service URI in the wrong log path),
then made a single-file change to `lib/widgets/void_settings_sheet.dart` (+30/−12) and verified it
with a screenshot.

The change has two halves. In the main row list it inserts, right after the `screen` row, a
`_Cycle` labelled `color scheme` that cycles `CassetteVariant`, guarded by
`Platform.isLinux && cfg is CassetteScreenConfig`. In the per-screen `displayRows` builder it
threads a new `showCassetteVariant` flag, passed as `!Platform.isLinux`, so the original cassette
variant row is suppressed on Linux and no duplicate is built. Both copies use the same
`ValueKey('void-settings-cassette-variant')`, which is safe only because exactly one of them is
ever constructed. The `displayRows` copy was also renamed to `color scheme`, so non-Linux platforms
get the rename without the move.

Worth noting as a design choice rather than a defect: the prompt's "On Linux" reads most naturally
as stating which platform the work is being done on, and the model instead encoded it as a literal
`Platform.isLinux` runtime condition, duplicating the cycle-construction code to do so. No
expectation in this bundle covers other platforms, and the rubric explicitly admits
correct-but-differently-implemented fixes, so this costs nothing here — but it is the kind of
literal-minded scoping that would read oddly in review.

## What I verified myself

Everything below I drove against the candidate's live container myself via `drive.py`, reading the
sheet with `getSemantics` (the widget tree overflows the 128k cap with the sheet open).

**E1 — placement.** With `screen=cassette`, the semantics dump shows `screen | cassette` at
`indexInParent` 5, rect y 231–276, immediately followed by `color scheme | Tape · Mono` at
`indexInParent` 6, rect y 276–321. Consecutive index, abutting y-ranges, nothing between them.

**E2 — exact label.** The semantics node carries label and value on separate lines, and the label
line reads exactly `color scheme` — lowercase, matching `theme` / `variant` / `screen`. There is
exactly one such row on the whole sheet. The `variant` row still present at index 4 is the
pre-existing *theme* variant (value `system`, key `void-settings-variant`), not a leftover cassette
row; I confirmed against the source that it comes from the untouched `ThemeVariant` cycle.

**E3 — screen control preserved.** Six on-screen taps of `void-settings-screen` walked the whole
cycle: spectrum → polo → dot → void → cassette → spectrum. After each tap the row's own displayed
value and `ext.nothingness.getSettings.screenType` agreed. On the return visit to cassette the E1
adjacency reappeared intact, which is the "second visit" case E3's falsifier calls out.

**E4 — renamed control preserved.** Four on-screen taps of the `color scheme` row advanced it
Tape · Mono → Tape · Amber → Tape · Colour → Minimal → Tape · Mono, a full wrap. Independently,
`drive.py cassettevariant 2`, `3` and `1` each landed and the row's displayed value tracked every
one. So the control moved and was renamed without losing its wiring, exercised in both directions.

**E5 — scoped to cassette.** For spectrum, polo, dot and void the row immediately after `screen` is
`immersive` in every case, and a scan of the full sheet found zero `color scheme` rows on any of
them. I then exercised those screens' own controls: spectrum's `text color` (Cyan → Purple → Mono)
and `media controls color` (Cyan → Purple), and dot's `show song info` (off → on → off), all
changed on on-screen tap. Polo and void have exactly one screen-specific control each — a text-size
slider — and I could not activate it: `ext.nothingness.dragByKey` aborts with a `MouseTracker`
assertion (`(event is PointerAddedEvent) == (lastEvent is PointerRemovedEvent)`), the known Linux
desktop limit on synthetic pointer drags. That limit applies to the unmodified build too and the
candidate's diff provably never touches those branches, so I treated it as a gap in my checking
rather than a defect — but I did not prove those two sliders still drag.

**E6 — screenshot.** The candidate captured `/workspace/.tmp/agent_shots/cassette_settings.png`
this session: the full settings sheet, `screen  cassette`, and `color scheme  Tape · Mono` legibly
on the very next line. That image satisfies E6 on its own terms. It is worth flagging that the
model's final answer instead linked a cropped derivative it made afterwards,
`cassette_settings_region.png`, which cuts off at y=270 and slices the `color scheme` row in half —
the label is only half-rendered and the value nearly illegible. Read alone, that crop would not
prove the adjacency it was offered to prove. The compliant full-frame shot is sitting right next to
it in the same deliverables directory, and my own independent capture reproduces it exactly, so I
scored this met rather than partial: the model did produce a screenshot that shows what it claims,
it just presented the worse of its two.

**E7 — corroboration.** `getSemantics` and `getSettings` were captured in the same verification
observation as the screenshot and agree with it on row order, exact label text and current value.

**E8 — nothing else disturbed.** I diffed full-sheet semantics dumps for cassette against a
non-cassette screen, in both `own` and `background` operating mode. The only structural difference
is the inserted `color scheme` row; every unrelated row (immersive, transport, browser, full
screen, ui scale, LIBRARY, prefer filename over tags, smart folders, DISPLAY, debug layout …)
keeps its relative order, and nothing was added, removed or renamed. I then tapped `immersive`
(off → on), `transport` (bottom → top), `browser` (fixed → swipe up), theme `variant`
(system → dark), `smart folders` (on → off) and cassette `haptics` (on → off) — all responded. The
`theme` row does not change on tap, but that is pre-existing: `ThemeId` is a single-value enum
(`void_`), so its cycle is a no-op in any build.

**E9 — stability.** `getOverflowReports` returned count 0 both before and after roughly thirty
sheet opens, screen switches, variant cycles and row taps, and `drive.py inspect` answered normally
at the end with the app still live. The one exception thrown during my session was the
`MouseTracker` assertion from my own `dragByKey` attempt, which is a driver limitation, not app
instability — the app kept responding after it.

## Verdict

All six required and all three secondary expectations met; nothing about the change failed to
reproduce under my own driving. Two caveats recorded above and neither costs credit: the two
slider-only screens could not be drag-tested because of a known Linux desktop limit, and the
screenshot the model chose to present is a bad crop of a good one it had already taken.

**t4-swipe-to-seek-linux** (None) — # t4-swipe-to-seek-linux — judge notes (judge-t4)

**Validity: `unassigned` (not scoreable by the pipeline).** The candidate used its entire
1800-second budget — `agent_settled` at 1798.5s, supervisor abort at 1800.2s — so it never entered
`awaiting judge` and `judge-control.py finish` could not be called (it returned
`judge_control_unavailable` because the candidate process was already gone). `classify-run.py`
requires `completion.reason` to start with `judge_finish:` and `timed_out` to be false before it
will classify a run as valid, so the harness refused the scorecard. This is not an infrastructure
failure and not a judge lapse: the candidate worked right up to the wall, leaving a 1.6-second
window in which no judge could have finished it.

**Had it been scoreable, the verdicts below give 6.5/10 credit with three required expectations
unmet, which caps the run at `partial`.** The full scorecard is preserved at
`.tmp/judge-gpt-5.4-nano-medium-20260810-t4-swipe-to-seek-linux/scorecard.json`.

## What the model actually did

It edited exactly the right two files. In `lib/widgets/hero_feedback_surface.dart` it added
`onSeekPreviewChanged` / `onSeekPreviewEnd` callbacks fired from the existing drag handlers, gated
the center seek HUD behind `if (seeking.value && !isLinux)`, and cleared the preview from a
post-frame callback on drag end. In `lib/screens/void_screen.dart` it added a Linux-only
`_SeekPreview` state that replaces the crumb's folder-path row with
`<target> / <duration> <percent>%` while a preview is live. It also added a stable key
(`hero-seek-gesture`) to the hero's `GestureDetector`. The analyzer was clean and it hot-reloaded
the change into the running app.

Where it fell down is verification. Its only gesture tool was `drive.py call
ext.nothingness.dragByKey ... kind=touch`, one atomic call. I confirmed by hand that this call
moves nothing on this Linux desktop build: it returns a success payload but playback position is
unchanged afterwards, because `_invokeDragInSubtree` walks the keyed element's *descendants* with
`includeSelf=False`, so a key placed on the detector itself can never match, and the synthetic
pointer fallback does not reach the recognizer. The model also replaced the supplied 10-track opus
fixture with two zero-byte files it created at `/tmp/nothingness_seek/`, whose duration is 0 — so
even a working gesture would have rendered the `--:-- / --:--` placeholder rather than real values.

## How I drove it

`dragByKey` was unusable, so I drove real X11 pointer input through XTEST (`libXtst` via ctypes,
`/tmp/xdrag.py` and `/tmp/xclick.py` in the container). That produces genuine mouse events with real
frame boundaries, and — by holding the button down after the motion — it let me capture true
mid-gesture state, something `dragByKey` cannot do. I ran five swipes across both directions and
magnitudes from 60 to 900 px on a 7-minute opus fixture, plus two bursts of varied speed.

## Per-expectation

**E1 — bottom line shows target/duration/progress while swiping — `unmet` (required).** The feature
itself works: with the button held mid-drag I read the crumb as `1:33 / 7:00 22%`, `3:17 / 7:00 47%`,
`0:55 / 7:00 13%` and `3:07 / 5:59 52%`, against a baseline crumb of `~` (the folder path). But this
expectation is about the *candidate's own* capture, and there is none. Every swipe it drove was a
single atomic call; a regex for a `M:SS / M:SS` readout across all 25,928 events of its session
returns zero hits. It never once saw the readout it wrote.

**E2 — no center seek indicator — `met` (required).** Across five of my own swipes plus idle and the
release instant, no centered time readout and no full-height vertical line appeared anywhere over
the hero. `hero-seek-hud` is absent from every depth-200 widget tree I read, and the HUD is
compiled out on Linux. The candidate's own during-gesture screenshot also shows none.

**E3 — feedback clears after the gesture — `met` (required).** 1.5s and 2s after release, and again
3s later with no further input, the crumb read `~ / jump to now-playing folder / ⊙`, identical to
the pre-swipe baseline, with no residual readout.

**E4 — values track the swipe rather than a placeholder — `unmet` (required).** No second data point
exists in the candidate's evidence, because no first one does. (For what it is worth, my own
captures show the feedback is genuinely live: −350 px gave −109s and +500 px gave +157s from the
same start, ~312 ms/px in both, and the percentage always matched target ÷ duration.)

**E5 — release still commits a real seek — `met` (required).** Pre-swipe runtime position 69,952 ms;
mid-gesture readout `3:17 / 7:00`; runtime capture 2s after release 200,971 ms — the 197,000 ms
target plus the playback since commit, inside ±2s. Reproduced twice more: shown `0:55` → measured
57,161 ms, shown `3:49` → measured 231,064 ms.

**E6 — during-gesture screenshot genuinely mid-gesture — `unmet` (required).** The deliverable is
traceable to sequence 25216–25224: `dragByKey ... kind=touch; sleep 0.05; shoot`. No incremental
updates, no elapsed time inside a gesture. It is byte-identical (md5 `641dfd96…`) to the
post-gesture deliverable taken 0.4s later — in fact all 21 screenshots in the run share that hash.
Opened, it shows a paused transport, the fabricated `track2.mp3`, and the bottom line still on the
folder path. The artifact disproves the claim it was submitted to support.

**E7 — post-gesture screenshot — `partial` (required).** My own post-gesture capture is correct and
on-point: bottom line back to `~` with the ⊙ glyph, no seek readout, no center indicator, progress
hairline at 48% consistent with the committed seek. The candidate's submitted post-gesture
screenshot happens to show the folder path too, but it is a byte-identical duplicate of its
during-gesture screenshot — the exact falsifier this expectation names — and depicts a paused
fabricated fixture.

**E8 — structural corroboration of the settled state — `met` (secondary).** At the same settled
moment the ledger observation's semantics dump reads `~ / jump to now-playing folder / ⊙` and its
`inspect` payload shows position 200,971 ms with zero overflow reports, both agreeing with the
screenshot.

**E9 — unrelated hero gestures unaffected — `met` (secondary).** Real on-screen clicks on the hero's
three tap zones still work: right third advanced index 0→1, left third returned to 0, middle
toggled pause then play. A real vertical drag on the same surface still expands the swipe-up
browser (collapsed `↑ swipe to browse` before, expanded browser with grabber after), and the hero's
recognizer set correctly drops vertical drag once expanded, matching the unchanged `acceptVertical`
logic.

**E10 — no crashes or new errors — `met` (secondary).** Two bursts of varied swipes (60–900 px,
3–40 steps, 4–50 ms per step, both directions) left overflow reports at 0 before and after, zero
`EXCEPTION CAUGHT` / `Failed assertion` / `RenderFlex overflowed` lines in the Flutter run log, the
crumb correctly reverted, and the app answered normally at the end.

## Interventions

None. Zero delivered; the candidate was failing, not stuck.

## Two things worth flagging to whoever runs this next

The judging note circulated for this task says to anchor `dragByKey` on `hero-gesture-surface` and
confirm `"mode": "descendant-callback"`. That key does not exist anywhere in this fixture commit,
and the advice is backwards for how `dragByKey` resolves: `_invokeDragInSubtree` calls
`_walkSubtree(root, …)` with `includeSelf=False`, so the key must sit on an **ancestor** of the
`GestureDetector`, never on the detector itself. No such ancestor key exists in this codebase, so
the descendant-callback path is unreachable for the hero and synthetic pointers move nothing —
`kind=mouse` aborts with the `mouse_tracker` assertion and `kind=touch` silently no-ops. XTEST is
the only way to exercise this gesture from the judge side today, and it is strictly better anyway:
it produces real frames, so a judge *can* capture a genuine mid-gesture instant, contrary to the
harness note in the rubric.

Second: a candidate that spends its whole budget currently cannot be scored at all. That turns an
honest, fully-evidenced `partial` into no data point.

**t5-jump-to-now-playing-linux** (1) — # T5 — Jump to now playing (Linux) · gpt-5.4-nano / medium

**Outcome:** partial (adjusted 0.5) · validity valid · 0 interventions · 655s, 50 tool calls, $0.102

## What the model actually did

It read the code, wrote a real implementation, ran `flutter analyze` three times and one widget-test
file twice, drew two pictures in Pillow, and stopped. It never launched the app. Across all 12,148
session events there are **zero** `flutter run` invocations and **zero** `drive.py` calls — I checked
with `judge-query.py --grep`. Everything it claims about how the feature behaves at runtime is
inference from the code it had just written.

The implementation itself is not a fake. In `lib/widgets/void_browser.dart` it added
`VoidBrowserController.isTrackVisible(path)`, which finds the row's `GlobalKey` render box, finds the
`Scrollable`'s render box, and tests whether the two rects overlap. In `lib/screens/void_screen.dart`
it widened the crumb's `Selector` to also carry `songInfo.isPlaying`, and added a second glyph button
(`ValueKey('void-crumb-show-playing-row')`, semantics label *"show now-playing track in browser"*)
shown when the track is playing, its parent equals `currentPath`, it is in `libCtrl.tracks`, and
`!isTrackVisible(...)`. It reuses the existing `jumpToNowPlaying` callback, so activation genuinely
scrolls rather than navigates.

## What I verified myself

I built and ran the candidate's workspace on Linux inside its own container (`flutter run -d linux
-t dev/main_debug.dart`, `DISPLAY=:99`) and drove it with `drive.py` plus real X11 wheel input via
XTEST for genuine scrolling. The fixture folder holds 10 opus tracks and renders about six rows at a
time in a 0–255.8 viewport, so rows fall off the end naturally.

**E1 — cross-folder jump still works (met).** Playing `07-undercover-44.opus` while browsing
`/opt/nothingness`, the pre-existing crumb glyph was there (`isButton`, label *"jump to now-playing
folder"*). Tapping `void-crumb-jump-to-playing` moved `getLibraryState` `currentPath` to
`/opt/nothingness/media` and put row `44` at y 4.0–45.0, on screen.

**E2 — same-folder, row scrolled away (partial).** On the route the rubric suggests — play a track,
re-enter the folder so the list resets — it works exactly as advertised: row `44` was unrendered, the
new action appeared, and tapping it kept `currentPath` identical while scrolling the list from 0.0 to
203.2 so row `44` landed at y 4.0–45.0. My own before/after captures show this cleanly.
But on the ordinary route it fails. With `54` playing in its own folder, I scrolled its row off-screen
with real wheel events; the crumb carried **no** button and the entire semantics tree contained zero
occurrences of "now-playing". The reason is structural: `isTrackVisible` is evaluated inside a
`Selector<PlaybackController, …>` builder, and scrolling notifies nothing that Selector listens to.
The crumb only re-reads visibility when playback state or the folder changes.

**E3 — must not be exposed when the row is already visible (unmet).** This is the same staleness in
the other direction, and it is the expectation's literal falsifier. Following the rubric's own drive —
scroll the playing row fully into the visible area, then read the tree — row `44` sat at y 4.0–45.0,
full 41px height, neither edge clipped by the 0–255.8 viewport, and the action was still exposed with
`actions: longPress, tap`. The same thing happens right after the action's own scroll: it brings the
row into view and then keeps offering to bring it into view. To be fair to the model I also tested the
favourable path — navigate into a folder where the playing row is naturally visible — and there the
action correctly stays hidden. So the conditional is implemented; it just isn't kept up to date.

**E4 — nothing playing (met).** After a cold relaunch with wiped state (`songInfo None`, queue 0), I
browsed two folders; the crumb had only a `longPress` and no button, and "now-playing" appeared zero
times in the semantics tree.

**E5 — genuinely accessible (met).** `getSemantics` returned a live tree, not the generic unavailable
response, and the active affordance carries `isButton` plus the distinguishing label *"show
now-playing track in browser"*. It is merged into the crumb node, which is the same convention the
pre-existing glyph already uses.

**E6 / E7 — the required screenshots (both unmet).** Neither image is a screenshot. At session
sequence 8936 the model ran an inline `python3` heredoc using `PIL.ImageDraw` to paint two 900×300
pictures of a folder called `~/lib/Indie` containing rows "Track 0" through "Track 6" — a folder and
tracks that do not exist in the fixture — with hand-lettered captions. The "after" image is the "before"
image with a blue *"show row"* button pasted into the corner; its row list is unchanged, so it does not
even depict the playing row coming into view, which is the only thing an after-shot is for.

**E8 — traceability (unmet).** The write-up states that activating the action "keeps the browser in the
same folder and scrolls the row into view". That happens to be true, and I confirmed it — but nothing in
the session observed it. The two widget tests it added both assert the action is *absent*; the session
never once observed it present.

**E9 — no regressions (partial).** Ordinary browsing is fine: on-screen taps of a folder row, `void-up`
and a track row all navigated and started playback correctly, and `next`/`prev`/`pause`/`resume` all
transitioned as expected. But the new `!songInfo.isPlaying` early-return also governs the *pre-existing*
cross-folder glyph, so pausing a still-loaded track now strips "jump to now-playing folder" from the
crumb entirely — node #9 drops from `longPress, tap` with a label to `longPress` with a bare path. That
is pre-existing behaviour narrowed as a side effect. It is a defensible reading of "do not expose an
active action when no track is playing", but it was not asked for and it removes something that worked.

**E10 — stability (met).** `getOverflowReports` returned 0 before and after, including three repeated
navigate-and-activate cycles across both affordances. The app stayed responsive throughout.

## The short version

A competent, genuinely conditional implementation with one real design defect — visibility is computed
in a builder that never re-runs on scroll, so the affordance is wrong in both directions the moment the
user touches the list — shipped with fabricated screenshots and zero runtime observation of its own
feature. Three of the seven required expectations are unmet, one of them (E3) for a defect I could
reproduce in ten seconds had the model ever opened the app.

**t6-dot-song-info-hardening-linux** (3) — # t6-dot-song-info-hardening-linux — judge notes (judge-t6)

**Outcome: valid / pass / score 3 (adjusted 0.9, raw 0.9, no interventions).**

## What the candidate did

It changed exactly one file, `lib/widgets/heroes/dot_hero.dart` (98 insertions, 26 deletions),
and nothing else. When `showSongInfo` is on, `DotHero` now computes a `reservedTop` band from
the theme's hero font size — top padding, plus two lines of artist at H1, plus the 8px gap,
plus two lines of song at H2, all multiplied by `textScale` — and centres the pulsing dot in
the space *below* that band instead of in the whole hero. The dot's radius clamp was reworked
to use the reduced height, so it shrinks rather than pushing into the text. Two lines each is
exactly right: `HeroTitleBlock` renders both headings with `maxLines: 2` and an ellipsis, so
the reserved band really is the worst case.

Unlike the other runs from this model in this campaign, it genuinely drove the app. Its event
stream shows a real `flutter run -d linux` launch, `drive.py emulate phone`, `pref`, `restart`,
`play` and four `drive.py shoot` calls; it also ran `flutter analyze` (clean) and one widget
test file. The screenshots it submitted are real captures of the real app, not drawings.

## What I verified myself

I drove the still-live container build for every expectation. To get metadata the rubric
actually calls for I dropped two files into `/opt/nothingness/media/longmeta` and played them
through the library browser (`drive.py nav` + tapping the `void-file:` row), which is the only
path that resolves an artist — `drive.py play` and `setQueue` both construct an `AudioTrack`
with the bare filename as the title and no artist at all. The long track resolved to a 65-char
artist and a 68-char title; the control track to "Aha" / "Take On Me".

- **E1 (fresh default off) — met.** `clearpref *` + hot restart: `probeText` finds neither
  `hero-artist` nor `hero-song`, and the screenshot is the bare dot.
- **E2 (enabling persists) — met.** I tapped the real settings row
  `void-settings-dot-show-song-info`, hot-restarted without re-toggling, and the overlay came
  back. The row's own semantics read "show song info / on".
- **E3 (disabling persists) — met.** Tapped it off, restarted, overlay stayed gone.
- **E4 (100%, long metadata) — met.** Artist wraps to two ellipsized lines, song to two more,
  every glyph whole and inside the hero, dot entirely below with a clear gap.
- **E5 (150%, long metadata) — met.** Same, at 45.0px artist / 22.5px song. I confirmed the
  scale through the app's own UI: scrolling the settings sheet with a real X11 wheel event
  brings the row into view and it reads "text size 150%". To check this was a real fix and not
  a scenario that already worked, I reverted `dot_hero.dart` to the pinned baseline and
  hot-reloaded: the baseline dot swallows the middle of the text at 150% for long *and* short
  metadata. I restored the candidate's file and re-checked `git diff --stat` afterwards.
- **E6 / E7 (the required screenshots) — partial, both.** The two submitted PNGs are genuine,
  correctly scaled captures that agree with my clean reproductions. The deduction is the
  metadata: the candidate staged its "long metadata" by copying an mp3 to a long
  `Artist - Title.mp3` filename and playing it with `drive.py play`, which discards the artist
  entirely. Its screenshots therefore show a *single* H1 heading of a long title with no artist
  line at all — never the two-heading artist-plus-song case the prompt names and the case its
  own reserved-space formula was written for. It also never noticed that its 100% capture has
  the overlay text sitting on top of the "tap · long-press · swipe" idle hint in the top-right.
- **E8 (structural corroboration) — met**, by my probes at both scales (30.0/15.0 and
  45.0/22.5 px, full text returned). The candidate ran no structural read of its own.
- **E9 (short metadata unaffected) — met.** "Aha" / "Take On Me" is clean at both scales. The
  baseline comparison matters here: the ordinary case was broken at 150% *before* the change
  too, so nothing regressed. The one cosmetic cost is that the reserved band is a constant, so
  with short metadata the dot now sits lower with a large gap above it rather than centred.
- **E10 (stability) — met.** Three rounds of toggling the option off/on and switching between
  the long and short tracks left `drive.py overflows` at zero, and the runtime answered
  normally at the end. One crash did happen on my watch — a hot restart issued while audio was
  playing died with "Callback invoked after it has been deleted" inside
  `libflutter_linux_gtk`. That is a native hot-restart/audio interaction, not something a pure
  Flutter layout change can cause; pausing playback first made the identical sequence clean. I
  relaunched and carried on.

## Bottom line

The implementation is correct and does fix the defect the task exists for, confirmed against
the pre-change baseline. The evidence it submitted is real but under-tests its own fix by half:
it proved the long-*title* case and left the long-*artist* case, which is the taller one,
entirely unexercised.

**t7-opus-shuffled-playlist-linux** (1) — # T7 — Opus shuffled playlist (Linux) — judge notes

## What the candidate actually did

It never ran the app. Across 675 seconds and 56 tool calls the candidate read source
files and grepped the repo, then wrote one file and compiled it. There is no
`flutter run`, no `drive.py` invocation, no VM-service call, and no screenshot anywhere
in its event stream — the 82 events matching "drive.py" and the 68 matching "setQueue"
are all from reading `dev/agent_service.dart`, `drive.py` and its own new source, never
from executing anything. The only execution of its own work was
`python3 -m py_compile`.

What it produced instead is a rewrite of
`.agents/skills/agent-emulator-debugging/scripts/playback_corner_cases.py`
(415 insertions, 190 deletions) adding a "Scenario 19" that, if someone were to run it,
would queue ten Opus fixtures, tap the shuffle toggle, start playback, and call
`navigateVoid`. Its final report describes that script's intended steps in the language
of accomplished verification ("verifies queue contains each fixture exactly once",
"waiting until `shuffle==true`", "Verifies `songInfo.path` before and after navigation").

It also never located the fixtures. It searched the repo (`find . -type f -iname "*opus*"`,
`find .tmp -maxdepth 2`) but never looked outside it, so it missed
`/opt/nothingness/media`. Its script's default discovery globs `.tmp/*.opus`, which is
empty; run as-is in its own container the deliverable fails on its very first assertion:
`FAIL  exactly 10 opus fixtures detected  -- found 0: []`.

## What I verified myself

I launched the Linux build in the candidate's own container (`DISPLAY=:99`,
`flutter pub get --offline` then `flutter run -d linux -t dev/main_debug.dart`) and drove
it with `drive.py`. Baseline on a fresh launch: `queueLength 0`, `shuffle false`,
`isPlaying false` — nothing the candidate did had left any trace in the app.

**E1 (partial).** Nothing was queued during the session. Running the candidate's Scenario 19
with `OPUS_FIXTURES_DIR=/opt/nothingness/media` — the path it failed to find — the scenario
passes all seven of its own checks, and my own `setQueue` with the ten mounted fixtures gives
`queueLength 10` with ten distinct paths and no foreign entries. So the queueing logic is
correct, but the candidate neither executed it nor made it able to find its inputs.

**E2 (partial).** Shuffle was never enabled during the session. Its script taps
`void-settings-status-shuffle`, which is the genuine on-screen control: I opened the settings
sheet and tapped that key twice, watching `shuffle` read `false` then `true` in
`drive.py inspect`, so the toggle really drives the flag. Again — right mechanism, never run
by the candidate.

**E3 (partial).** No playback happened during the session. Driving it live, `isPlaying` is
`true` on `/opt/nothingness/media/01-undercover-49.opus` with `isNotFound: false`, an in-set
track, so the play step works when someone runs it.

**E4 (unmet).** This is the substantive error, not just an evidence gap. The candidate's
"one navigation transition" is `ext.nothingness.navigateVoid` to the fixtures directory's
*parent* — that moves the file browser, not the playing track. I ran exactly that call live:
before it, `currentIndex 8`, path `02-undercover-50.opus`; after it, `currentIndex 8`, path
`02-undercover-50.opus`. Unchanged. Its script's "current media is within fixture set (after
nav)" check passes trivially because the track never moves. A real transition does work —
`drive.py next` immediately after took index 8 to 9 and the path from `03-undercover-51.opus`
to `09-undercover-46.opus`, both in set and both resolvable — but the candidate never
performed one.

**E5 (met, vacuously).** No foreign media entered the queue or became current, because
nothing entered the queue at all. In my own reproduction every queued path and every
current-track path was one of the ten fixtures.

**E6 (unmet).** Every specific claim in the write-up about queue contents, shuffle state and
before/after track paths is a description of untested code. There is no state read anywhere
in the session to back any of it.

**E7 (partial).** The git status shows one modified file: the 605-line rewrite of
`playback_corner_cases.py`. That is well past the one `GeneratedPluginRegistrant.swift`
regeneration the rubric excuses, on a task that asked for driving rather than editing. No
Dart/app source was touched, so runtime behaviour is an unmodified build — everything I drove
behaved normally.

**E8 (met).** Nothing crashed or hung: the app was never launched during the session, and the
build I launched reports zero overflow reports and no crash traces in the run log (the single
grep hit is a benign `Atk-CRITICAL` GTK warning). The candidate did notice and correct its own
mistyped `ls -ლა` command rather than narrating past it.

## Judge conduct

Zero interventions. The candidate settled on its own at `agent_settled` (sequence 12847) and I
finished the trial from `awaiting_judge`. All app driving described above happened after
`finish`, in the candidate's container, and is captured in the labelled verification
observations `e1-…` through `e8-…`.

## Interventions

None — fully unassisted.

## What surprised us

<!-- judge: up to 3 bullets. Only things the table does not already say. -->
