# Judge notes — T3 · Cassette settings placement + color-scheme rename (Linux)

**Run:** `t1-t7-gpt-5.4-nano-medium-t3-settings-placement-color-scheme-linux-run-885b75439fc8`
**Model:** azure-openai-responses / gpt-5.4-nano / medium
**Outcome:** pass (score 3, raw 1.0, no interventions)

## What the candidate did
It made a single, surgical change to `lib/widgets/void_settings_sheet.dart` (4 insertions, 2 deletions):
1. Renamed the cassette variant `_Cycle` row's label from `'variant'` to `'color scheme'` — the widget key
   `void-settings-cassette-variant` and its cycle handler are untouched.
2. Added `final inlineCassette = Platform.isLinux && cfg is CassetteScreenConfig;` and inserted
   `if (inlineCassette) ...displayRows(cfg)` immediately after the `screen` row, while guarding the original
   bottom placement with `if (!inlineCassette) ...displayRows(cfg)`. So on Linux with Cassette selected, the
   cassette controls render right under `screen`; everywhere else the layout is unchanged.
It built and launched the Linux app, set screen=cassette, opened settings, and captured screenshots. `flutter analyze` was clean.

## What I verified myself (live, driving the running Linux build)
- **E1 (met):** With Cassette selected, `getSemantics` shows `screen`/cassette at indexInParent 5 (rect y231–276)
  immediately followed by `color scheme`/Tape·Mono at indexInParent 6 (rect y276–321) — abutting rects, nothing between.
- **E2 (met):** The row label reads exactly `color scheme`, lowercase like every other label. Exactly one such row;
  no leftover cassette `variant` row (the `variant`/system row above is the unrelated theme variant control).
- **E3 (met):** Tapping the `screen` row on-screen cycles cassette→spectrum→polo→dot→void→cassette (full cycle back
  to start), the row value tracking each step; direct `screen <name>` calls also land and match `getSettings`.
- **E4 (met):** Tapping the `color scheme` row cycles Minimal→Tape·Mono→Tape·Amber→Tape·Colour→Minimal; direct
  `cassettevariant 1/2/3` calls move the variant and the row's displayed value tracks (captured at Tape·Amber). Both
  activation paths work — the rename did not disconnect the handler.
- **E5 (met):** For spectrum/polo/dot/void the semantics contain zero `color scheme` labels and the row after `screen`
  is that screen's own generic control, never a cassette one. Their own controls still work (spectrum bar-count 8→12,
  dot show-song-info off→on).
- **E6 (met):** Genuine screenshot (verification bundle) of the settings sheet with Cassette selected legibly shows
  `screen: cassette` directly above `color scheme: Tape · Mono`.
- **E7 (met):** Semantics + widget tree + `getSettings` dumps taken while Cassette selected corroborate the order,
  exact label, and variant value — the claim doesn't rest on the image alone.
- **E8 (met):** All other rows keep their prior relative order; unrelated controls still respond (transport bottom→top,
  immersive off→on).
- **E9 (met):** Overflows count 0 before and after opening/closing settings, switching all screens, and cycling the
  color scheme control repeatedly; `inspect` answered normally throughout — no crashes or new errors.

## Bottom line
A correct, minimal, Linux-scoped implementation. Every required and secondary expectation is met on live evidence.
