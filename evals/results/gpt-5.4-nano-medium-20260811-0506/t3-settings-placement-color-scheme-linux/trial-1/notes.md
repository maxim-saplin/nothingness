# T3 — cassette settings placement + `color scheme` rename (Linux)

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
