# T4 — Swipe-to-seek feedback placement (Linux) — judge notes

**Run:** t1-t7-gpt-5.4-nano-medium-t4-swipe-to-seek-linux-run-b51243550ec4
**Model:** azure-openai-responses / gpt-5.4-nano / thinking=medium (identity verified)
**Outcome:** partial (score 2, raw 0.7, adjusted 0.7) — 0 interventions, unassisted.

## What the candidate actually did

It made a clean, correct implementation touching two files. In `hero_feedback_surface.dart` it
gated the existing center seek HUD behind `seeking.value && !isLinux` (so it never renders on Linux)
and added `onSeekFeedback`/`onSeekFeedbackEnd` callbacks fired from the horizontal-drag
start/update/end with the live target, duration and fraction. In `void_screen.dart` it wired those,
on Linux only, into the bottom crumb (folder-path) line so that while scrubbing the line shows
`m:ss / m:ss NN%`, and it added a 600 ms timer that clears the preview after the gesture. It also
added a `ValueKey('hero-feedback-surface')` on the surface — an ancestor of the GestureDetector —
which (unusually for this fixture) makes `dragByKey` actually drive the hero. `flutter analyze`
passes.

The feature genuinely works. I confirmed it live by driving a real held X11 (XTEST) gesture and
reading the app mid-hold: the bottom line showed `3:16 / 7:00 47%` (and `2:49 / 7:00 40%` on another
hold), the hero center showed only "empty" with no HUD or vertical line, and on release playback
jumped to the shown target.

**The gap is proof, not function.** The task required during- and post-gesture screenshots, and the
candidate captured its "during" shot the only way the frozen `dragByKey` allows: one atomic
`dragByKey` call, then a *separate* `drive.py shoot during_seek`. By the time that second command
ran, the 600 ms clear timer had already fired, so `during_seek.png` shows the bottom line back at the
folder path `~ ⊙` — not the seek readout. Its `post_seek.png` is the same folder-path state. So the
candidate never captured the mid-gesture instant its deliverable claims to show.

## Per-expectation

- **E1 (unmet, required):** Candidate's during capture shows the folder path, not target/duration/
  progress, and was a single atomic gesture with no incremental updates over real elapsed time. The
  feature works (I saw it live), but the candidate's own trail never captured it.
- **E2 (met):** No center readout or full-height vertical line at any point — at rest, mid-hold, or
  post-release. Center is gated off on Linux in code and absent in every capture.
- **E3 (met):** After release + ≥1 s settle the bottom line reverts to the folder path with no
  residual readout (post-settle tree + screenshot agree).
- **E4 (unmet, required):** Only one during-gesture capture exists and it carries no legible target
  value, so live value-tracking across differing swipes is not demonstrated in the candidate's trail.
- **E5 (met):** Release commits a real seek. At-rest position 102 229 ms → post-release 243 085 ms
  (~141 s forward jump, far beyond playback drift, in the swipe direction). Reproduced independently
  (121 536 → 219 741 ms on a +220 drag).
- **E6 (unmet, required):** The during-gesture screenshot deliverable traces to a capture taken after
  a single atomic drag settled; its content shows the folder path, so the artifact disproves the
  claim it was submitted to support — the exact recorded field-test failure this expectation guards.
- **E7 (met):** A genuine settled post-gesture screenshot shows the bottom line back to the normal
  folder path, no readout, no center indicator.
- **E8 (met):** A post-settle structural read (tree + runtime) independently corroborates the
  reversion.
- **E9 (met):** On-screen tap zones still work — tapping `transport-play` toggled isPlaying
  True→False; next/prev also fired. The diff leaves tap and vertical-drag wiring untouched.
- **E10 (met):** A burst of varied swipes produced zero overflow/error entries and the app stayed
  live and responsive; run log shows only ALSA/GTK environment noise, no Flutter exceptions.

## Bottom line

Correct, well-scoped implementation of the actual feature, undone on the scored deliverable: the
required during-gesture screenshot shows the cleared folder path rather than the seek readout,
failing the three event-trail expectations (E1/E4/E6) that measure whether the candidate captured its
own gesture. Required-unmet caps the run at **partial**.
