# t2-settings-placement-linux — judge notes

**Run:** t1-t7-gpt-5.4-nano-medium-t2-settings-placement-linux-run-8a43a340073a
**Model:** azure-openai-responses / gpt-5.4-nano / medium (identity verified)
**Outcome:** pass (score 3, raw 1.0, no interventions)

## What the candidate did
It edited `lib/widgets/void_settings_sheet.dart` only: inserted `if (cfg is CassetteScreenConfig) ...displayRows(cfg)` immediately after the `_Cycle('void-settings-screen', ...)` row, and guarded the original DISPLAY-section copy with `if (cfg is! CassetteScreenConfig) ...displayRows(cfg)` so the cassette rows are not duplicated. It added a widget test, ran `flutter analyze` (clean) and the sheet test (green), launched the Linux build, and captured screenshots. The diff is scoped to the cassette branch and the row position; no handlers or ids were changed.

## What I verified live (driving the running Linux build myself)
- **E1 (met, required):** With Cassette selected, `getSemantics` shows the `screen / cassette` row (indexInParent 5, rect y 231–276) immediately followed by the cassette `variant / Tape · Mono` row (indexInParent 6, rect y 276–321). Abutting y-ranges, no group header or gap. The captured screenshot shows the same: "screen cassette" directly above "variant Tape · Mono".
- **E2 (met, required):** Tapping the on-screen `screen` row five times cycled spectrum → polo → dot → void → cassette, all the way back to the start. Direct `drive.py screen <name>` calls were each reflected in the row's displayed value. Both directions wired.
- **E3 (met, required):** On-screen taps of the variant row advanced Minimal → Tape · Mono → Tape · Amber; direct `cassettevariant <n>` calls also moved the variant and the row's displayed label tracked each one.
- **E4 (met, required):** For spectrum/polo/dot/void the row directly after `screen` is the general `immersive` toggle — never a cassette control. Spectrum's own `bar style` cycled segmented → solid → glow and dot's `show song info` toggled off → on → off when tapped on-screen, so non-cassette screens' own controls still work.
- **E5 (met, required):** A genuine session screenshot (x11 capture bundled by judge-verify) shows the Settings sheet with Cassette active and both the `screen` and `variant` rows in frame and legible.
- **E6 (met):** The semantics dump plus `getSettings` (screenType=cassette) corroborate the screenshot's row order and active screen.
- **E7 (met):** Unrelated rows kept their prior relative order (MODE, operating mode, LOOK, theme, theme-variant, screen, immersive, transport, browser, full screen, ui scale, LIBRARY…); `transport` cycled bottom → top and `smart folders` toggled and restored when tapped.
- **E8 (met):** `overflows` reported 0 before and after repeatedly opening/closing settings and switching screens; the app stayed live and responsive (final `inspect`: alive, overflows 0).

## Notes
Only the settings sheet + its test were touched; no crashes or new errors surfaced. All four prompt clauses (placement, screen control preserved, variant control preserved, screenshot) hold, and the change is correctly scoped to the Cassette case.
