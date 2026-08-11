# t4-swipe-to-seek-linux — trial-01-attempt-03 — judge v130-judge-t4

**Outcome: partial (adjusted 0.9, capped by one required-expectation miss).**

The candidate implemented the feature cleanly and correctly: `hero_feedback_surface.dart` gained
`onSeekScrub`/`onSeekScrubEnd` callbacks fired from the pre-existing `onSeekStart`/`onSeekUpdate`/
`onSeekEnd` handlers, and a `showCenterSeekHud` flag that `void_screen.dart` sets false on Linux.
`void_screen.dart` renders the live target/duration/progress in the bottom crumb row while scrubbing
and falls back to the normal folder-path/search/jump-glyph row otherwise. I read the diff directly in
the running container (`git diff` inside the container, not the seed) and confirmed none of this
touches the underlying seek math — only where the numbers are displayed.

Also worth recording: the candidate hit the exact dead end the rubric brief predicts (`dragByKey` with
`key` on the `GestureDetector` itself, `kind=mouse` aborting with the `mouse_tracker.dart` assertion),
then — like the one field-test model that solved this task — wrote its own instrumentation
(`dragByKeyHold`/`endDrag` in `dev/agent_service.dart`) dispatching real `PointerAddedEvent`/
`PointerMoveEvent`/`PointerUpEvent` with real per-step timestamps, letting it hold a genuine
mid-gesture instant open across a real screenshot call. This is legitimate, in-scope engineering, not
a shortcut.

- **E1 (met):** Candidate held `dragByKeyHold dx=220 kind=touch` at 7/16 steps for real elapsed time
  (~7s before the screenshot, ~8s more before release) and shot `during_seek.png` while still held.
  I opened that PNG myself: the bottom line reads `0:04 / 1:23   5%` in place of the folder path — all
  three required fields, genuinely computed, not a placeholder.
- **E2 (met):** My own fresh reproductions (release-instant `dragByKey`, both directions, up to 800px,
  plus a held mid-gesture capture of my own) never show a centered readout or vertical line anywhere
  over the hero. The candidate's own during-gesture capture agrees.
- **E3 (met):** After release + ~2.5s idle, the bottom line reverted exactly to the pre-swipe folder
  path in my own captures.
- **E4 (unmet, required — caps the run at partial):** The candidate ran exactly one
  `dragByKeyHold`/`shoot`/`endDrag` sequence in the entire session, at one `dx` and one direction. It
  never captured a second during-gesture instant at a different magnitude or direction, so its own
  evidence trail cannot show the readout tracking the gesture live rather than being a fixed string
  that happened to be right once. I found no second capture anywhere in the transcript.
- **E5 (met):** I captured position immediately before (7114ms) and immediately after (55125ms) a
  +350px rightward touch swipe — clearly forward, correct direction, proportionate. Side note for
  whoever reads this next: leftward (negative-dx) swipes reproducibly failed to move the seek target
  backward at all in this build, tested repeatedly up to -800px from several starting positions. I
  checked — `seekAccumDx`/`primaryDelta` math is byte-identical to the pinned fixture's pre-existing
  code, untouched by this diff, so it predates the candidate's change and isn't something to fault
  this candidate for. Worth a look at the harness/base-app level, though.
- **E6 (met):** The during_seek.png capture sits with real elapsed time on both sides (after the hold,
  before the release) — genuinely mid-gesture, not an atomic capture.
- **E7 (met):** My own post-gesture capture (release + settle) shows the real folder path restored,
  no seek readout, no center indicator. The candidate's own `post_seek.png` shows `~` plus a jump
  glyph instead of a literal path — because it played the track via `playTrackByPath` rather than
  navigating the library, so `library.currentPath` was null the whole session. That's still the
  correct reverted placeholder for a null path (see `void_screen.dart`: `path == null ? '~' : path`),
  not a lingering readout and not a duplicate of `during_seek.png` — just a weaker demonstration than
  it could have been.
- **E8 (met):** The settled capture's `library.currentPath` agreed exactly with the screenshot text.
- **E9 (met):** Real on-screen X11 clicks at the hero surface's outer thirds correctly hit previous
  (resets current-track position), play/pause (toggles `isPlaying`), and next (advances
  `currentIndex`) — note there's no separate widget key per zone, so `tapByKey`/`drive.py tap` can't
  reach previous/next (it always lands center via the RenderBox-center fallback); I used a raw XTEST
  click at absolute screen coordinates instead. A real vertical drag on the same surface did nothing
  and didn't crash, consistent with the diff never touching vertical-drag wiring.
- **E10 (met):** Zero overflow reports before/after a burst of 5+ varied swipes; app stayed fully
  responsive throughout. The only errors all session were `mouse_tracker.dart` assertions from the
  frozen `dragByKey` with `kind=mouse` — a known, pre-existing harness/tool issue, never an app crash.

**Dry-run points for the manager:**
1. `observe` behaved exactly as documented: returns in the foreground at ~2 minutes with
   `still_running: true`, streams actions only.
2. `collect.json` reported `agent_shots: 2`; both PNGs were present under `artifacts/agent-shots/`
   and I opened them directly (not just captions) — both genuinely on-topic, see E1/E7 above.
3. `summary.json.candidate.truncated_turns` was `0`. No Azure content-filter loss this run.
4. No deadline guard fired. The candidate finished naturally at 791.7s elapsed — 44% of its 1800s
   budget — well clear of both the 90% `observe` guard and the 97% supervisor guard.
5. Rubric read cleanly against what I could actually observe; I found no line that was wrong or
   unachievable. The one thing worth feeding back into the rubric/brief: the pre-existing
   leftward-seek quirk (see E5) is real and reproducible, and a future judge testing E5/E9 with a
   leftward swipe by default would incorrectly fail a fully-correct candidate on this Linux-only
   change — worth a note there so nobody burns time chasing it as a regression.
