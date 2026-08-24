# T4 swipe-to-seek — judge notes (gpt-5.4-nano, low)

Run: `t1-t7-gpt-5.4-nano-low-t4-swipe-to-seek-linux-run-c5ab22513230`
Outcome: **partial** (three required `events` expectations unmet cap the run).

## What the candidate actually did
The candidate edited only `lib/widgets/hero_feedback_surface.dart`. The diff is display-only and correct: it deletes the centered time readout plus the full-height vertical preview line, and rewrites `_SeekHud` to a single bottom-left line rendering `m:ss / m:ss · NN%` (target position / duration / progress), still gated by the existing `seeking.value` flag so it clears on release. It ran `flutter analyze` (clean) and `flutter test` (pass). It made 267 bash / 18 read / 2 edit tool calls and **never launched or drove the app** — no `flutter run`, no `drive.py`, no `dragByKey`, no `shoot`. Its own final message concedes it could not produce the required during-gesture and post-gesture screenshots.

## What I verified myself
I built and launched the candidate's Linux build in-container (DISPLAY=:99), played the 7-minute fixture `07-undercover-44.opus`, and drove real gestures with X11/XTEST (synthetic `dragByKey` cannot move the hero on this fixture).

- **Feature works.** A held rightward XTEST swipe showed a bottom-left `4:05 / 7:00 · 58%` readout with no center indicator and no vertical line; a leftward swipe showed `1:51 / 7:00 · 26%` — the value tracks direction and magnitude. The `hero-seek-hud` widget is present in the tree mid-gesture and absent after release.
- **Seek commits (E5).** Rightward swipe moved playback ~30s → ~296s on the 420s track while playing — a real forward seek in the requested direction.
- **Clears (E3/E7).** Post-release the bottom line reverts to the folder path `~`, with the seek readout gone, confirmed by both screenshot and tree.
- **No center indicator (E2).** Confirmed across a held mid-gesture capture and a burst of swipes.
- **No regressions (E9).** On-screen hero center-third tap and transport-play toggled play/pause; transport-next advanced the track. The GestureDetector, tap handling, and vertical-drag wiring are untouched by the diff. Vertical-drag reveal is gated to swipeUp browser presentation (not active in this mode), so it is a no-op here by unchanged design.
- **Stable (E10).** Five varied swipes → 0 overflows before/after, app still live and playing. Log errors were ALSA (no sound card) and SoLoud file-not-found from my own malformed setQueue test paths — not the gesture.

## Why it is only partial
E1, E4, and E6 are `events` expectations: they audit whether the *candidate's own session* captured a mid-gesture instant (the bottom-line readout, two tracking data points, and the during-gesture screenshot deliverable). The candidate captured nothing and produced no screenshots, so all three are `unmet`. Each is required, which caps the run at `partial` regardless of the seven passing expectations. The implementation itself is correct; the candidate simply never proved it and never delivered the required artifacts.
