# T2 · Cassette settings placement (Linux) — judge notes

**Run:** t1-t7-gpt-5.4-nano-low-t2-settings-placement-linux-run-bdeeceb6686e
**Model:** azure-openai-responses / gpt-5.4-nano / thinking=low
**Outcome:** pass · score 3 (raw 1.0, penalty 0.0) · valid · 0 interventions · candidate settled at awaiting_judge (timed_out=false)

## What the candidate did
It made a single, surgical edit to `lib/widgets/void_settings_sheet.dart`. For `CassetteScreenConfig` it splices `displayRows(cfg)` — the cassette variant, text-size and haptics rows — in immediately after the `void-settings-screen` selector, and it gates the original DISPLAY-cluster `...displayRows(cfg)` (and the visualizer/SOUND cluster) with `cfg is! CassetteScreenConfig` so cassette's rows are no longer duplicated or buried lower down. `flutter analyze` was clean; it launched the Linux build under Xvfb, drove it, and saved its own screenshot. Only that one file is modified; nothing untracked.

## What I verified by driving the live app myself
- **E1 (met):** With Cassette selected, `getSemantics` shows `screen / cassette` at indexInParent 5 (rect y 231–276) immediately followed by `variant / Tape · Mono` at indexInParent 6 (rect y 276–321). The y-ranges abut with no group header or gap. The screenshot shows the same order.
- **E2 (met):** Tapping `void-settings-screen` on-screen six times cycled spectrum→polo→dot→void→cassette→spectrum (full cycle + wrap). Direct `drive.py screen <name>` calls for polo/dot/void/spectrum were each reflected in the row's displayed value. Both directions wired.
- **E3 (met):** On-screen taps of `void-settings-cassette-variant` advanced Tape·Mono→Tape·Amber→Tape·Colour→Minimal; direct `cassettevariant 2`/`1` calls moved it too (row showed Tape·Amber then Tape·Mono). Displayed label tracks the underlying variant both ways.
- **E4 (met):** For spectrum/polo/dot/void the row right after `screen` is the general `immersive` toggle — never a cassette control. Spectrum's own `bar count` cycled bars24→bars8→bars12 on-screen. The cassette-variant row is injected under `screen` only on Cassette.
- **E5 (met):** Captured screenshot legibly shows the Settings sheet with `screen cassette` directly above `variant Tape · Mono`, both rows fully in frame, with text size 100% and haptics on below.
- **E6 (met):** The semantics dump and `getSettings` (screenType=cassette) independently corroborate the row order and active screen, so the claim doesn't rest on the image alone.
- **E7 (met):** Unrelated rows kept their pairwise order (MODE, operating mode, LOOK, theme, theme-variant, screen, immersive, transport, browser, full screen, ui scale, LIBRARY…, DISPLAY, ABOUT); none added/removed/renamed. On-screen taps of `immersive` (on→off), `transport` (top→off) and `operating mode` (background→own) each changed their displayed value.
- **E8 (met):** `overflows` reported count 0 both before and after repeatedly opening/closing settings and switching all five screens; no EXCEPTION/RenderFlex entries in the run log; final `inspect` showed the app alive and responsive.

## Evidence
- `verification-0ac23dd710e84f0d9b3f4529e664df99` — cassette settings open (semantics + screenshot + settings): E1, E5, E6, E7.
- `verification-580ba03679e54e66a8b01af3a02dd9d4` — spectrum screen (row-after-screen = immersive, bar count changed): E2, E4.
- `verification-23c16149eafb4575a5a7a37fbbc35d2d` — cassette variant state: E3.
- `verification-f2c47efe942e4b50b621ab497b67a335` — final runtime lens, overflows 0: E8.

No blockers. The implementation is correct and observably behaves as the prompt requires.
