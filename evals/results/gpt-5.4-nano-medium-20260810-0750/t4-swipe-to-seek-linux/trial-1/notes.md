# t4-swipe-to-seek-linux — judge notes (judge-t4)

**Validity: `unassigned` (not scoreable by the pipeline).** The candidate used its entire
1800-second budget — `agent_settled` at 1798.5s, supervisor abort at 1800.2s — so it never entered
`awaiting judge` and `judge-control.py finish` could not be called (it returned
`judge_control_unavailable` because the candidate process was already gone). `classify-run.py`
requires `completion.reason` to start with `judge_finish:` and `timed_out` to be false before it
will classify a run as valid, so the harness refused the scorecard. This is not an infrastructure
failure and not a judge lapse: the candidate worked right up to the wall, leaving a 1.6-second
window in which no judge could have finished it.

**Had it been scoreable, the verdicts below give 6.5/10 credit with three required expectations
unmet, which caps the run at `partial`.** The full scorecard is preserved at
`.tmp/judge-gpt-5.4-nano-medium-20260810-t4-swipe-to-seek-linux/scorecard.json`.

## What the model actually did

It edited exactly the right two files. In `lib/widgets/hero_feedback_surface.dart` it added
`onSeekPreviewChanged` / `onSeekPreviewEnd` callbacks fired from the existing drag handlers, gated
the center seek HUD behind `if (seeking.value && !isLinux)`, and cleared the preview from a
post-frame callback on drag end. In `lib/screens/void_screen.dart` it added a Linux-only
`_SeekPreview` state that replaces the crumb's folder-path row with
`<target> / <duration> <percent>%` while a preview is live. It also added a stable key
(`hero-seek-gesture`) to the hero's `GestureDetector`. The analyzer was clean and it hot-reloaded
the change into the running app.

Where it fell down is verification. Its only gesture tool was `drive.py call
ext.nothingness.dragByKey ... kind=touch`, one atomic call. I confirmed by hand that this call
moves nothing on this Linux desktop build: it returns a success payload but playback position is
unchanged afterwards, because `_invokeDragInSubtree` walks the keyed element's *descendants* with
`includeSelf=False`, so a key placed on the detector itself can never match, and the synthetic
pointer fallback does not reach the recognizer. The model also replaced the supplied 10-track opus
fixture with two zero-byte files it created at `/tmp/nothingness_seek/`, whose duration is 0 — so
even a working gesture would have rendered the `--:-- / --:--` placeholder rather than real values.

## How I drove it

`dragByKey` was unusable, so I drove real X11 pointer input through XTEST (`libXtst` via ctypes,
`/tmp/xdrag.py` and `/tmp/xclick.py` in the container). That produces genuine mouse events with real
frame boundaries, and — by holding the button down after the motion — it let me capture true
mid-gesture state, something `dragByKey` cannot do. I ran five swipes across both directions and
magnitudes from 60 to 900 px on a 7-minute opus fixture, plus two bursts of varied speed.

## Per-expectation

**E1 — bottom line shows target/duration/progress while swiping — `unmet` (required).** The feature
itself works: with the button held mid-drag I read the crumb as `1:33 / 7:00 22%`, `3:17 / 7:00 47%`,
`0:55 / 7:00 13%` and `3:07 / 5:59 52%`, against a baseline crumb of `~` (the folder path). But this
expectation is about the *candidate's own* capture, and there is none. Every swipe it drove was a
single atomic call; a regex for a `M:SS / M:SS` readout across all 25,928 events of its session
returns zero hits. It never once saw the readout it wrote.

**E2 — no center seek indicator — `met` (required).** Across five of my own swipes plus idle and the
release instant, no centered time readout and no full-height vertical line appeared anywhere over
the hero. `hero-seek-hud` is absent from every depth-200 widget tree I read, and the HUD is
compiled out on Linux. The candidate's own during-gesture screenshot also shows none.

**E3 — feedback clears after the gesture — `met` (required).** 1.5s and 2s after release, and again
3s later with no further input, the crumb read `~ / jump to now-playing folder / ⊙`, identical to
the pre-swipe baseline, with no residual readout.

**E4 — values track the swipe rather than a placeholder — `unmet` (required).** No second data point
exists in the candidate's evidence, because no first one does. (For what it is worth, my own
captures show the feedback is genuinely live: −350 px gave −109s and +500 px gave +157s from the
same start, ~312 ms/px in both, and the percentage always matched target ÷ duration.)

**E5 — release still commits a real seek — `met` (required).** Pre-swipe runtime position 69,952 ms;
mid-gesture readout `3:17 / 7:00`; runtime capture 2s after release 200,971 ms — the 197,000 ms
target plus the playback since commit, inside ±2s. Reproduced twice more: shown `0:55` → measured
57,161 ms, shown `3:49` → measured 231,064 ms.

**E6 — during-gesture screenshot genuinely mid-gesture — `unmet` (required).** The deliverable is
traceable to sequence 25216–25224: `dragByKey ... kind=touch; sleep 0.05; shoot`. No incremental
updates, no elapsed time inside a gesture. It is byte-identical (md5 `641dfd96…`) to the
post-gesture deliverable taken 0.4s later — in fact all 21 screenshots in the run share that hash.
Opened, it shows a paused transport, the fabricated `track2.mp3`, and the bottom line still on the
folder path. The artifact disproves the claim it was submitted to support.

**E7 — post-gesture screenshot — `partial` (required).** My own post-gesture capture is correct and
on-point: bottom line back to `~` with the ⊙ glyph, no seek readout, no center indicator, progress
hairline at 48% consistent with the committed seek. The candidate's submitted post-gesture
screenshot happens to show the folder path too, but it is a byte-identical duplicate of its
during-gesture screenshot — the exact falsifier this expectation names — and depicts a paused
fabricated fixture.

**E8 — structural corroboration of the settled state — `met` (secondary).** At the same settled
moment the ledger observation's semantics dump reads `~ / jump to now-playing folder / ⊙` and its
`inspect` payload shows position 200,971 ms with zero overflow reports, both agreeing with the
screenshot.

**E9 — unrelated hero gestures unaffected — `met` (secondary).** Real on-screen clicks on the hero's
three tap zones still work: right third advanced index 0→1, left third returned to 0, middle
toggled pause then play. A real vertical drag on the same surface still expands the swipe-up
browser (collapsed `↑ swipe to browse` before, expanded browser with grabber after), and the hero's
recognizer set correctly drops vertical drag once expanded, matching the unchanged `acceptVertical`
logic.

**E10 — no crashes or new errors — `met` (secondary).** Two bursts of varied swipes (60–900 px,
3–40 steps, 4–50 ms per step, both directions) left overflow reports at 0 before and after, zero
`EXCEPTION CAUGHT` / `Failed assertion` / `RenderFlex overflowed` lines in the Flutter run log, the
crumb correctly reverted, and the app answered normally at the end.

## Interventions

None. Zero delivered; the candidate was failing, not stuck.

## Two things worth flagging to whoever runs this next

The judging note circulated for this task says to anchor `dragByKey` on `hero-gesture-surface` and
confirm `"mode": "descendant-callback"`. That key does not exist anywhere in this fixture commit,
and the advice is backwards for how `dragByKey` resolves: `_invokeDragInSubtree` calls
`_walkSubtree(root, …)` with `includeSelf=False`, so the key must sit on an **ancestor** of the
`GestureDetector`, never on the detector itself. No such ancestor key exists in this codebase, so
the descendant-callback path is unreachable for the hero and synthetic pointers move nothing —
`kind=mouse` aborts with the `mouse_tracker` assertion and `kind=touch` silently no-ops. XTEST is
the only way to exercise this gesture from the judge side today, and it is strictly better anyway:
it produces real frames, so a judge *can* capture a genuine mid-gesture instant, contrary to the
harness note in the rubric.

Second: a candidate that spends its whole budget currently cannot be scored at all. That turns an
honest, fully-evidenced `partial` into no data point.
