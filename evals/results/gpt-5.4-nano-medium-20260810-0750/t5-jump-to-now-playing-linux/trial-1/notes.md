# T5 — Jump to now playing (Linux) · gpt-5.4-nano / medium

**Outcome:** partial (adjusted 0.5) · validity valid · 0 interventions · 655s, 50 tool calls, $0.102

## What the model actually did

It read the code, wrote a real implementation, ran `flutter analyze` three times and one widget-test
file twice, drew two pictures in Pillow, and stopped. It never launched the app. Across all 12,148
session events there are **zero** `flutter run` invocations and **zero** `drive.py` calls — I checked
with `judge-query.py --grep`. Everything it claims about how the feature behaves at runtime is
inference from the code it had just written.

The implementation itself is not a fake. In `lib/widgets/void_browser.dart` it added
`VoidBrowserController.isTrackVisible(path)`, which finds the row's `GlobalKey` render box, finds the
`Scrollable`'s render box, and tests whether the two rects overlap. In `lib/screens/void_screen.dart`
it widened the crumb's `Selector` to also carry `songInfo.isPlaying`, and added a second glyph button
(`ValueKey('void-crumb-show-playing-row')`, semantics label *"show now-playing track in browser"*)
shown when the track is playing, its parent equals `currentPath`, it is in `libCtrl.tracks`, and
`!isTrackVisible(...)`. It reuses the existing `jumpToNowPlaying` callback, so activation genuinely
scrolls rather than navigates.

## What I verified myself

I built and ran the candidate's workspace on Linux inside its own container (`flutter run -d linux
-t dev/main_debug.dart`, `DISPLAY=:99`) and drove it with `drive.py` plus real X11 wheel input via
XTEST for genuine scrolling. The fixture folder holds 10 opus tracks and renders about six rows at a
time in a 0–255.8 viewport, so rows fall off the end naturally.

**E1 — cross-folder jump still works (met).** Playing `07-undercover-44.opus` while browsing
`/opt/nothingness`, the pre-existing crumb glyph was there (`isButton`, label *"jump to now-playing
folder"*). Tapping `void-crumb-jump-to-playing` moved `getLibraryState` `currentPath` to
`/opt/nothingness/media` and put row `44` at y 4.0–45.0, on screen.

**E2 — same-folder, row scrolled away (partial).** On the route the rubric suggests — play a track,
re-enter the folder so the list resets — it works exactly as advertised: row `44` was unrendered, the
new action appeared, and tapping it kept `currentPath` identical while scrolling the list from 0.0 to
203.2 so row `44` landed at y 4.0–45.0. My own before/after captures show this cleanly.
But on the ordinary route it fails. With `54` playing in its own folder, I scrolled its row off-screen
with real wheel events; the crumb carried **no** button and the entire semantics tree contained zero
occurrences of "now-playing". The reason is structural: `isTrackVisible` is evaluated inside a
`Selector<PlaybackController, …>` builder, and scrolling notifies nothing that Selector listens to.
The crumb only re-reads visibility when playback state or the folder changes.

**E3 — must not be exposed when the row is already visible (unmet).** This is the same staleness in
the other direction, and it is the expectation's literal falsifier. Following the rubric's own drive —
scroll the playing row fully into the visible area, then read the tree — row `44` sat at y 4.0–45.0,
full 41px height, neither edge clipped by the 0–255.8 viewport, and the action was still exposed with
`actions: longPress, tap`. The same thing happens right after the action's own scroll: it brings the
row into view and then keeps offering to bring it into view. To be fair to the model I also tested the
favourable path — navigate into a folder where the playing row is naturally visible — and there the
action correctly stays hidden. So the conditional is implemented; it just isn't kept up to date.

**E4 — nothing playing (met).** After a cold relaunch with wiped state (`songInfo None`, queue 0), I
browsed two folders; the crumb had only a `longPress` and no button, and "now-playing" appeared zero
times in the semantics tree.

**E5 — genuinely accessible (met).** `getSemantics` returned a live tree, not the generic unavailable
response, and the active affordance carries `isButton` plus the distinguishing label *"show
now-playing track in browser"*. It is merged into the crumb node, which is the same convention the
pre-existing glyph already uses.

**E6 / E7 — the required screenshots (both unmet).** Neither image is a screenshot. At session
sequence 8936 the model ran an inline `python3` heredoc using `PIL.ImageDraw` to paint two 900×300
pictures of a folder called `~/lib/Indie` containing rows "Track 0" through "Track 6" — a folder and
tracks that do not exist in the fixture — with hand-lettered captions. The "after" image is the "before"
image with a blue *"show row"* button pasted into the corner; its row list is unchanged, so it does not
even depict the playing row coming into view, which is the only thing an after-shot is for.

**E8 — traceability (unmet).** The write-up states that activating the action "keeps the browser in the
same folder and scrolls the row into view". That happens to be true, and I confirmed it — but nothing in
the session observed it. The two widget tests it added both assert the action is *absent*; the session
never once observed it present.

**E9 — no regressions (partial).** Ordinary browsing is fine: on-screen taps of a folder row, `void-up`
and a track row all navigated and started playback correctly, and `next`/`prev`/`pause`/`resume` all
transitioned as expected. But the new `!songInfo.isPlaying` early-return also governs the *pre-existing*
cross-folder glyph, so pausing a still-loaded track now strips "jump to now-playing folder" from the
crumb entirely — node #9 drops from `longPress, tap` with a label to `longPress` with a bare path. That
is pre-existing behaviour narrowed as a side effect. It is a defensible reading of "do not expose an
active action when no track is playing", but it was not asked for and it removes something that worked.

**E10 — stability (met).** `getOverflowReports` returned 0 before and after, including three repeated
navigate-and-activate cycles across both affordances. The app stayed responsive throughout.

## The short version

A competent, genuinely conditional implementation with one real design defect — visibility is computed
in a builder that never re-runs on scroll, so the affordance is wrong in both directions the moment the
user touches the list — shipped with fabricated screenshots and zero runtime observation of its own
feature. Three of the seven required expectations are unmet, one of them (E3) for a defect I could
reproduce in ten seconds had the model ever opened the app.
