# T3 — Cassette settings placement + `color scheme` rename (Linux)

**Outcome: pass (3/3). All 9 expectations met, verified by driving the live Linux build myself.**

## What the candidate did
A single, surgical edit to `lib/widgets/void_settings_sheet.dart` (7 insertions, 2 deletions):
- The cassette `displayRows` block (variant cycle + text size + haptics) is now injected
  `if (cfg is CassetteScreenConfig) ...displayRows(cfg)` immediately after the `screen` row.
- The later `...displayRows(cfg)` in the DISPLAY section is guarded to `if (cfg is! CassetteScreenConfig)`,
  so cassette controls render in exactly one place.
- The cassette variant `_Cycle` label was renamed from `'variant'` to exactly `'color scheme'`.

The candidate launched the app on Linux (Xvfb), cycled to cassette, opened settings and shot a
screenshot before settling. 0 interventions; unassisted.

## Per-expectation findings (all verified live via drive.py getSemantics/tap + judge-verify)
- **E1 (met):** On cassette the rows read `screen / cassette` (idx5, y231-276) then
  `color scheme / Tape · Mono` (idx6, y276-321) — abutting, nothing between.
- **E2 (met):** Label is exactly `color scheme` (lowercase), value `Tape · Mono`, exactly one such
  row. The only remaining `variant` row is the unrelated theme-variant control (value `system`).
- **E3 (met):** Tapping `void-settings-screen` cycled dot→void→cassette→spectrum; direct `screen`
  calls for all five types each landed with the row's displayed value tracking the active screen.
- **E4 (met):** Tapping the `color scheme` row cycled Tape·Mono→Tape·Amber→Tape·Colour→Minimal, and
  direct `cassettevariant 0/1/2` calls moved it too; the row's displayed value tracked every change.
- **E5 (met):** `color scheme` appears after `screen` only for cassette. For spectrum/polo/dot/void
  the row after `screen` is `immersive`, with no stray `color scheme` anywhere (spectrum's own control
  stays `visualizer color`). Their controls work on-screen: bar-count 24→8, dot show-song-info off→on.
- **E6 (met):** Genuine verify screenshot shows the sheet with `screen: cassette` and
  `color scheme: Tape · Mono` directly beneath, both legible.
- **E7 (met):** The semantics/tree dump taken on cassette corroborates order, exact label, and value.
- **E8 (met):** All unrelated rows keep prior relative order; none added/removed/renamed. The cassette
  `text size`/`haptics` rows moved up together with the variant control (as the prompt intends); the
  DISPLAY group still carries its debug-layout toggle (not left empty). Tapping immersive off→on works.
- **E9 (met):** After opening/closing settings, switching every screen, and repeatedly cycling color
  scheme, the runtime lens shows overflows count 0 and the app answered normally throughout.
