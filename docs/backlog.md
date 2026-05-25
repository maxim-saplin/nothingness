# Backlog

Single-file issue tracker for in-flight UX/bug work on `main`. Continues the
`B-NNN` numbering from the closed `ui-revamp` arc (last id was B-010).

## Conventions

- One H2 per issue: `## B-0NN (severity): title` — severity is `minor` /
  `major` / `blocker`.
- Body uses these fields (omit any that don't apply):
  - **Symptom** — what the user observes.
  - **Repro** — exact sequence (driver commands welcome) plus the runtime
    evidence we collected (numbers, screenshots, logcat snips).
  - **Desired** — what we want it to do.
  - **Notes** — code pointers (`path/to/file.dart:line`), constraints,
    cross-refs (`see B-0NN`).
  - **Area** — short tag (`chrome`, `search`, `transport`, `permissions`,
    `browser`, `heroes`, `settings`).
- When an item is fixed, **move the entry to `backlog_done.md`** and append
  a `**Closed**: YYYY-MM-DD — one-line summary of the resolution (commit
  hash if useful)` line at the bottom of the moved entry. Keep the trail —
  it's cheap to read and pays off when a regression looks familiar.
- New ids are assigned monotonically across both files. Don't reuse closed
  ids; check `backlog_done.md` too when picking the next id.

---

## B-034 (minor): SOUND group shows visualizer config on screens that don't have a visualizer

**Symptom**: Opening settings on the Dot or Void screen still shows the
SOUND group's bar count / bar style / decay speed / visualizer color
rows — even though neither Dot nor Void renders the visualizer. These
controls only affect Spectrum and Polo (the two heroes that paint the
visualizer). Showing them on Dot/Void is confusing — toggling them does
nothing visible on the active screen.

**Desired**: Same contract as B-018's `hostsChromeTransport`. Add a
`bool get usesVisualizer` to `ScreenConfig` (default `true` so
new heroes opt in by default). Override to `false` on `DotScreenConfig`
and `VoidScreenConfig`. The settings sheet's SOUND group hides the four
visualizer-only rows (`bar count`, `bar style`, `decay speed`,
`visualizer color`) when `activeConfig.usesVisualizer == false`. The
`eq` placeholder row stays since it's a generic audio control. The
LIBRARY group (filename fallback, smart folders) is unaffected.

**Notes**: `lib/models/screen_config.dart` for the new getter;
`lib/widgets/void_settings_sheet.dart` around the SOUND group (line
~510) for the gate. Keep the DISPLAY group's existing per-screen gating
exactly as-is.

**Area**: settings

---

## B-035 (minor): Song info text size is only configurable on Spectrum

**Symptom**: Spectrum has a `text size` slider under DISPLAY that scales
the title + parent-folder typography. Dot's optional song-info overlay
(B-020) and Void's title display have no such control — they always
render at the base hero typography size. Real-device feedback: the size
that looks right on Spectrum is wrong on the other heroes; users want
to tune each.

**Desired**:
1. Add a `double textScale` field (default `1.0`, range `0.5..1.5`,
   same as Spectrum's) to `DotScreenConfig` and `VoidScreenConfig`.
   Persist via the existing per-screen `saveScreenConfig` path
   (B-028 made the keys per-screen so this is automatic).
2. Apply the scale at render: `dot_hero.dart` (only when
   `showSongInfo == true`) and `void_hero.dart` multiply
   `typography.heroSize` and `typography.hintSize` by `cfg.textScale`.
3. Add a `text size` slider row to `_buildDotDisplayRows` and to the
   Void section of the DISPLAY group (`type == ScreenType.void_`,
   replacing the current `no options` placeholder). Same UI as
   Spectrum's slider — 50% to 150%, 10 divisions.

**Notes**: `lib/models/screen_config.dart`,
`lib/widgets/heroes/dot_hero.dart`, `lib/widgets/heroes/void_hero.dart`,
`lib/widgets/void_settings_sheet.dart`. Polo stays untouched — its LCD
font is bespoke.

**Area**: settings / heroes / dot / void

