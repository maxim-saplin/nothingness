# T5 — Jump to now playing (Linux) — judge notes

**Run:** `t1-t7-gpt-5.4-nano-medium-t5-jump-to-now-playing-linux-run-a12a4180da0d`
**Model:** gpt-5.4-nano / medium · **Outcome:** partial (score 2) · raw 0.9, capped by required E3 unmet · no interventions.

## What the candidate did
One-file change in `lib/screens/void_screen.dart`. It reuses the existing `void-crumb-jump-to-playing` ⊙ glyph in the browser breadcrumb and changes its show-condition. Previously the glyph showed only when the playing track lived in a *different* folder (`divergent`). The candidate added a Linux branch: `showJumpGlyph = isLinux ? playingExists : resolveJumpGlyphVisible(divergent)`. It also broadened the semantics label to "jump to now-playing track in browser". `jumpToNowPlaying` loads the parent folder only if `currentPath != parent`, then calls `browserController.scrollToTrack(playingPath)`. Analyzer clean; it hot-reloaded and captured before/after screenshots.

## Per-expectation (verified live by me)
- **E1 (met):** Playing 07-undercover-44 while browsing the *different* parent `/opt/nothingness`, the glyph was present; tapping it navigated into `/opt/nothingness/media` and left the row on screen (idx10, y4–45 in viewport 0–332).
- **E2 (met):** In `/opt/nothingness/media` with track 44's row scrolled off the top (reverse ListView, scrollPosition 0), the glyph was present; tapping scrolled the list to scrollPosition 127, bringing row 44 fully into view, and `currentPath` stayed `/opt/nothingness/media` — it scrolled rather than re-navigated. This is the core hardening ask and it works.
- **E3 (UNMET, required — the cap):** The action is gated only on playback, not visibility. On Linux the code is literally `showJumpGlyph = playingExists`. With track 44's row fully visible and unclipped (y4–45 inside the 0–332 viewport, confirmed in semantics and screenshot), the jump action was *still* exposed as an active tappable button (SemanticsNode#9: actions tap/longPress, isButton, jump label). That is exactly the "always-on" implementation the rubric falsifies.
- **E4 (met):** Idle (isPlaying false, songInfo null): no jump action in tree or semantics at `/opt/nothingness/media`, re-checked at `/opt/nothingness` — same.
- **E5 (met):** getSemantics returned a real tree; the action node carries the distinguishing label "jump to now-playing track in browser" plus the ⊙ glyph and a tap action — genuinely accessible, not a bare glyph.
- **E6 (met):** Candidate's `before_track_54.png` shows the browser with the playing row (54) absent from the visible list and the ⊙ crumb glyph; my own before reproduction (44 off-screen) matches.
- **E7 (met):** Candidate's `after_track_54_delayed.png` shows row 54 now visible+highlighted with the path unchanged; my after reproduction matches (44 scrolled to top, same folder).
- **E8 (met):** Write-up claims are all backed by the candidate's own session reads (6× getLibraryState, 6× getSemantics, 18× tree, 68× shoot, plus the before/after PNGs).
- **E9 (met):** On-screen `void-folder:` tap entered media; `void-up` returned to parent. Playback: with a real folder queue (row-tap builds a 10-track queue) next 46→47 and prev 47→46; pause/resume clean. (next/prev stopping under a single-track `play` is the pre-existing empty-queue quirk, not a regression.)
- **E10 (met):** Overflow count 0 throughout; only ALSA sound-card warnings (no audio device in container), no Flutter exceptions; app live and responsive at the end.

## Bottom line
The candidate correctly shipped the hard same-folder-scroll case (E2) and preserved the cross-folder case (E1), with an accessible label and genuine screenshots. But it implemented the Linux branch as an unconditional "show whenever something is playing", so the action stays active even when the row is already fully visible — failing the required conditional-on-visibility expectation E3. One required unmet caps the run at **partial** despite 9/10 expectations met (raw 0.9).
