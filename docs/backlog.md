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

## B-030 (major): No press feedback on most tappable surfaces

**Symptom**: On a real device (not the emulator), tapping a track row in
the browser produces no visible feedback for ~500 ms — then the
now-playing row inverse-color highlight catches up when playback
finally advances. The user reads the half-second of nothing as "the app
ignored my tap". Same for settings rows, search results, help-screen
rows, the crumb glyphs (search-close, jump-to-now-playing). The
MediaButton has a press dip from B-012 but at 80 ms / opacity 0.55 it
is below the perception threshold on real hardware, especially for the
primary play button (the dip is on the whole circle but the strong
accent backdrop doesn't change).

**Root cause**: B-012's scope was hero + transport buttons. Most
tappable surfaces never got touch-down state. `_VoidRow`
(`lib/widgets/void_browser.dart:704-`) is a plain `GestureDetector`
with `onTap` only. Settings sheet rows use bare `GestureDetector` too.
The B-015 "now-playing row highlight" is a *consequence* of playback
state, not a *response* to the user's tap.

**Desired**:
1. A single `PressFeedback` widget that wraps any child and reflects
   touch-down/up/cancel as a perceptible opacity (or other monochrome)
   change. Calibration tuned for real-hardware visibility:
   - Pressed opacity: 0.4 (was 0.55 for MediaButton — too subtle).
   - Fade-in: 120 ms with `Curves.easeOut`.
   - Fade-out (release): 200 ms with `Curves.easeOut` so the dip is
     visible even on very brief taps.
2. Apply `PressFeedback` to every tappable surface:
   - `_VoidRow` in `void_browser.dart` (file rows, folder rows, search
     results, parent row).
   - `_toggleRow` and tappable static rows in `void_settings_sheet.dart`.
   - Help-screen tappable rows in `help_screen.dart`.
   - Crumb glyphs: search-close (`void-search-close`),
     jump-to-now-playing (`void-crumb-jump-to-playing`).
   - Tap-to-grant gate.
3. Re-tune `MediaButton` to the same calibration constants.
4. Bump `HeroFeedbackSurface` tap-ring visibility: `fgSecondary` at
   1.5× current alpha and 2× stroke width so it's actually visible on
   a hand-held device.

**Tests**:
- Widget test for `PressFeedback`: opacity transitions correctly on
  `onTapDown`/`onTapUp`/`onTapCancel`; survives no-op rebuilds.
- Update `_VoidRow` tests (and add coverage if missing) to assert the
  press path lives in the row.
- Re-snap `MediaButton` test to the new pressed-opacity constant.

**Notes**: This is the user-facing followup to B-012 — same idea,
comprehensive scope. The QA prompt template should also be updated to
require the implementer to enumerate every `GestureDetector`/`InkWell`
in the diff context and confirm each has a visible feedback surface.

**Area**: chrome / browser / settings / heroes / transport
