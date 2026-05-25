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

## B-033 (major): Swipe-up browser pops without animation; jump glyph + drag handle invisible on real hardware

**Symptom**: Three concrete user-reported failures on real-device install
after B-030..B-032 landed:

1. **Browser open/close pops with no animation.** Settings sheet has a
   nice slide-in; the swipe-up browser just appears/disappears
   atomically. The Positioned widget that holds the browser is
   conditionally rendered (`if (!browserCollapsed)`); there's no
   `AnimatedPositioned`, `AnimatedSlide`, or transition tween on the
   `_browserExpanded` flip. Verified in `lib/screens/void_screen.dart`
   ~line 487.
2. **Jump-to-now-playing glyph hard to see.** `_buildJumpGlyph` renders
   `⊙` at `typography.crumbSize` (~13 px) in `palette.fgSecondary`
   (mid-gray). A tiny low-contrast character in a 44×44 hit target.
   "Most of the time I don't see the icon."
3. **Drag handle invisible.** B-032 spec'd 32×4 px in `fgTertiary` —
   that's a thin dark pill on a dark background. Combined with the
   missing slide animation (point 1), the user has no visual cue that
   the browser can be pulled down to close.

**Desired**:
1. **Animate the browser presentation**: replace the conditional
   `Positioned(...)` with an `AnimatedPositioned` (or wrap in
   `AnimatedSlide`) that tweens the browser's top/bottom edges over
   ~280 ms with `Curves.easeOutCubic`. Same direction in both modes —
   slides up from the bottom of the screen on expand, slides back down
   on collapse. The hero's height interpolates in lockstep so there's
   no layout pop. Match the feel of the settings sheet open animation
   (whatever its duration/curve is — find it and reuse).
2. **Bump glyph visibility**: render the `⊙` at `typography.rowSize`
   (matches search-input bump from B-013) in `palette.fgPrimary` (full
   contrast) — same hit target. Optionally add a subtle background
   circle in `palette.fgPrimary.withAlpha(40)` for further visibility.
3. **Bump drag handle**: 40 px wide × 6 px tall, `palette.fgSecondary`
   (mid contrast, was fgTertiary), top/bottom margin 10 px. Sits
   centered above the crumb. Visible even on darkest backgrounds.

**Validation note**: the user's previous build may have predated B-031
and B-032 — confirm via reinstall before judging. But the three fixes
above are correctness regardless of which build they're on.

**Area**: chrome / browser / heroes
