# Expectations bundle — T4 · Swipe-to-seek feedback placement (Linux)

- **Task id:** `t4-swipe-to-seek-linux`
- **Prompt (verbatim):** "On Linux, update swipe-to-seek feedback so a horizontal swipe shows the target position, duration, and progress in the bottom folder line while swiping. Do not show a center seek indicator. The temporary feedback must clear after the gesture. Provide during-gesture and post-gesture screenshots."
- **Fixture:** `evals/assets/opus/manifest.json` — 10 tracks mounted at `/opt/nothingness/media` in the candidate's container. Prefer a longer track (several minutes) so seek targets are unambiguous and far from either end of the track.
- **Evidence this task's manifest already requires:** `swipe_pre_state`, `swipe_action`, `swipe_during_state`, `swipe_during_screenshot`, `swipe_post_state`, `swipe_post_screenshot`.
- **Scoring:** per `evals/README.md` § Scoring rubric. Judge gives one verdict per expectation below — `met` (credit 1.0), `partial` (0.5), `unmet` (0.0) — each with a one-line justification and a reference to the `judge-verify.py` observation that supports it. **Any `unmet` expectation tagged `required` caps the run at `partial`, regardless of the aggregate score.**

## How to judge this task

This is the hardest of the seven tasks — the field test this rubric is calibrated against (`evals/archive/local-model-field-test/report.md` / `notes.md`, "task 4") saw every model except one either fail outright or declare success over a screenshot that, read plainly, still showed the *old* centered readout with a tall vertical line, or showed the bottom line completely unchanged. Treat every claim here as something to disprove, not to take on faith.

**A harness fact that shapes how this bundle is structured, not what counts as correct:** the desktop build's only synthetic-gesture primitive (`drive.py call ext.nothingness.dragByKey key=<k> dx=<..> dy=0 steps=<n>`) fires the whole press→move×N→release sequence synchronously inside one call, with no frame yield between steps — there is no real frame boundary a judge's own follow-up `drive.py shoot`/`inspect` can land on mid-sequence. Whatever the judge captures immediately after the call returns reflects state as of release, never a true mid-drag instant, no matter how quickly it's issued. This is a property of the driving tool available to the *judge*, not an excuse for the candidate: a real user's mouse produces genuine live-updating frames throughout, and the one field-test model that nailed this task got its during-gesture screenshot by adding its own widget-level automation with real frame yields between steps — solving exactly the capture problem the frozen `dragByKey` cannot.

Because of that asymmetry, this bundle is explicit about which expectations rest on which kind of evidence, and an expectation is never allowed to instruct you to cite evidence the pipeline has no path to produce:
- **`verification`** expectations (E2, E3, E5, E7, E8, E9, E10) are things you reproduce live, right now, against the running app. Every verdict on these must be backed by your own fresh capture, not a description, and not the candidate's say-so.
- **`events`** expectations (E1, E4, E6) are, by exception, about the *candidate's own during-gesture capture* specifically because no independent reproduction of a genuine mid-drag instant is possible through this harness — there is no ledger mechanism to cite a candidate-produced artifact as `verification` evidence at all, only the session's own digest-verified event trail (the candidate's own tool calls and their outputs). This is a deliberate, narrow departure from the usual rule that `events` never substitutes for the judge looking at the app: here, "looking at the app" during the gesture is not an option available to the judge under any evidence kind, so the honest alternative is auditing whether the candidate genuinely captured that instant itself and what it captured — not pretending a release-instant reproduction is the same thing. Structured state reads (`getPlaybackState`/`tree`/`probeText`-style JSON) the candidate captured mid-gesture are fully legible in the event trail; a screenshot capture call's result may only be traceable as "a capture happened around this point in the sequence" since large payloads are truncated in the event log — don't treat a truncated/absent image payload alone as proof nothing was captured, and don't claim to have visually confirmed pixels you cannot actually see through this channel.

Use `hero-gesture-surface` as the `dragByKey` anchor — that key sits directly on the hero's gesture surface `GestureDetector`. `dragByKey` does not go through Flutter's normal hit-testing/pointer-routing: `_invokeDragInSubtree` walks the keyed element and its descendants and, when it finds a `GestureDetector`, invokes that widget's `onHorizontalDragStart`/`onHorizontalDragUpdate`/`onHorizontalDragEnd` callbacks directly; only when no match is found does it fall back to synthetic pointer events, which abort on this Linux desktop build with a `mouse_tracker.dart` assertion and move nothing. Confirm you got the working path by checking the call's own reply reads `"mode": "descendant-callback"` — and treat a `mouse_tracker` assertion as a harness failure to report, not as evidence about the candidate. Do **not** anchor on `hero-song` or any other key inside the hero band: those are descendants of the detector, not ancestors, so the walk can never reach it.

## Required expectations

### E1 — While swiping, the bottom folder line shows target position, duration, and progress
**Evidence:** events

**Statement:** The candidate's own session genuinely captured a mid-gesture instant during a horizontal swipe — not the release-instant state a judge's own reproduction is limited to — and that captured output shows the row that normally shows the current folder path (at the bottom of the Void screen, above the gesture-nav area) instead showing the seek target's position, the track's total duration, and some progress indication (e.g. a fraction/bar) tied to where the swipe currently sat.

**Drive:** `drive.py play <a several-minute fixture>` and a baseline `drive.py tree` yourself first, to confirm the bottom line ordinarily shows the folder path. Then audit the session's own event trail for the candidate's during-gesture capture(s): find the tool call(s) around a drag in progress (e.g. its own incremental pointer/gesture updates issued with real elapsed time between them, per the harness note above — never a single atomic `dragByKey` call standing in for "during"), and read that call's own result payload directly, in full, rather than the candidate's caption of it. As a sanity check only (not the cited evidence), you may also issue your own `dragByKey` swipe and an immediate `tree`/`getPlaybackState` read; if that plainly contradicts what the candidate's own capture shows, say so in the note.

**Confirms `met`:** the event trail contains a capture genuinely taken while a gesture was in flight (the surrounding events show incremental updates spanning real elapsed time, not one atomic call), and that capture's own output shows the bottom line's target/duration/progress in place of the folder path — not blank, not a static placeholder, not the folder path unchanged.

**Falsifies (→ `unmet`):** no during-gesture capture is traceable anywhere in the session's own event trail; the closest candidate capture is indistinguishable from a resting/idle read (nothing in the surrounding events shows a gesture was actually in flight); or the captured output shows the folder path unchanged, or only one of the three required pieces (e.g. no duration, no progress indication).

### E2 — No center-screen seek indicator ever appears
**Evidence:** verification

**Statement:** At no point — during the swipe or immediately after release — does a centered time readout with a tall full-height vertical line appear over the hero. (This is the existing behavior the prompt asks to remove; the app currently shows exactly this at the center of the hero during a swipe.)

**Drive:** perform several `dragByKey` swipes varying direction (`dx` positive and negative) and magnitude, each immediately followed by your own `drive.py tree`/`drive.py shoot` — this is the citable evidence for this expectation, and it covers everything genuinely reproducible: idle state and the release instant. As additional, non-required corroboration, also plainly read the candidate's own during-gesture screenshot (via the session's event trail, same as E1) for any centered readout or vertical line, and note in your justification if it disagrees with your own reproduction.

**Confirms `met`:** across every one of your own reproductions, no centered time readout or full-height vertical line is present at any point, and nothing in the candidate's own during-gesture capture contradicts that.

**Falsifies (→ `unmet`):** any of your own reproductions shows a centered time readout and/or a tall vertical line anywhere over the hero during or immediately after a swipe, or the candidate's own during-gesture capture shows one even though your own reproduction didn't happen to catch it.

### E3 — The temporary feedback fully clears once the gesture ends
**Evidence:** verification

**Statement:** After the swipe is released and a brief settle, the bottom line reverts to showing whatever it displayed before the swipe (the folder path), with no leftover target/duration/progress readout persisting indefinitely.

**Drive:** immediately after a `dragByKey` call, `drive.py tree`; then wait at least 1 real second with no further input and `drive.py tree` again; compare both against the pre-swipe baseline.

**Confirms `met`:** the bottom line reads the same folder path it showed before the swipe, with no residual seek readout, at the latest check.

**Falsifies (→ `unmet`):** the seek readout is still present in the bottom line well after the gesture ended (more than a couple of seconds, with no further input), or the bottom line is left blank/broken rather than reverted to the folder path.

### E4 — The displayed values genuinely track the swipe, not a static placeholder
**Evidence:** events

**Statement:** The candidate's own during-gesture captures for (at least) two swipes of different direction and/or magnitude on the same track show different target-position values that move in the direction and rough proportion of the swipe — the candidate's own evidence shows the feedback is computed live from the gesture, not a fixed string. (A judge's own reproduction cannot settle this directly — per the harness note above, an independent follow-up capture only ever reflects release-instant state, not the live-tracking behavior mid-gesture.)

**Drive:** audit the session's event trail for at least two distinct during-gesture captures corresponding to swipes of different `dx` and/or direction that the candidate's own instrumentation performed; read each capture's own output payload directly.

**Confirms `met`:** the two captured outputs show different target-position values consistent with the different swipe magnitudes/direction the session's own events show were exercised (further swipe → target further from the start position, in the correct direction).

**Falsifies (→ `unmet`):** only one during-gesture capture with a legible value exists anywhere in the session (no second data point to compare); the two captures show identical or implausible values despite a claimed difference in swipe magnitude/direction; or no during-gesture capture with a legible target value exists at all.

### E5 — Releasing still commits an actual seek to the last-shown target
**Evidence:** verification:runtime

**Statement:** Swipe-to-seek still *seeks* — releasing the gesture moves playback position to (approximately) the target that was last shown during the swipe, not merely redraws the UI without moving playback.

**Drive:** `drive.py inspect` (pre-swipe position); perform a `dragByKey` swipe with a known `dx`; `drive.py inspect` immediately after (post-release position).

**Confirms `met`:** the post-swipe position lands within ±2 seconds of the last target the feedback showed (or, if you can't independently catch the exact last-shown target given the atomicity note above, within ±2 seconds of a reasonable target implied by the swipe's direction and magnitude relative to the pre-swipe position and track duration) and is clearly different from the pre-swipe position in the requested direction.

**Falsifies (→ `unmet`):** position is unchanged after the swipe, moved the wrong direction, or lands nowhere near what the swipe's direction/magnitude implies — the same class of failure T1/E4 guards for fast-forward, here for the gesture path specifically.

### E6 — The required during-gesture screenshot was actually captured and is on-point
**Evidence:** events

**Statement:** The required during-gesture screenshot deliverable is traceable, in the session's own event trail, to a capture taken while a horizontal swipe was genuinely in progress (not at rest, not after a full release-and-settle) — not merely present among the deliverables with an unverified caption. (This cannot be settled as `verification`: a judge's own fresh screenshot, taken at judging time, can never itself be "mid-gesture" — see the harness note above — so the only citable evidence for a claim about this specific artifact's *timing* is the session's own record of when it was taken.)

**Drive:** find the tool call in the session's event trail whose result is the during-gesture screenshot deliverable; check the surrounding events for evidence the capture happened while a gesture was actually in progress (e.g. it falls between the candidate's own drag-start and drag-end instrumentation, with incremental state updates around it, spanning real elapsed time rather than one atomic call). Where the event trail's own structured state reads (not the screenshot's own truncated payload) are legible at that point, cross-check them against E1's criteria too.

**Confirms `met`:** the event trail shows this screenshot was genuinely captured mid-gesture (real elapsed time and surrounding incremental updates, not a single atomic call or a capture issued at rest), and nothing in the surrounding structured reads contradicts the bottom-line/no-center-indicator claim.

**Falsifies (→ `unmet`):** no during-gesture screenshot deliverable is traceable to any capture in the session's event trail; the surrounding events show the capture was taken at rest/idle or after a full release-and-settle rather than mid-gesture; or the surrounding structured reads at that point show the old center indicator or contradict the bottom-line claim — matching the exact recorded field-test failure of a screenshot disproving the claim it was attached to support.

### E7 — The required post-gesture screenshot was actually captured and is on-point
**Evidence:** verification:screenshot

**Statement:** A screenshot exists from this session captured after the swipe was released and the feedback had cleared, showing the bottom line back to its normal folder-path display with no lingering seek readout.

**Drive:** `drive.py call ext.nothingness.dragByKey key=<hero key> dx=<...> dy=0 steps=20`; wait ≥1 second; `drive.py shoot t4_post`; open the resulting PNG; compare against the candidate's own submitted post-gesture screenshot.

**Confirms `met`:** the image shows the folder path (or whatever the bottom line normally shows), with no seek readout and no center indicator anywhere.

**Falsifies (→ `unmet`):** no such screenshot exists; the image still shows the seek readout or a center indicator; or it's actually a duplicate/near-duplicate of the during-gesture screenshot rather than a genuinely later, settled capture.

## Secondary expectations

### E8 — An independent structural dump corroborates the post-gesture screenshot
**Evidence:** verification

**Statement:** Beyond the post-gesture screenshot, a structural read (`tree` and/or `getPlaybackState`/`getSettings`) taken after the settle window independently corroborates the bottom line's reversion to the folder path, so that claim doesn't rest on the image alone. (This is scoped to the post-gesture state deliberately: per the harness note above, a judge-driven structural read cannot independently corroborate the *during*-gesture state — that corroboration, if any, is whatever the session's own event trail shows alongside E1/E4/E6's captures.)

**Drive:** `drive.py tree` and `drive.py call ext.nothingness.getPlaybackState`, taken together after the settle window from E3/E7.

**Confirms `met`:** a text dump exists for the settled moment and agrees with the post-gesture screenshot.

**Falsifies (→ `partial`):** only the screenshot exists with nothing structural to corroborate it, or the structural read disagrees with the screenshot.

### E9 — Unrelated hero gestures are unaffected
**Evidence:** verification

**Statement:** Tap zones (previous / play-pause / next) and any vertical-drag behavior on the same gesture surface still work exactly as before the change — the horizontal-swipe rework didn't regress the other gestures sharing that surface.

**Drive:** `drive.py inspect` (baseline index/isPlaying); `drive.py tree` to find the key(s) for the on-screen previous / play-pause / next tap zones on the hero's gesture surface; activate each via `drive.py tap <key from tree>` — an actual on-screen tap, not a direct playback shortcut that bypasses the tap handler entirely — each followed by a fresh `drive.py inspect` to confirm the expected transition still happens; separately exercise a vertical `dragByKey` on the same surface and confirm whatever vertical-drag behavior it had before still fires.

**Confirms `met`:** every one of these on-screen tap zones and the vertical-drag behavior still produce their expected transition after the swipe-feedback change.

**Falsifies (→ `partial`/`unmet`):** any on-screen tap zone does nothing or does the wrong thing when tapped (even if the equivalent direct playback call still works — that would mean the tap zone itself is what regressed), or vertical-drag behavior stopped working or behaves differently than before this change.

### E10 — No crashes or new errors surfaced while exercising the gesture repeatedly
**Evidence:** verification:runtime

**Statement:** Repeatedly swiping (varying direction, magnitude, and speed) does not throw, error, or destabilize the app.

**Drive:** `drive.py overflows` before and after a burst of several `dragByKey` calls at varying `dx`/`steps`; `drive.py inspect` at the end to confirm the app is still live and responsive.

**Confirms `met`:** no new overflow/error entries attributable to the swipe feedback after the change, and the app answers normally at the end.

**Falsifies (→ `partial`/`unmet`):** new overflow/error entries appear tied to this area, or the app stops responding partway through the checks above.
