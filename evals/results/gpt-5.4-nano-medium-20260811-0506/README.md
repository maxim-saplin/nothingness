# gpt-5.4-nano · medium reasoning · 2026-08-11

**15/21** across 7 scored tasks · **$0.6164** · 487.7k in / 126.1k out · unassisted · judge: judge-t1, judge-t2, judge-t3, judge-t4, judge-t5, judge-t6, judge-t7

All seven tasks ran once each, unassisted, with no judge intervention anywhere in the campaign. Six
landed `partial` and one (t7) `pass`; nothing failed outright and nothing was lost to a deadline. The
thing this run shows most clearly is that the model's ceiling here is not its coding — it is whether
it reads its own output. On five of the six capped tasks the implementation was substantially or
entirely correct and the run was capped by a required expectation about *demonstrating* the work: t1
captured a post-seek position of 288 ms against its own 30,000 ms target and reported success anyway;
t2 and t3 both submitted or produced no usable screenshot of a placement that was in fact correct; t4
accepted a `dragByKey` success payload as proof of a swipe that moved nothing, then screenshotted the
settled app nine seconds after release. Only t5 and t6 were capped by defects in the change itself —
a visibility predicate that never re-evaluates on scroll, and a fix that shrank the dot to nothing
without ever constraining the text it was making room for. One provenance caveat, recorded because it
bears on the isolation model rather than on any score: `judge-run.py publish` resolves its destination
from the repo root of the script invoked rather than from the working directory, so two judges wrote
into the shared results tree instead of their sandboxes. Both were caught, and the tree was verified
clean after each; t7's was the last task, so no judge could have read a peer's verdict.

| Task | Score | Outcome | Assisted | In | Out | Reasoning | Cache | Cost | $/point |
| --- | --- | --- | --- | --- | --- | --- | --- | --- | --- |
| `t1-playback-smoke-linux` | 2 | partial | no | 33.2k | 6.6k | 4.2k | 544.3k | $0.0261 | $0.0131 |
| `t2-settings-placement-linux` | 2 | partial | no | 34.6k | 10.2k | 6.7k | 1121.0k | $0.0424 | $0.0212 |
| `t3-settings-placement-color-scheme-linux` | 2 | partial | no | 53.9k | 14.6k | 11.3k | 959.7k | $0.0483 | $0.0241 |
| `t4-swipe-to-seek-linux` | 2 | partial | no | 83.6k | 24.3k | 14.1k | 3689.0k | $0.1212 | $0.0606 |
| `t5-jump-to-now-playing-linux` | 2 | partial | no | 67.2k | 31.8k | 24.0k | 5026.0k | $0.1540 | $0.0770 |
| `t6-dot-song-info-hardening-linux` | 2 | partial | no | 163.9k | 27.0k | 20.1k | 4843.8k | $0.1637 | $0.0819 |
| `t7-opus-shuffled-playlist-linux` | 3 | pass | no | 51.3k | 11.6k | 7.6k | 1784.3k | $0.0607 | $0.0202 |
| **Total** | **15/21** | | no | 487.7k | 126.1k | 87.9k | 17968.1k | **$0.6164** | **$0.0411** |

## What happened

**t1-playback-smoke-linux** (2) — # T1 · Playback smoke (Linux) — judge notes

Run: `t1-t7-gpt-5.4-nano-medium-t1-playback-smoke-linux-trial-01-attempt-04`
Model: `azure-openai-responses / gpt-5.4-nano` (thinking: medium), identity verified.
Outcome: **partial** (adjusted 0.714, no penalty). Interventions: **0**.
Candidate settled on its own at 291s of a 1800s budget; I finished it in `awaiting_judge`.

## What the candidate actually did

It read the repo's own regression tooling first (`tool/regression/README.md`, `smoke.txt`,
`playback.txt`, `drive.py`, `dev/agent_service.dart`), then decided to *extend the existing
`tool/regression/smoke.txt` replay script* with a playback section rather than issue transport calls
ad hoc. That section sets a 10-track queue from `/opt/nothingness/media` via
`ext.nothingness.setQueue`, then runs `resume` / `inspect` / `pause` / `inspect` / `resume` /
`seek 0:30` / `inspect` / `next` / `inspect` / `overflows`.

It launched the real app itself — `flutter run -d linux --debug -t dev/main_debug.dart` with the
fifo, run log and a sandboxed `DRIVE_DESKTOP_HOME` all exported — and drove it through `drive.py`.
It then ran the whole smoke script twice and reported done. Its final report is short and vague: it
lists the script steps and says only "playback transport actions succeeded and `overflows` reported
**0**", quoting no observed positions, indices or track names.

## E1 — met

Genuinely live. The candidate's own event stream shows `drive.py preflight`, `inspect`, `setQueue`,
`resume`, `pause`, `next`, `seek`, `overflows`, `screen`, `shoot`, `settings open/close` all
answering with real payloads. I confirmed the same session myself: `drive.py contract` lists 31
registered `ext.nothingness.*` extensions and a fresh `inspect` answers right now. It used
`dev/main_debug.dart`, the entrypoint that registers the extensions — not the `main_test.dart`
failure mode the rubric warns about.

## E2 — met

The candidate's three inspects bracket the transition correctly: `isPlaying` true at index 0, false
after `pause`, true again after `resume`. I reproduced the whole sequence live against the same
running app with labelled captures — `e2-playing` (true, pos 1728 ms), `e2-paused` (false, pos
4138 ms), `e2-resumed` (true, pos 5952 ms). Nothing assumed here.

## E3 — met

`setQueue` returned `queued: 10` and the following inspect shows `queueLength: 10`, `shuffle: false`
and the full queue array in the order passed, so the multi-track precondition was real. `next`
advanced `currentIndex` 0 → 1 with the active path changing `01-undercover-49.opus` →
`02-undercover-50.opus` in the candidate's own post-call inspect. I reproduced forward skips live
(`e3-pre-skip` index 0 / 01-undercover-49 → `e3-post-skip` index 1 / 02-undercover-50, then a second
`next` to index 2). I also tried `prev`: it restarted the current track rather than stepping back,
which is the documented >3s behaviour, not a defect — the candidate never exercised `prev`.

## E4 — unmet (this is what caps the run)

The candidate's script does the right thing structurally — it inspects immediately after `seek 0:30`
— but the read it captured says `position: 288`. Against a 30,000 ms target, from a pre-seek position
of 53 ms. The fast-forward simply did not take effect in its run, and the candidate reported the
transport actions as having succeeded anyway, taking the `seek` call's own `{"ok": true,
"positionMs": 30000}` reply as the result and never looking at the state read sitting directly below
it.

This is not an app defect, and I checked that carefully before scoring it:

- Seek while playing works. Direct `drive.py` pair: 84,501 ms → 30,042 ms for a `0:30` target.
  Labelled capture `e4-post-seek-playing`: 32,170 ms → 71,311 ms for a `1:10` target (the ~1.3s
  overshoot is the ~3.5s verify bundle running while playback continues).
- The candidate's *exact* sequence — setQueue, resume, pause, resume, seek 0:30, inspect — landed at
  30,042 ms in 3 of 3 reproductions just now.

So the candidate hit a genuine near-zero-position race (its first `resume` read only 53 ms in, versus
373–512 ms in my reproductions, so the source load was very likely still settling and reset position
to 0 after the seek applied). That race is exactly the kind of thing this task exists to catch, and
the candidate had the disconfirming evidence in hand.

One incidental build quirk I found while checking, which does **not** bear on this verdict because
the candidate's seek was issued while playing: `seek` is a no-op while **paused** — it replies
`ok` with the requested `positionMs`, but the reported position does not move (`e4-pre-seek` 32,170 ms
→ `e4-post-seek` 32,266 ms after a `0:45` seek). Worth knowing for future seek testing.

## E5 — partial

Most of the report is traceable: the launch command, the `replay` invocation and "overflows reported
0" all match real tool results in the session. But the blanket "playback transport actions succeeded"
covers the seek, whose only in-session observation contradicts it. The report also cites no observed
values whatsoever — no positions, no indices, no track names — which is precisely what let the
contradiction pass unnoticed. Nothing was fabricated; the failure is one unbacked aggregate claim
plus a write-up too thin to expose it.

## E6 — partial

The workspace diff is not empty: ` M tool/regression/smoke.txt`, 13 insertions and 1 deletion. The
task asked only to drive and smoke-test. In mitigation, the change is confined to a regression replay
script with no effect on app runtime behaviour — my live re-check of play/pause/skip/seek behaved
exactly as an unmodified build would — and it is arguably a reasonable engineering instinct
(extending the project's own harness rather than firing one-off calls). But it is still a tracked
source file touched beyond the single regeneration the rubric permits, so it scores `partial`.

Notable: the known `macos/Flutter/GeneratedPluginRegistrant.swift` and
`linux/flutter/generated_plugins.cmake` regenerations did **not** occur at all this run. The only
diff is the candidate's own edit.

## E7 — met

Two real faults, both noticed and both fixed before anything was reported done:

1. A 20-attempt `inspect` poll failed with `could not find Dart VM service URI` (the Linux build was
   still compiling). The candidate listed `/tmp`, tailed the run log, saw the compile in progress,
   and retried until `inspect` answered.
2. Its first `replay` exited code 1 on `error: No escaped character` — it had written the `setQueue`
   line with backslash line continuations, which `drive.py replay` does not support, so the playback
   section never ran that time. It read the file back, joined the line, and re-ran the entire script
   successfully. It did not report the first, broken run as a pass.

No crash or hang anywhere in the run log — the only errors are ALSA `No such file or directory`
noise, expected because the container has no audio device (SoLoud still clocks real-time). `overflows`
is 0 throughout. And the session answering me is demonstrably the same continuous one, not a silent
relaunch: before I touched anything it had free-run from the candidate's track 02 onward to track 03
at position 73,066 ms.

## Genuinely surprising

The candidate's methodology was better than its reading. It correctly discovered on its own — from
reading `dev/agent_service.dart` — that `play` maps to `playTrackByPath` and that a real queue needs
`setQueue`, which is the trap the rubric explicitly flags for E3, and it structured its script to
inspect after every transport call. It then failed on the one thing that structure existed to catch,
because it never read its own output.

**t2-settings-placement-linux** (2) — # T2 · Cassette settings placement (Linux) — judge-t2

**Outcome: `partial`** (raw 0.875, penalty 0, adjusted 0.875; capped at `partial` because required E5 is `unmet`).
0 interventions. Candidate settled on its own at 531s of an 1800s budget for $0.042.

## What the model actually did

It spent its first ~4 minutes reading the repo, then made a single-file change to
`lib/widgets/void_settings_sheet.dart` (24 insertions, 10 deletions, nothing else touched). The
approach: wrap the existing cassette-variant `_Cycle` in the `DISPLAY` section with `if
(!Platform.isLinux)`, and add a second copy of that row in the `LOOK` group immediately after the
`void-settings-screen` row, guarded by `if (Platform.isLinux && cassetteCfg != null)` where
`cassetteCfg` is the current screen config downcast to `CassetteScreenConfig`. It hit two rounds of
analyzer errors (a missing paren, an undefined name, then an unnecessary cast and a no-op `!`) and
cleared them before moving on — `flutter analyze` was clean at the end.

It then built and launched the Linux app for real, set the screen to cassette, opened the settings
sheet, took a screenshot, and cropped the top half of it with PIL. It never looked at either image
(it only `ls -l`'d their byte sizes), and finished by presenting the crop as proof.

I did not intervene at any point.

## What I verified with my own hands

I drove the candidate's still-running build in its container throughout — `drive.py` reads,
`tapByKey` activations, `getSemantics`, `getSettings`, `getOverflowReports`, and my own screenshots
captured through `judge-verify.py`. I read the settings sheet via `getSemantics` (not the widget
tree) and used consecutive `indexInParent` with abutting y-ranges to settle adjacency.

**E1 — met.** With screen = cassette the sheet reads `indexInParent 5 = "screen / cassette"`
(y 231–276) followed immediately by `indexInParent 6 = "variant / Tape · Mono"` (y 276–321), then
`immersive` at 7. Abutting rects, consecutive indices, no group header or gap between them. My own
screenshot of that state, read plainly, shows the same order rendered: `screen  cassette` and
directly under it `variant  Tape · Amber`. The row was genuinely removed from `DISPLAY`, not
duplicated — the `DISPLAY` group now reads debug layout / text size / haptics.

**E2 — met.** Five consecutive on-screen taps of `void-settings-screen` walked
cassette → spectrum → polo → dot → void → cassette, i.e. the full established cycle back to the
start, with the row's own displayed value tracking every step. Separately, `drive.py screen <name>`
for all five screens was reflected back both in `getSettings` (`screenType`) and in the row's
displayed value, so the row and the setting are still connected in both directions. On the second
visit to cassette the E1 adjacency held again, with no stale state.

**E3 — met.** This was the "moved the label, dropped the wiring" risk, and the wiring survived.
Tapping `void-settings-cassette-variant` in its new position cycled
Mono → Amber → Colour → Minimal → Mono, the row's value tracking each tap. `drive.py cassettevariant
3/1/4/2` moved it the other way and the row's value matched each time. The change is real, not
cosmetic: with the sheet closed, variant 2 renders the amber tape artwork on the cassette screen
while variant 4 renders the minimal "SIDE A / No tape loaded" layout.

**E4 — met.** For spectrum, polo, dot and void, the row immediately after `screen` is `immersive` —
the pre-change next row — with no cassette-only control injected anywhere. Each of those screens'
own controls still respond to on-screen activation: spectrum `bar count` 24→8→12, polo `bar style`
solid→glow, dot `show song info` off→on, void `debug layout` off→on.

**E5 — unmet. This is the one real failure.** Both PNGs the candidate produced show the **cassette
playback screen** — the tape-reel artwork, the transport buttons, the word "empty" — and not the
settings sheet at all. Not a single settings row appears in either image, so the adjacency they are
captioned as proving cannot be read off them. The cause is visible in its event stream: it chained
`drive.py screen cassette && drive.py settings open && drive.py shoot cassette_settings_top` as one
command that returned in 0.27s, so `ext.nothingness.screenshot` rasterized a frame from before the
sheet's first paint. It then cropped that same wrong PNG (`img.crop((0, h*0.08, w, h*0.55))`) and
embedded the crop in its final answer under the heading "Screenshot (Cassette selected; relevant
region)". This is the second recorded field-test failure mode exactly: the model's own screenshot,
read plainly, does not show what its write-up claims.

To be fair to it I checked this was not a harness limitation. It is not: my own captures of the same
state, same app, same 1278×720 resolution show the sheet plainly. The sheet does take a moment to
appear — I saw the same one-state lag when `drive.py settings close` returned `{"closed": true}`
while the screenshot still showed the sheet — but a short wait, or simply looking at the resulting
image once, is all it took. The candidate did neither.

**E6 — met.** The placement claim does not rest on an image: `getSemantics` gives the consecutive
`indexInParent` 5/6 with abutting y-ranges and the live variant value, and `getSettings` confirms
`screenType: cassette` in the same capture. Structural dump and screenshot agree on both order and
value. (`getSemantics` answered fully on this build — it was not the "semantics not available" case
the rubric warns about.)

**E7 — met.** The full row list is unchanged apart from the inserted row. Across cassette plus all
four other screens the order is MODE / operating mode / LOOK / theme / variant (theme) / screen /
[cassette variant, cassette only] / immersive / transport / browser / full screen / ui scale /
LIBRARY / prefer filename / smart folders / then the per-screen SOUND and DISPLAY groups — matching
the pre-change source order for every unrelated pair, with nothing added, removed or renamed. I also
confirmed a full dump before and after tapping five unrelated rows was byte-identical in ordering.
Every unrelated row I could activate changed its displayed value: immersive off→on, transport
top→off, browser swipe up→fixed, prefer filename off→on, smart folders on→off, theme variant
system→dark, debug layout off→on, plus the spectrum SOUND rows. The `theme` row cycles to itself,
which is correct rather than broken — `ThemeId` has exactly one value (`void_`).

**E8 — met.** `getOverflowReports` was `count: 0` both before and after roughly forty sheet opens,
screen switches and row activations. At the end the app still answered `inspect` normally, `git
status` showed only the one modified file, and the runtime lens reported no overflows.

## Limits of my own testing, stated so they are not read as candidate faults

- **Sliders cannot be driven by synthetic pointers on this build.** Polo's and void's only
  *screen-specific* controls are text-size sliders, so for those two screens I exercised a
  neighbouring row of theirs instead (polo's SOUND `bar style`, void's `debug layout`). That is my
  blind spot, not a gap in the candidate's work.
- **`void-settings-spectrum-text-color` is unreachable by key**, because the settings `ListView`
  only builds ~20 children and spectrum's `DISPLAY` group starts at index 19. Pre-existing harness
  limitation; I used spectrum's SOUND rows instead.

## One judgement call worth flagging to the manager

E1's falsifier list ends with "…or the screenshot the candidate supplies doesn't actually show the
two rows adjacent even though the write-up claims it does," which read in isolation would also fire
here. I scored E1 `met` anyway, because the rubric's own "How to judge this task" section tells the
judge to settle every expectation by driving the running build rather than trusting the candidate's
screenshot, maps the three prompt clauses to E1 (where the row sits) and E5 (a screenshot proving
it), and states that a correct implementation must pass every expectation. The placement genuinely
is correct in the running app — I confirmed it four independent ways — so the screenshot defect is
priced once, in E5, rather than twice. Either reading lands the run at `partial`, since E5 is
required and unmet; only the raw score differs (0.875 vs 0.75). Flagging it in case the manager
reads that clause more literally.

**t3-settings-placement-color-scheme-linux** (2) — # T3 — cassette settings placement + `color scheme` rename (Linux)

Judge: judge-t3. Campaign `nano-medium-20260811`. Model: azure-openai-responses / gpt-5.4-nano /
thinking medium. Interventions delivered: **0**.

## What the candidate did

It read its way around the settings sheet quickly and landed a correct, minimal five-line change to
`lib/widgets/void_settings_sheet.dart`, and nothing else:

- renamed the cassette variant row's label from `'variant'` to `'color scheme'` (key
  `void-settings-cassette-variant` unchanged, handler untouched);
- inserted `if (cfg is CassetteScreenConfig) ...displayRows(cfg)` directly after the
  `void-settings-screen` row in the LOOK group;
- changed the DISPLAY group's `...displayRows(cfg)` to `if (cfg is! CassetteScreenConfig)`, so the
  cluster is not rendered twice.

It ran `flutter analyze` (clean) and the existing `test/widgets/void_settings_sheet_test.dart` (passing).

Then it spent the remaining **two thirds of its budget** failing to produce the required screenshot.
Rather than launching the app, it wrote `test/capture_settings_cassette_screenshot_test.dart`, a
widget test that pumps `VoidSettingsSheet` inside a `RepaintBoundary` and calls
`boundary.toImage()`. That call hangs in `flutter_tester`; the test hit flutter's own 10-minute
per-test timeout twice (once with `pumpAndSettle`, once after switching to `pump(200ms)`), and a
third run was still going when the clock ran out. Its only artifact,
`/workspace/.tmp/cassette_settings_region.png`, is **0 bytes**. In its last ~70 seconds it started
reading `drive.py`, `dev/agent_service.dart` and `dev/main_debug.dart` — it had just worked out that
the app needed launching — but the deadline arrived first. The event stream contains no `flutter run`
and no `drive.py` invocation at all, and it never wrote a final report (cut mid-tool-call).

The harness's own deadline guard auto-finished the run at 1648s of 1800s with `timed_out: false` and
a `judge_finish:` reason, so the run is scoreable. My own `judge-control.py finish` raced with it by
a few seconds and returned `judge_control_unavailable` — the guard had already closed the socket.

## What I verified myself

The candidate never launched the app, so I did: `flutter pub get --offline`, then
`flutter run -d linux --debug -t dev/main_debug.dart` under `DISPLAY=:99` with the default
`/tmp/flutter_run.log` and `/tmp/flutter_input` fifo. Everything below is from driving that build.

**E1 — placement (met).** With `screen` cycled to cassette, the sheet's semantics dump shows
`screen | cassette` at `indexInParent` 5, rect y 231–276, immediately followed by
`color scheme | Tape · Mono` at `indexInParent` 6, rect y 276–321. Consecutive indices, abutting
y-ranges, nothing between them. The screenshot in the same capture reads the same way plainly.

**E2 — exact label (met).** The semantics node carries `color scheme` on the label line and
`Tape · Mono` on the value line, so the rename went to the label and not the value. I scrolled the
whole 22-row sheet with real X11 wheel input (XTEST) and found exactly one `color scheme` row and no
leftover cassette `variant` row anywhere. The `variant | system` row at index 4 is the pre-existing
app-wide theme-variant row, which the rubric itself names as one of the sheet's normal labels.

**E3 — the `screen` row still works (met).** Five on-screen taps of `void-settings-screen` advanced
spectrum → polo → dot → void → cassette, the full established cycle back to where it started, and
the row's own displayed value matched `getSettings` at every step. The direct `drive.py screen <name>`
calls for all five types also landed and were reflected back in the row's value. Switching away from
cassette and back restored the adjacency from E1.

**E4 — the renamed row still works (met).** Four taps of the row cycled
Tape · Mono → Tape · Amber → Tape · Colour → Minimal → Tape · Mono. Separately,
`drive.py cassettevariant 2`, `3`, `1`, `2` each landed with the row's displayed value tracking it
(Amber, Colour, Mono, Amber). Both directions of exercising it work; the label rename did not
disconnect the handler.

**E5 — scoped to cassette (met).** For spectrum, polo, dot and void, the row immediately after
`screen` is that screen's own `immersive` row, never a cassette control, and a full-scroll scan of
each sheet found no `color scheme` label anywhere. Each screen's own DISPLAY rows are all still
present in their baseline order. On-screen taps: spectrum's `text color` Cyan→Purple, spectrum's
`media controls color` Cyan→Purple, dot's `show song info` off→on. Polo and void have no own control
except a text-size slider, which synthetic pointers cannot activate on this build — that is my
blind spot, not a candidate defect, and I am not scoring it against them.

**E6 — required screenshot (unmet).** No usable screenshot exists among the candidate's
deliverables: a 0-byte PNG from a test harness that hung, and no evidence anywhere that it ever ran
the app. The screenshot I cite is my own, taken after I launched the build myself, which is why E1/E2
are `met` while E6 is not: the work is right, the proof the prompt asked for was never produced.

**E7 — corroborating dump (met).** Each capture carries `semantics.json`, `settings.json`
(`"screenType": "cassette"`) and a 170KB widget tree beside the screenshot; row order, exact label
text and current variant value agree across all of them. `getSemantics` answered normally on this
desktop build — no accessibility-service problem.

**E8 — other groups undisturbed (met).** Every genuinely unrelated row keeps its baseline pairwise
order on all five screens (MODE/operating mode, LOOK/theme/variant/screen, immersive, transport,
browser, full screen, ui scale, the LIBRARY rows, DISPLAY/debug layout, ABOUT/help/version); none
were added, removed or renamed. `transport` (bottom→top), `browser` (fixed→swipe up) and `immersive`
(off→on) all responded to on-screen taps. Two things I checked before crediting this: cassette's own
`text size` and `haptics` rows did move up with the variant row, which is the prompt's own "its
cassette variant controls" (plural) clause rather than an accidental reorder; and `theme` taps to
itself because `ThemeId` has exactly one value (`void_`) in this fixture — pre-existing, not a
regression.

**E9 — no crashes (met).** `drive.py overflows` reported count 0 both before and after the whole
exercise, the run log holds zero exceptions or failed assertions after all the screen switching,
variant cycling and two open/close cycles of the sheet, and the final runtime capture answered
normally with the app still live.

## Worth flagging

- One cosmetic consequence of the fix nobody's expectation covers: with cassette selected, the
  DISPLAY group is left holding only the debug-only `debug layout` row, so a release build would
  render an empty DISPLAY header on that screen.
- `judge-run.py observe`'s `elapsed_seconds` tracked the last *event* timestamp, not wall clock. While
  the candidate sat in a 10-minute hung tool call it kept reporting 323.4s against a 1800s budget
  while ~11 real minutes had passed, and it returned instantly instead of polling for ~2 minutes. A
  judge trusting that number would have believed it had 25 minutes of headroom when it had 13. I
  tracked the deadline from `started_at` by hand instead.

**t4-swipe-to-seek-linux** (2) — # T4 · Swipe-to-seek feedback placement (Linux) — judge notes

**Run:** `t1-t7-gpt-5.4-nano-medium-t4-swipe-to-seek-linux-trial-01-attempt-04`
**Model:** gpt-5.4-nano, thinking medium · 885 s of 1800 s budget · 98 tool calls · $0.121 · 0 interventions

## What the candidate did

It read the fixture carefully before touching it — `void_screen.dart`, `hero_feedback_surface.dart`,
`agent_service.dart`, and `drive.py` including the `dragByKey` implementation — then made a small,
well-aimed change across three files (119 insertions, 79 deletions):

- Deleted the `_SeekHud` widget and its `hero-seek-hud` key from `HeroFeedbackSurface`, removing the
  centered time readout and full-height vertical preview line entirely.
- Added two optional callbacks, `onSeekPreviewUpdate(target, duration)` and `onSeekPreviewEnd`, fired
  from `onSeekStart` / `onSeekUpdate` / `onSeekEnd`, and turned `seekTargetMs` from a `useState` into a
  `useRef` so the hero no longer rebuilds per drag tick.
- In `VoidScreen`, held the preview in a `useState<({int targetMs, int durationMs})?>` (Linux-only via
  `Platform.isLinux`) and, when set, rendered `'$target / $duration · $pct%'` in the crumb row in place
  of the folder path. Cleared it on a 450 ms timer after drag end, with the timer cancelled on unmount.
- Updated `test/widgets/hero_feedback_surface_test.dart` to assert the new callbacks instead of the
  deleted HUD key. `flutter analyze` came back clean.

It then launched the Linux app for real (`flutter pub get --offline`, then `flutter run -d linux`),
navigated the browser to `/opt/nothingness/media`, played `01-undercover-49.opus`, and tried to drive
the gesture. That last part is where it came apart.

## Where it fell short

The candidate's whole gesture evidence is one atomic call:
`ext.nothingness.dragByKey key=hero-gesture-surface dx=180 dy=0 steps=12 kind=touch`. Its first attempt
with `kind=mouse` aborted on the documented `mouse_tracker.dart` assertion, so it retried with
`kind=touch`, got a success payload back, and treated that as a swipe having happened. It never checked.
I did: four `dragByKey kind=touch` reproductions of my own (dx = +240, −240, +600, −600) moved nothing
at all — playback position advanced only by the seconds of wall-clock that had passed, the seek-preview
hook state stayed `null`, and the crumb never changed. The success payload is a lie, exactly as the
harness notes warn.

Then, in a *separate* bash invocation about 9 seconds after that call had already returned, it ran
`sleep 0.15; drive.py shoot seek_during`. So the "during-gesture" screenshot was taken by a different
process, well after release, of a gesture that had not moved anything in the first place. There is no
incremental pointer instrumentation and no mid-gesture structured read anywhere in the session. Its own
final message half-admits the shape of the problem — it says it "used a short delay to allow QA
screenshot capture" — but a 450 ms clear window does not help when the capture is nine seconds late.

The deliverable proves it. `seek_during.png` shows the bottom line reading `/opt/nothingness/media` —
the folder path, unchanged, no target, no duration, no progress. It differs from `seek_post.png` in 510
of 920160 pixels (a progress hairline advancing a hair), so the two "before and after" screenshots are
effectively the same settled frame. This is the precise failure the rubric is calibrated against: a
screenshot that disproves the claim it was submitted to support.

## What I verified myself

`dragByKey` cannot drive this hero, so I drove it with real X11 input through XTEST (~40 lines of
`ctypes`), holding the button down after the motion so a capture could land on a true mid-gesture
instant. The Flutter client area sits at X11 offset (+1, +20) and the hero surface spans y ≈ 0–228, so
the press landed at (450, 135) and moved horizontally. I seeked well inside a 7-minute track
(`07-undercover-44.opus`, 420623 ms) before every directional test, so no result is an artifact of the
`[0, duration]` clamp.

- **Mid-gesture, button still down:** the crumb row read `4:10 / 7:00 · 60%` — target position, total
  duration, and a progress percentage — with the seek-preview hook state populated as
  `(durationMs: 420623, targetMs: 250315)`. The feature works, and works well.
- **No center indicator:** zero `hero-seek-hud` nodes in every tree I captured, and no centered readout
  or vertical line visible in any screenshot, mid-gesture or at rest, across seven separate swipes.
- **Direction and proportion:** rightward from 92.3 s targeted 195.0 s; leftward from 220.3 s targeted
  117.5 s (`1:57 / 7:00 · 28%`). Both proportional to the distance dragged.
- **Clears on release:** hook state back to `null`, crumb back to `/opt/nothingness/media`.
- **Seek still commits:** 92272 ms before, target 195024 ms shown mid-drag, 197157 ms after release —
  the target plus the ~2 s of playback that elapsed while the capture was taken.
- **Other gestures intact:** all three hero tap zones fire as real clicks (left third restarts the
  current track, which is correct for position > 3 s; centre toggles play/pause; right advances the
  index), and an upward drag still expands the swipe-up browser.
- **No new instability:** ten swipes at varying direction, magnitude and speed left the overflow count
  at 0 and the app responsive.

Two things worth recording so nobody misreads them as candidate defects. Seeking while *paused* does
not update the reported position, so a paused seek-commit test looks like a failure that isn't — I had
to redo that check with playback running. And the run log carries
`SoLoudInvalidParameterException` on seeks that clamp to 0 or past the end; a plain `drive.py seek 0`
with no gesture at all reproduces it, so it belongs to the pre-existing seek path.

## Verdicts

| # | Tier | Verdict | One-line reason |
|---|------|---------|-----------------|
| E1 | required | **unmet** | No mid-gesture capture exists in the session; its during-shot shows the folder path unchanged. |
| E2 | required | met | No center readout or vertical line in any of seven reproductions; `_SeekHud` deleted outright. |
| E3 | required | met | Crumb and hook state revert after release, verified more than 2 s later. |
| E4 | required | **unmet** | Only one drag call in the whole session and no legible target value captured — no data points to compare. |
| E5 | required | met | Release commits the seek to the last-shown target (92.3 s → 195.0 s target → 197.2 s). |
| E6 | required | **unmet** | The during-screenshot is a separate call ~9 s post-release and a near-duplicate of the post shot. |
| E7 | required | met | My settled screenshot shows the folder path, no readout, no center indicator. |
| E8 | secondary | met | Tree and runtime lenses from the settled moment corroborate the post-gesture image. |
| E9 | secondary | met | All three tap zones and the vertical-drag browser reveal still work. |
| E10 | secondary | met | Overflow count 0 before and after a ten-swipe burst; app responsive. |

The shape of this result: the implementation is genuinely good — arguably the cleanest possible reading
of the prompt, and it survived every functional probe I aimed at it — but the candidate never observed
its own work. All three failures are the same failure: it accepted a `dragByKey` success payload as
proof a swipe had happened, and screenshotted a settled app while believing it was mid-gesture. The
verification gap, not the code, is what caps this run.

**t5-jump-to-now-playing-linux** (2) — # T5 · Jump to now playing (Linux) — judge notes

Run `t1-t7-gpt-5.4-nano-medium-t5-jump-to-now-playing-linux-trial-01-attempt-05`, gpt-5.4-nano
(thinking: medium), 1046 s of a 2700 s budget, 86 tool calls, $0.154, zero interventions. The
candidate settled on its own and was finished from `awaiting_judge`.

## What the model actually did

It read the browser and screen code, found the pre-existing `⊙` crumb affordance (B-015/B-031) that
already appeared when `dirname(playing)` differed from the browsed folder, and hardened the
*condition* rather than rebuilding the feature. Two files, +105/−10:

- `lib/widgets/void_browser.dart`: added a `isTrackVisible(path)` probe to `VoidBrowserController`,
  registered alongside the existing `scrollToTrack` handle. It finds the row's `GlobalKey` context,
  and returns whether the row's global rect `overlaps` the scroll viewport's rect; a row that was
  never built (fully off-screen) returns false, and it falls back to "visible" when the browser
  isn't mounted so no premature affordance shows.
- `lib/screens/void_screen.dart`: the crumb's condition became "parent folder differs **or** the
  playing track is in this folder's track list but its row isn't visible", gated behind a
  post-first-frame `visibilityProbeReady` flag. It also relabelled the button from
  `jump to now-playing folder` to `scroll to now-playing track`, and bumped `rebuildTick` after
  `scrollToTrack` so the glyph drops once the row lands. Activation reuses the existing
  `jumpToNowPlaying`, which already skipped `loadFolder` when the folder was correct.

It got `flutter analyze` to clean and iterated until all 40 `void_screen_test.dart` tests passed,
including the existing B-015/B-031 jump-glyph tests it initially broke. For runtime proof it launched
the Linux build, navigated to the fixtures folder, played `01-undercover-49.opus`, shot
`before_out_of_view2.png`, tapped `void-crumb-jump-to-playing`, and shot `after_in_view2.png`. That
one before/after pair is the entirety of its runtime verification — it never checked the no-track
state, never browsed a different folder while playing, and never read `getLibraryState`, the widget
tree, or the semantics tree after activating.

## What I verified myself

I drove the still-live container directly (`DISPLAY=:99`, the candidate's own
`flutter_run_nothingness_linux_debug.log` session) and captured 13 labelled `judge-verify.py`
bundles. `getSemantics` is fully available on this build, which made the crumb node readable even
though the widget tree truncates past the 128 k cap before reaching it. The list is a reverse
`ListView` of 11 children (10 tracks + the `..` row) with a 255.8-logical-px viewport and 41 px rows,
so a fresh `nav` resets to offset 0 and leaves tracks 44–47 off-screen.

**E1 (cross-folder) — met.** With track 47 playing and the browser at `/opt/nothingness`, the crumb
carried the affordance. Tapping it left the browser at `/opt/nothingness/media` with 47's row at
y 103.4–144.4 inside the 0–255.8 viewport, and the affordance correctly cleared.

**E2 (same folder, row scrolled out) — partial.** On the route the rubric prefers it works exactly as
specified: freshly loaded media folder at offset 0 with 47 playing and off-screen, affordance present,
and activation kept `currentPath` byte-identical while centring the row. But the predicate is
evaluated only inside the crumb's `Selector` builder, so it is never re-read when the list scrolls.
After a real X11 wheel scroll (XTEST, button 5) pushed 47 back fully off-screen in the same correct
folder — 47 still playing at position 7.4 s, visible rows 49–54 + `..` — the affordance was gone
from the semantics tree entirely. That is E2's own falsifier on the more natural user path, so half
the expectation holds and half doesn't.

**E3 (not active when the row is fully visible) — unmet, and this is what caps the run.** Starting
from the affordance-shown state, two wheel clicks up put 47's row at y 29.8–70.8, fully inside the
viewport with neither edge clipped (confirmed on the screenshot, not just the rects). The crumb still
carried `scroll to now-playing track` with `actions: tap` / `flags: isButton`, and it was genuinely
live: tapping it re-centred the list from offset 106.0 to 183.6. Same root cause as the E2 gap — the
condition goes stale in both directions because nothing re-evaluates it on scroll. Note the
implementation would also treat a merely half-clipped row as "visible" (`Rect.overlaps`), which the
rubric explicitly says should still expose the action.

**E4 (nothing playing) — met.** With `songInfo` null, both `/opt/nothingness/media` and
`/opt/nothingness` showed zero `jump`/`now-playing` hits in the semantics tree *and* the widget tree.

**E5 (accessibility) — met.** The active affordance is a real semantics node with `tap`, `isButton`,
and a distinguishing label. Worth flagging for later tasks: the label merges into the crumb's own
node alongside the path text (`"/opt/nothingness/media / scroll to now-playing track / ⊙"`) rather
than standing alone, so a screen reader reads them together.

**E6/E7 (screenshots) — both met, both genuine.** I reproduced the candidate's exact pre- and
post-activation states live and they match its images pixel-for-pixel: before shows 49 playing with
only a ~6 px sliver of its 41 px row at the list's top edge and the affordance present; after shows 49
fully visible and highlighted, crumb path unchanged, affordance gone. Both are real `drive.py shoot`
captures recorded in the event stream at 1278×720. The before state is a near-fully-clipped row rather
than a wholly absent one, which per the rubric's own boundary clause still counts as "not visible".

**E8 (traceability) — partial.** Its write-up asserts the action appears "only when a track is
actively playing" and when "the playing track's parent folder differs". Neither has any supporting
observation anywhere in the session; both happen to be true, but it never looked.

**E9 (no regressions) — met.** Real on-screen taps still navigate (`void-up` → `/opt/nothingness`,
the folder row back again), an on-screen track-row tap started playback with a 10-track queue, and
`next`/`prev`/`pause`/`resume` all behaved. `prev` holding position when >3 s into a track is the
fixture's own documented `_onPrevious` restart rule, not a regression — it stepped back correctly
when I retested under 3 s.

**E10 (stability) — met.** `overflows` count 0 before and after, app responsive throughout, and the
flutter log holds no framework exceptions — only container noise (EGL/DRI3, ALSA has no card) and a
benign SoLoud `fileAlreadyLoaded` from replaying the same fixture.

## Verdict

`partial`, raw 0.8, no intervention penalty. Seven met, two partial, one unmet. The shape of the
result: the model correctly identified the harder case the prompt was pointing at, wrote a genuinely
reasonable visibility probe, kept the existing tests green, and produced honest screenshots — but it
wired the probe into a builder that only reruns on playback and folder changes, so the "conditional"
half of the ask is right only at the instant the folder loads. One judging trap worth recording: my
first attempt at the E2 scroll probe read as "affordance absent" when in fact the 174 s track had
simply ended, so I redid it with `isPlaying` and `songInfo` captured in the same bundle as the
semantics read.

**t6-dot-song-info-hardening-linux** (2) — # T6 — Dot song-info hardening (Linux) · judge-t6

**Outcome: partial · adjusted 0.6 · no interventions.**

## What the candidate actually did

It read the codebase carefully, correctly identified `lib/widgets/heroes/dot_hero.dart` as the place
to fix, and shipped a real change: when `showSongInfo` is on it computes the vertical space the title
block can need (2 lines of artist at `heroSize * textScale` plus 2 lines of song at half that, using
the same 1.18 line-height factor the widget uses) and shrinks the dot's *maximum radius* to whatever
is left above the hero's centre. It also added `ValueKey('dot-circle')` / `ValueKey('dot-song-info')`
so geometry is addressable, and wrote two widget tests asserting the title block's bottom sits above
the dot's top at textScale 1.0 and 1.5. `flutter analyze` was clean and I re-ran its tests myself:
all 7 in `dot_hero_test.dart` pass.

It then spent ~11 minutes of its 30-minute budget hung inside
`flutter test test/widgets/heroes/dot_hero_screenshots_test.dart` — a screenshot-producing widget
test it wrote and later deleted. It abandoned that route, launched the real Linux app at 1385s, ran
`drive.py preflight` and `drive.py inspect`, and was still reading `library_service.dart` looking for
a way to stage long metadata when the deadline guard finished the run at 1625s. **It never captured a
single screenshot** (`.tmp/agent_shots` was empty, and the event stream contains no `shoot` call),
never toggled the option, and never looked at the Dot screen. The prompt asked for screenshots at
both scales; none were delivered, and there is no final write-up.

## What I verified myself

I staged long metadata the way the app actually resolves it: a copy of a fixture opus named
`<82-char artist> - <79-char title>.opus` under `/opt/nothingness/media/longmeta`, played via the
library browser row (`drive.py play` would have given a title-only track with no artist). The app
resolved artist = 82 chars and title = 79 chars. I drove the text-size slider with real X11 input
(XTEST) after wheel-scrolling the settings sheet, and confirmed the row's own value read `150%`
before capturing, and `100%` after setting it back. Two of the restarts were full process relaunches
(kill + fresh `flutter run`), not hot restarts.

- **E1 (met)** — `clearpref '*'` + restart: the hero shows the pulsing dot alone, 230 px across, no
  overlay, settings row reads "show song info / off".
- **E2 (met)** — toggled on, killed the process and relaunched: the overlay is back without
  re-toggling and the row reads "on". Genuine persistence.
- **E3 (met)** — toggled off, relaunched: no overlay, and the dot returns at full size
  (`dot-circle` 173.1×173.1 logical). A real round trip.
- **E4 (partial)** — at 100% with the long metadata the overlay is fully inside the hero: ink ends at
  y=141 of a 230 px band, the artist ellipsizes legibly at 2 lines. Nothing clips and nothing overlaps
  the dot — but only because **the dot isn't there**. The captured tree shows the dot's Container at
  `BoxConstraints(w=0.0, h=0.0)` while the track is playing with a non-zero spectrum. The candidate's
  reserved height (130 logical px at 100%) exceeds the hero's half-height (86.6), so `centerY -
  reserved` goes negative and the radius clamps to 0. The "no overlap" condition holds vacuously.
- **E5 (unmet)** — the one observation this rubric is built around. At 150% the song title's second
  line, "Seventeen Reprise", is **cut mid-glyph at the hero's own bottom bound**: ink runs to y=229
  and stops flat at the 230 px band edge, descenders sliced. The fix only shrank the dot; it never
  constrained the text block, so the clipping the task exists to remove is still there.
- **E6 / E7 (unmet)** — no candidate screenshot exists at either scale, so there is nothing to review
  against my own captures. My own 100% reproduction is clean (modulo the missing dot); my own 150%
  reproduction shows the clip above.
- **E8 (met)** — `drive.py probe` corroborates the text really renders at both scales: hero-artist
  fontSize 30 / 848×70 and hero-song 15 / 713×18 at 100%; 45 / 848×106 and 22.5 / 848×54 at 150%,
  full strings resolved, matching trees.
- **E9 (partial)** — ordinary metadata ("undercover" / "49") renders cleanly at both scales with no
  clipping, but the dot is 0×0 there too. The regression is not limited to long metadata: with the
  option enabled the Dot screen has no dot at any text scale on this window.
- **E10 (met)** — `drive.py overflows` reported 0 before, during and after two toggle cycles, two
  scale changes and switching between long- and short-metadata tracks; the app answered `inspect`
  normally at the end. Only ALSA/JACK container audio noise in the run log, no Flutter exceptions.

## Worth flagging

The candidate's own tests pass while the app clips because they exercise `DotHero` in a 400×400 box.
The real hero band is 960×173 logical — less than half as tall — so the title block fits in the test
and overflows in the app. And `titleRect.bottom <= dotRect.top` is trivially true once the dot is
0×0, so neither test could have caught either problem. Nothing here was mis-scored for lack of
proof: I reproduced every claim live, and the two failures are failures of the change itself, not of
its evidence.

**t7-opus-shuffled-playlist-linux** (3) — # T7 · Opus shuffled playlist (Linux) — judge notes

Run: `t1-t7-gpt-5.4-nano-medium-t7-opus-shuffled-playlist-linux-trial-01-attempt-03`
Model: gpt-5.4-nano, thinking medium. Judge: judge-t7. Interventions: 0.
Outcome: **pass** (band 3, raw 1.0, adjusted 1.0). Candidate settled on its own at 540s of a
1200s budget, 62 tool calls, $0.060.

## What the candidate actually did

It spent the first ~3 minutes reading, not driving: `drive.py`, `dev/agent_service.dart`, the
regression README, and the extension handler table, to find out how `setQueue`, the shuffle toggle
and `next` are actually wired. Then it ran `drive.py preflight`, saw no live VM, launched the Linux
build (`flutter pub get` then `flutter run` under `DRIVE_TARGET=linux`), waited out the ~3-minute
SoLoud/CMake build, and confirmed `live VM=yes` before touching anything.

The working sequence was short and correct:

1. `drive.py call ext.nothingness.setQueue paths="$(ls -1 /opt/nothingness/media/*.opus | sort | paste -sd, -)" startIndex=0` → `{"queued": 10}`. It built the path list from the mount rather than typing names, so there was no chance of a typo or an eleventh file.
2. `getPlaybackState` → `queueLength 10`, the ten fixtures in sorted order each once, `isNotFound false` on all, `isPlaying true`, `currentIndex 0` on `01-undercover-49.opus` at position 5.3s. Note that `setQueue` starts playback itself, which is why the candidate never needed a separate `play` call — "play valid supplied media" was satisfied by real audio actually running (`spectrumNonZero: true`).
3. `drive.py settings open`, then `drive.py tap void-settings-status-shuffle` → `{"tapped": ..., "mode": "descendant-callback"}`. The follow-up `getPlaybackState` read `shuffle: true` with the queue genuinely re-permuted and the current track carried to its new index 6, still playing `01-undercover-49.opus`.
4. Captured "before" (`01-undercover-49.opus`), ran `drive.py next` **once**, then polled `getPlaybackState` until the path changed — it had already changed on the first poll to `09-undercover-46.opus`. A final read confirmed `currentIndex 7`, `isPlaying true`, queue still the ten fixtures.
5. It then re-asserted the whole thing in an inline Python check over the live state (queue length 10, 10 unique, set equality against `glob('/opt/nothingness/media/*.opus')`, before/after both in-set and distinct) → `queue_ok`, `transition_ok`, and wrote a replay script recording the exact sequence.

Exactly one transition happened in the entire session: one `next`, zero `prev`, one `setQueue`, zero
`play`. Nothing had to be walked back.

## What I verified with my own hands

The candidate left the app running, so I drove its own live session rather than a replacement — my
first capture found it still playing `09-undercover-46.opus` at 249s of 359s, i.e. the very track its
`next` had selected, continuing uninterrupted (`verification-c21fef32f7ff44c3a89d973333c3cfc6`).

- **E1 met.** I re-ran `setQueue` with the ten mounted paths myself and read the runtime lens: `queueLength 10`, the ten fixture paths each exactly once, nothing foreign, `isNotFound false` throughout (`verification-7761904a3cc849b2a8c4036a86e75b3c`).
- **E2 met.** I did not take the flag on trust. With the sheet open I tapped `void-settings-status-shuffle` and watched `shuffle` go **true → false** (`verification-f27d4b971aa34264966af7032258a1f2`), then tapped the same row again and watched it go **false → true**, with the queue re-permuted into a different order than the candidate's while the current track was preserved (`verification-49fd97a169b4425a968a0b98bda0e83a`). The on-screen control is what moves the flag.
- **E3 met.** I closed the sheet, ran `drive.py play /opt/nothingness/media/05-undercover-53.opus`, and captured `isPlaying true`, current path in-set, `isNotFound false`, position advancing (`verification-d24a8e232bec449e8e6b53800ac3b030`).
- **E4 met.** One `drive.py next` moved current from `05-undercover-53.opus` (index 5) to `06-undercover-54.opus` (index 6), still playing, still `isNotFound false`, both endpoints in the fixture set (`verification-714fffddd86e408aa6d13a7875db0943`). A real transition, not a no-op.
- **E5 met.** I scanned the entire session record for audio paths. Every distinct `"path"` value in every playback-state dump is one of the ten fixtures. The only non-fixture audio *filenames* anywhere in the transcript (`t1_a440_2s.wav`, `long_10s.wav`, `/absolute/path/foo.mp3`) come from documentation and existing replay scripts the candidate read; none was ever queued or made current.
- **E6 met.** Each claim in the final report maps to a concrete read: the queue claim to the post-`setQueue` dump plus its own set-equality assertion; `shuffle: true` to the post-tap dump; the before/after paths to the two reads bracketing the single `next`; the replay-script claim to the write itself. No claim rests on memory.
- **E7 met.** `candidate.diff` is 0 bytes and the inspection's git lens shows an empty `diff_stat` — this run did not even produce the tolerated `GeneratedPluginRegistrant.swift` regeneration. The one workspace addition is a single untracked file, `tool/regression/opus_fixtures_shuffle_next.txt`, a `drive.py replay` script that documents the sequence; it changes no app code, no setting, and no runtime behaviour, and my re-derivation of queue/shuffle/play/next behaved exactly like a stock build.
- **E8 met.** Nothing broke that needed recovering: `overflows` count 0 in every capture, and the run log (270 lines) has no lost-connection, `EXCEPTION CAUGHT` or segfault traces. Three tool calls did fail — two `grep` invocations that matched nothing (it used `|` alternation without `-E`), and one `python3 - <<'PY'` heredoc that swallowed stdin so `json.load(sys.stdin)` got the script instead of the piped state. The candidate diagnosed that last one correctly, re-ran it by writing state to `/tmp/playback_state.json` first, and got its assertions to pass. It fixed its own tooling rather than reporting over the failure.

## Worth noting

- `playTrackByPath` (what `drive.py play` uses) sets the current track without syncing `currentIndex` to that track's queue position: after I played `05-undercover-53.opus` (queue position 3), `currentIndex` still read 5, so my `next` advanced to index 6 rather than index 4. Pre-existing fixture behaviour, unrelated to the candidate, and it does not affect any expectation here — the transition was still genuine and in-set.
- The candidate's "after" detection loop assigned to the shell variable `PATH`, which would have broken subsequent lookups inside that loop had it needed a second iteration. It matched on the first poll, so nothing came of it.
- This was attempt 03 of trial 1; the earlier attempts are not part of this scoring.

## Interventions

None — fully unassisted.

## What surprised us

- On t1 the model's methodology was better than its reading. It worked out on its own, from
  `dev/agent_service.dart`, that `play` maps to `playTrackByPath` and that a real queue needs
  `setQueue` — the exact trap the rubric flags for E3 — and it deliberately structured its replay
  script to inspect after *every* transport call. It then failed the one expectation that structure
  existed to catch, because it never looked at the output the structure produced.
- On t6 the model's own tests passed and were structurally incapable of failing. They exercise
  `DotHero` in a 400×400 box while the real hero band is 960×173 logical, so the long title fits in
  the test and clips in the app; and the second assertion, `titleRect.bottom <= dotRect.top`, became
  trivially true the moment its fix collapsed the dot to 0×0. Two real defects, two green tests
  written specifically to catch them.
- The one `pass` is the task where the model drove the least. On t7 it spent its first ~3 minutes
  reading `drive.py` and the extension table before touching anything, then ran the shortest sequence
  of the campaign — one `setQueue` built from `ls` rather than typed names, one shuffle tap, one
  `next` — for 62 tool calls and $0.060, the second-cheapest run in the set. Its workspace diff was
  0 bytes. Where it read first and acted narrowly it scored full marks; where it acted first and
  verified last it lost expectations it had already satisfied in code.
