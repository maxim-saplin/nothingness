# T3 — Cassette settings placement + `color scheme` rename (Linux)

**Outcome: pass (3/3).** gpt-5.4-nano (low) edited only `lib/widgets/void_settings_sheet.dart`:
it removed the cassette variant `_Cycle` from the per-screen `displayRows(CassetteScreenConfig)`
list and re-inserted it, gated on `if (cfg is CassetteScreenConfig)`, immediately after the
`void-settings-screen` row, renaming its label from `variant` to `color scheme`. `flutter analyze`
was clean and it launched the Linux build and captured a screenshot. I verified everything below by
driving that same live build myself with `drive.py` / `getSemantics`.

- **E1 (met):** With screen=cassette the semantics tree shows `screen / cassette` at indexInParent 5
  (rect y 231–276) immediately followed by `color scheme / Tape · Mono` at indexInParent 6 (rect
  y 276–321). Rects abut, nothing sits between them. Adjacency also held on a second visit after
  switching away to spectrum and back.
- **E2 (met):** The row's label line reads exactly `color scheme` — lowercase, same register as
  `theme`/`variant`/`transport`. Value line is the variant (`Tape · Mono`). Exactly one such row;
  scanning the whole sheet found no leftover cassette `variant` row.
- **E3 (met):** Tapping `void-settings-screen` on-screen cycled its value
  spectrum→polo→dot→void→cassette→spectrum (full wrap); direct `drive.py screen <name>` calls also
  updated the row (spectrum capture shows `screen / spectrum`).
- **E4 (met):** Tapping the `color scheme` row cycled its value
  Minimal→Tape·Mono→Tape·Amber→Tape·Colour→Minimal; a direct `drive.py cassettevariant 2` call moved
  it to `Tape · Amber`. The control is still wired to its handler in both directions.
- **E5 (met):** For spectrum, polo, dot and void the row after `screen` is `immersive`, never a
  cassette control, and no `color scheme` label appears anywhere. Each screen's own controls still
  work on-screen (spectrum bar count 24→8, dot show-song-info off→on when tapped).
- **E6 (met):** I opened the screenshot lens PNG — it genuinely shows the settings sheet with
  screen=cassette and `color scheme / Tape · Mono` legibly directly beneath `screen / cassette`.
- **E7 (met):** The semantics + `getSettings` dumps taken while cassette is selected corroborate the
  screenshot on order, exact label, and current variant value.
- **E8 (met):** The full sheet order (MODE / LOOK / LIBRARY / SOUND / DISPLAY groups) is otherwise
  unchanged — no unrelated row added, removed, renamed, or reordered; sampled unrelated rows still
  respond to taps.
- **E9 (met):** `drive.py overflows` returned count 0 after all the exercising and the runtime lens
  shows the app still live and responsive; no crashes or new errors.

No interventions. Candidate cost ≈ $0.0216.
