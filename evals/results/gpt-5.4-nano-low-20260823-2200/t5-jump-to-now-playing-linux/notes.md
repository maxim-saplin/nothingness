# T5 — Jump to now playing (Linux) — judge notes

**Run:** t1-t7-gpt-5.4-nano-low-t5-jump-to-now-playing-linux-run-775976d2eb65
**Model:** azure-openai-responses / gpt-5.4-nano / low

## What the candidate did
It edited `lib/widgets/void_browser.dart` and `lib/screens/void_screen.dart` to extend the
existing cross-folder "jump to now playing" glyph so it also shows when the playing track's row is
scrolled out of view within the already-open folder. It added
`VoidBrowserController.isTrackInViewport(path)` (row render box vs viewport), wired an `onUserScroll`
callback, and gated the glyph on `outsideFolder || outsideViewport`, hiding it entirely when nothing
plays. `flutter analyze` passed. It never got a live app running — every `flutter run` failed with
"could not find Dart VM service URI" — so it produced no before/after screenshots and made no live
observations. I launched and drove the built app myself to settle every expectation.

## Per-expectation findings (verified live by me)
- **E1 (met):** From the mount root with a media track playing, the glyph was present; tapping it
  navigated to /opt/nothingness/media and left the playing row (.44) fully visible at the top.
- **E2 (unmet):** The core hardening case. With media open and row 46 scrolled off-screen, the glyph
  appears and the folder path stays unchanged, but a single activation is inert — 5/5 clean single
  taps left the row off-screen. Only repeated taps eventually scroll it into view. Activation does
  not reliably reveal the row, which is the whole ask.
- **E3 (unmet):** With the playing row (46) fully unclipped and visible in the correct folder, an
  active jump glyph stayed exposed across 4/4 steady samples — it behaves as always-on when a track
  plays in the folder, not conditional on visibility.
- **E4 (met):** With nothing playing (isPlaying false, songInfo null), no jump action appeared in
  either the media folder or the root folder.
- **E5 (met):** In the active state the glyph node carries the semantic label
  "jump to now-playing folder" with the button flag — a genuine accessible affordance.
- **E6 (unmet):** No candidate before-screenshot exists (no live VM, no shoot, no PNGs in workspace).
- **E7 (unmet):** No candidate after-screenshot exists, for the same reason; the candidate said so.
- **E8 (unmet):** The write-up's behavioral claims are code-derived, not backed by any session
  observation — the app never ran for the candidate.
- **E9 (met):** On-screen folder-row and up-row taps navigate correctly; pause/resume and transport
  controls behave normally on a fresh track.
- **E10 (unmet):** Playing a track in the browsed folder throws two exceptions —
  `setState()/markNeedsBuild() called during build` (void_screen.dart:626, ValueNotifier set inside
  the Selector builder) and `Scrollable.of()` with no Scrollable ancestor (isTrackInViewport). When
  the row is built the crumb is replaced by a red error widget. Both are in the run log.

## Bottom line
The easy cross-folder path (E1) works and the affordance is accessible (E5) and correctly absent when
idle (E4), but the load-bearing same-folder hardening is broken: the visibility check throws
exceptions and is unreliable, so the action is effectively always-on (E3 fails) and a single
activation does not scroll an off-screen row into view (E2 fails), plus it crashes the crumb (E10).
No screenshots were produced (E6/E7) and no runtime claims were observed by the candidate (E8).
