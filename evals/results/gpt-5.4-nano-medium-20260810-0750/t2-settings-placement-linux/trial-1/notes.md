# T2 · Cassette settings placement (Linux) — judge notes

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
