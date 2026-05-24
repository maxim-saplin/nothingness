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

## B-032 (minor): Browser needs a drag-down-to-close affordance

**Symptom**: With swipe-up browser presentation, the browser opens via
upward swipe but the only documented close gesture is Android Back,
which is unintuitive. The crumb's `×` (for search) and the back button
are both available, but neither is discoverable from the browser open
state. Users learning the app expect the browser to close by pulling it
back DOWN, the way it opened.

**Desired**:
1. Add a small drag handle at the top of the open browser — a thin
   horizontal pill in `fgTertiary`, centered, ~32 px wide × 4 px tall,
   placed above the crumb. Telegraphs the drag-down gesture.
2. Vertical-drag-DOWN on the non-scrolling regions of the browser
   closes it. Non-scrolling regions include:
   - the drag handle itself,
   - the crumb area (path readout + glyphs),
   - the search bar when active,
   - any gap between crumb and the start of the scrollable list.
3. Threshold: same pattern as B-027's velocity escape — fire on EITHER
   distance > ~60 dp OR velocity > 300 dp/s. Use Flutter's
   `onVerticalDragEnd` velocity sign for direction.
4. Back button still closes (don't remove that path — `_onPopInvoked` in
   `void_screen.dart` covers it per B-007).
5. The browser's scrollable list MUST NOT be affected — vertical drags
   inside the list keep scrolling the list, not closing the browser.

**Notes**: `lib/widgets/void_browser.dart` for the drag handle + crumb
region; `lib/screens/void_screen.dart` for the swipe-up presentation
state and the close path the gesture should call. Don't conflict with
the swipe-up open gesture (it lives on the home screen, not the open
browser).

**Area**: chrome / browser
