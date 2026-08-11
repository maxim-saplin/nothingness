# T5 · Jump to now playing (Linux) — judge notes

Run `t1-t7-gpt-5.4-nano-medium-t5-jump-to-now-playing-linux-trial-01-attempt-05`, gpt-5.4-nano
(thinking: medium), 1046 s of a 2700 s budget, 86 tool calls, $0.154, zero interventions. The
candidate settled on its own and was finished from `awaiting_judge`.

## What the model actually did

It read the browser and screen code, found the pre-existing `⊙` crumb affordance (B-015/B-031) that
already appeared when `dirname(playing)` differed from the browsed folder, and hardened the
*condition* rather than rebuilding the feature. Two files, +105/−10:

- `lib/widgets/void_browser.dart`: added a `isTrackVisible(path)` probe to `VoidBrowserController`,
  registered alongside the existing `scrollToTrack` handle. It finds the row's `GlobalKey` context,
  and returns whether the row's global rect `overlaps` the scroll viewport's rect; a row that was
  never built (fully off-screen) returns false, and it falls back to "visible" when the browser
  isn't mounted so no premature affordance shows.
- `lib/screens/void_screen.dart`: the crumb's condition became "parent folder differs **or** the
  playing track is in this folder's track list but its row isn't visible", gated behind a
  post-first-frame `visibilityProbeReady` flag. It also relabelled the button from
  `jump to now-playing folder` to `scroll to now-playing track`, and bumped `rebuildTick` after
  `scrollToTrack` so the glyph drops once the row lands. Activation reuses the existing
  `jumpToNowPlaying`, which already skipped `loadFolder` when the folder was correct.

It got `flutter analyze` to clean and iterated until all 40 `void_screen_test.dart` tests passed,
including the existing B-015/B-031 jump-glyph tests it initially broke. For runtime proof it launched
the Linux build, navigated to the fixtures folder, played `01-undercover-49.opus`, shot
`before_out_of_view2.png`, tapped `void-crumb-jump-to-playing`, and shot `after_in_view2.png`. That
one before/after pair is the entirety of its runtime verification — it never checked the no-track
state, never browsed a different folder while playing, and never read `getLibraryState`, the widget
tree, or the semantics tree after activating.

## What I verified myself

I drove the still-live container directly (`DISPLAY=:99`, the candidate's own
`flutter_run_nothingness_linux_debug.log` session) and captured 13 labelled `judge-verify.py`
bundles. `getSemantics` is fully available on this build, which made the crumb node readable even
though the widget tree truncates past the 128 k cap before reaching it. The list is a reverse
`ListView` of 11 children (10 tracks + the `..` row) with a 255.8-logical-px viewport and 41 px rows,
so a fresh `nav` resets to offset 0 and leaves tracks 44–47 off-screen.

**E1 (cross-folder) — met.** With track 47 playing and the browser at `/opt/nothingness`, the crumb
carried the affordance. Tapping it left the browser at `/opt/nothingness/media` with 47's row at
y 103.4–144.4 inside the 0–255.8 viewport, and the affordance correctly cleared.

**E2 (same folder, row scrolled out) — partial.** On the route the rubric prefers it works exactly as
specified: freshly loaded media folder at offset 0 with 47 playing and off-screen, affordance present,
and activation kept `currentPath` byte-identical while centring the row. But the predicate is
evaluated only inside the crumb's `Selector` builder, so it is never re-read when the list scrolls.
After a real X11 wheel scroll (XTEST, button 5) pushed 47 back fully off-screen in the same correct
folder — 47 still playing at position 7.4 s, visible rows 49–54 + `..` — the affordance was gone
from the semantics tree entirely. That is E2's own falsifier on the more natural user path, so half
the expectation holds and half doesn't.

**E3 (not active when the row is fully visible) — unmet, and this is what caps the run.** Starting
from the affordance-shown state, two wheel clicks up put 47's row at y 29.8–70.8, fully inside the
viewport with neither edge clipped (confirmed on the screenshot, not just the rects). The crumb still
carried `scroll to now-playing track` with `actions: tap` / `flags: isButton`, and it was genuinely
live: tapping it re-centred the list from offset 106.0 to 183.6. Same root cause as the E2 gap — the
condition goes stale in both directions because nothing re-evaluates it on scroll. Note the
implementation would also treat a merely half-clipped row as "visible" (`Rect.overlaps`), which the
rubric explicitly says should still expose the action.

**E4 (nothing playing) — met.** With `songInfo` null, both `/opt/nothingness/media` and
`/opt/nothingness` showed zero `jump`/`now-playing` hits in the semantics tree *and* the widget tree.

**E5 (accessibility) — met.** The active affordance is a real semantics node with `tap`, `isButton`,
and a distinguishing label. Worth flagging for later tasks: the label merges into the crumb's own
node alongside the path text (`"/opt/nothingness/media / scroll to now-playing track / ⊙"`) rather
than standing alone, so a screen reader reads them together.

**E6/E7 (screenshots) — both met, both genuine.** I reproduced the candidate's exact pre- and
post-activation states live and they match its images pixel-for-pixel: before shows 49 playing with
only a ~6 px sliver of its 41 px row at the list's top edge and the affordance present; after shows 49
fully visible and highlighted, crumb path unchanged, affordance gone. Both are real `drive.py shoot`
captures recorded in the event stream at 1278×720. The before state is a near-fully-clipped row rather
than a wholly absent one, which per the rubric's own boundary clause still counts as "not visible".

**E8 (traceability) — partial.** Its write-up asserts the action appears "only when a track is
actively playing" and when "the playing track's parent folder differs". Neither has any supporting
observation anywhere in the session; both happen to be true, but it never looked.

**E9 (no regressions) — met.** Real on-screen taps still navigate (`void-up` → `/opt/nothingness`,
the folder row back again), an on-screen track-row tap started playback with a 10-track queue, and
`next`/`prev`/`pause`/`resume` all behaved. `prev` holding position when >3 s into a track is the
fixture's own documented `_onPrevious` restart rule, not a regression — it stepped back correctly
when I retested under 3 s.

**E10 (stability) — met.** `overflows` count 0 before and after, app responsive throughout, and the
flutter log holds no framework exceptions — only container noise (EGL/DRI3, ALSA has no card) and a
benign SoLoud `fileAlreadyLoaded` from replaying the same fixture.

## Verdict

`partial`, raw 0.8, no intervention penalty. Seven met, two partial, one unmet. The shape of the
result: the model correctly identified the harder case the prompt was pointing at, wrote a genuinely
reasonable visibility probe, kept the existing tests green, and produced honest screenshots — but it
wired the probe into a builder that only reruns on playback and folder changes, so the "conditional"
half of the ask is right only at the instant the folder loads. One judging trap worth recording: my
first attempt at the E2 scroll probe read as "affordance absent" when in fact the 174 s track had
simply ended, so I redid it with `isPlaying` and `songInfo` captured in the same bundle as the
semantics read.
