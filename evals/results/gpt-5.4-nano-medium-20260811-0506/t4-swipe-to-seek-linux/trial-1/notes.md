# T4 · Swipe-to-seek feedback placement (Linux) — judge notes

**Run:** `t1-t7-gpt-5.4-nano-medium-t4-swipe-to-seek-linux-trial-01-attempt-04`
**Model:** gpt-5.4-nano, thinking medium · 885 s of 1800 s budget · 98 tool calls · $0.121 · 0 interventions

## What the candidate did

It read the fixture carefully before touching it — `void_screen.dart`, `hero_feedback_surface.dart`,
`agent_service.dart`, and `drive.py` including the `dragByKey` implementation — then made a small,
well-aimed change across three files (119 insertions, 79 deletions):

- Deleted the `_SeekHud` widget and its `hero-seek-hud` key from `HeroFeedbackSurface`, removing the
  centered time readout and full-height vertical preview line entirely.
- Added two optional callbacks, `onSeekPreviewUpdate(target, duration)` and `onSeekPreviewEnd`, fired
  from `onSeekStart` / `onSeekUpdate` / `onSeekEnd`, and turned `seekTargetMs` from a `useState` into a
  `useRef` so the hero no longer rebuilds per drag tick.
- In `VoidScreen`, held the preview in a `useState<({int targetMs, int durationMs})?>` (Linux-only via
  `Platform.isLinux`) and, when set, rendered `'$target / $duration · $pct%'` in the crumb row in place
  of the folder path. Cleared it on a 450 ms timer after drag end, with the timer cancelled on unmount.
- Updated `test/widgets/hero_feedback_surface_test.dart` to assert the new callbacks instead of the
  deleted HUD key. `flutter analyze` came back clean.

It then launched the Linux app for real (`flutter pub get --offline`, then `flutter run -d linux`),
navigated the browser to `/opt/nothingness/media`, played `01-undercover-49.opus`, and tried to drive
the gesture. That last part is where it came apart.

## Where it fell short

The candidate's whole gesture evidence is one atomic call:
`ext.nothingness.dragByKey key=hero-gesture-surface dx=180 dy=0 steps=12 kind=touch`. Its first attempt
with `kind=mouse` aborted on the documented `mouse_tracker.dart` assertion, so it retried with
`kind=touch`, got a success payload back, and treated that as a swipe having happened. It never checked.
I did: four `dragByKey kind=touch` reproductions of my own (dx = +240, −240, +600, −600) moved nothing
at all — playback position advanced only by the seconds of wall-clock that had passed, the seek-preview
hook state stayed `null`, and the crumb never changed. The success payload is a lie, exactly as the
harness notes warn.

Then, in a *separate* bash invocation about 9 seconds after that call had already returned, it ran
`sleep 0.15; drive.py shoot seek_during`. So the "during-gesture" screenshot was taken by a different
process, well after release, of a gesture that had not moved anything in the first place. There is no
incremental pointer instrumentation and no mid-gesture structured read anywhere in the session. Its own
final message half-admits the shape of the problem — it says it "used a short delay to allow QA
screenshot capture" — but a 450 ms clear window does not help when the capture is nine seconds late.

The deliverable proves it. `seek_during.png` shows the bottom line reading `/opt/nothingness/media` —
the folder path, unchanged, no target, no duration, no progress. It differs from `seek_post.png` in 510
of 920160 pixels (a progress hairline advancing a hair), so the two "before and after" screenshots are
effectively the same settled frame. This is the precise failure the rubric is calibrated against: a
screenshot that disproves the claim it was submitted to support.

## What I verified myself

`dragByKey` cannot drive this hero, so I drove it with real X11 input through XTEST (~40 lines of
`ctypes`), holding the button down after the motion so a capture could land on a true mid-gesture
instant. The Flutter client area sits at X11 offset (+1, +20) and the hero surface spans y ≈ 0–228, so
the press landed at (450, 135) and moved horizontally. I seeked well inside a 7-minute track
(`07-undercover-44.opus`, 420623 ms) before every directional test, so no result is an artifact of the
`[0, duration]` clamp.

- **Mid-gesture, button still down:** the crumb row read `4:10 / 7:00 · 60%` — target position, total
  duration, and a progress percentage — with the seek-preview hook state populated as
  `(durationMs: 420623, targetMs: 250315)`. The feature works, and works well.
- **No center indicator:** zero `hero-seek-hud` nodes in every tree I captured, and no centered readout
  or vertical line visible in any screenshot, mid-gesture or at rest, across seven separate swipes.
- **Direction and proportion:** rightward from 92.3 s targeted 195.0 s; leftward from 220.3 s targeted
  117.5 s (`1:57 / 7:00 · 28%`). Both proportional to the distance dragged.
- **Clears on release:** hook state back to `null`, crumb back to `/opt/nothingness/media`.
- **Seek still commits:** 92272 ms before, target 195024 ms shown mid-drag, 197157 ms after release —
  the target plus the ~2 s of playback that elapsed while the capture was taken.
- **Other gestures intact:** all three hero tap zones fire as real clicks (left third restarts the
  current track, which is correct for position > 3 s; centre toggles play/pause; right advances the
  index), and an upward drag still expands the swipe-up browser.
- **No new instability:** ten swipes at varying direction, magnitude and speed left the overflow count
  at 0 and the app responsive.

Two things worth recording so nobody misreads them as candidate defects. Seeking while *paused* does
not update the reported position, so a paused seek-commit test looks like a failure that isn't — I had
to redo that check with playback running. And the run log carries
`SoLoudInvalidParameterException` on seeks that clamp to 0 or past the end; a plain `drive.py seek 0`
with no gesture at all reproduces it, so it belongs to the pre-existing seek path.

## Verdicts

| # | Tier | Verdict | One-line reason |
|---|------|---------|-----------------|
| E1 | required | **unmet** | No mid-gesture capture exists in the session; its during-shot shows the folder path unchanged. |
| E2 | required | met | No center readout or vertical line in any of seven reproductions; `_SeekHud` deleted outright. |
| E3 | required | met | Crumb and hook state revert after release, verified more than 2 s later. |
| E4 | required | **unmet** | Only one drag call in the whole session and no legible target value captured — no data points to compare. |
| E5 | required | met | Release commits the seek to the last-shown target (92.3 s → 195.0 s target → 197.2 s). |
| E6 | required | **unmet** | The during-screenshot is a separate call ~9 s post-release and a near-duplicate of the post shot. |
| E7 | required | met | My settled screenshot shows the folder path, no readout, no center indicator. |
| E8 | secondary | met | Tree and runtime lenses from the settled moment corroborate the post-gesture image. |
| E9 | secondary | met | All three tap zones and the vertical-drag browser reveal still work. |
| E10 | secondary | met | Overflow count 0 before and after a ten-swipe burst; app responsive. |

The shape of this result: the implementation is genuinely good — arguably the cleanest possible reading
of the prompt, and it survived every functional probe I aimed at it — but the candidate never observed
its own work. All three failures are the same failure: it accepted a `dragByKey` success payload as
proof a swipe had happened, and screenshotted a settled app while believing it was mid-gesture. The
verification gap, not the code, is what caps this run.
