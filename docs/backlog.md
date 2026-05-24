# Backlog

Single-file issue tracker for in-flight UX/bug work on `main`. Continues the
`B-NNN` numbering from the closed `ui-revamp` arc (last id was B-010).

## Conventions

- One H2 per issue: `## B-0NN (severity): title` — severity is `minor` /
  `major` / `blocker`.
- Body uses these fields (omit any that don't apply):
  - **Symptom** — what the user observes.
  - **Repro** — exact sequence (driver commands welcome) plus the runtime
    evidence we collected (numbers, screenshots, logcat snips).
  - **Desired** — what we want it to do.
  - **Notes** — code pointers (`path/to/file.dart:line`), constraints,
    cross-refs (`see B-0NN`).
  - **Area** — short tag (`chrome`, `search`, `transport`, `permissions`,
    `browser`, `heroes`, `settings`).
- When an item is fixed, **move the entry to `backlog_done.md`** and append
  a `**Closed**: YYYY-MM-DD — one-line summary of the resolution (commit
  hash if useful)` line at the bottom of the moved entry. Keep the trail —
  it's cheap to read and pays off when a regression looks familiar.
- New ids are assigned monotonically across both files. Don't reuse closed
  ids; check `backlog_done.md` too when picking the next id.

---

## B-008 (minor): Choreographer skips ~140 frames at cold launch

**Symptom**: First frame logs `Choreographer: Skipped 140 frames` — cold
launch is visibly janky on slower devices.

**Cause**: Sequential bootstrap before `runApp` (settings load, audio
session init, SoLoud init) runs on the platform thread, starving frame
production.

**Desired**: Defer non-essential init behind a post-frame callback or a
splash widget so the first frame paints before settings/audio init
completes. Acceptable to show a black void for ~one frame.

**Area**: bootstrap / chrome

---

## B-011 (major): Play/pause feels delayed on Android

**Symptom**: Tapping play/pause (hero or transport row) takes ~half a second
to start audio. With no visual confirmation (see B-012) the gesture reads as
ignored.

**Repro**: On emulator-5554 (x86_64, debug):
```
.../drive.py pause; sleep 1; .../drive.py resume
```
Logcat shows `MediaSessionService onSessionPlaybackStateChanged …
state=PLAYING` ≈ 500 ms after the RPC fires. RPC itself (`drive.py resume`,
which mirrors what an in-app `playPause()` does on Android) returns in
~500–700 ms across three runs. Optimistic UI flip is already in place
(`PlaybackController.playPause` at
`lib/services/playback_controller.dart:464,469`), so the lag the user feels
is the AudioHandler → AudioService → SoLoud chain, not the Dart state.

**Desired**: Profile each hop (`NothingAudioHandler.onPlay`,
`audio_service` plugin glue, native `AudioFocus`, SoLoud `play`) and shrink
whichever dominates. If the chain is irreducible, lean on B-012 to mask the
gap.

**Notes**: Cross-ref B-012 (visual feedback) and B-018 (per-skin transport).

**Area**: transport / playback

---

## B-014 (major): Search results destroy the queue; needs sub-queue model

**Symptom**: Tap a result while searching → the queue becomes a one-track
list (just the result). When the track ends, playback simply stops; the
other search results are gone.

**Repro**: queue contained two indie tracks. Searched "the" → two results
("The Strokes – Last Nite", "The Offspring – Pretty Fly"). Tapped the
first. Immediately after:
```
queueLength = 1
queue = ["The Strokes - Last Nite"]
isPlaying = True
```
The Offspring result is unreachable — playback dead-ends at the natural
end.

**Root cause**: `VoidBrowser._playOneShot`
(`lib/widgets/void_browser.dart:628-631`) calls `playOneShot`. On Android
the provider (`lib/providers/audio_player_provider.dart:285`) drops back
to `setQueue([track])` because the Android handler doesn't implement
one-shot, *destroying the prior queue in the process*. On non-Android,
`PlaybackController.playOneShot`
(`lib/services/playback_controller.dart:815`) preserves the prior queue
and resumes at `index+1` on natural end — but the search-results list is
still discarded.

**Desired — sub-queue model**:
- Search is **global** across the library (already true since B-009).
- Tapping a result installs the **search results list as a sub-queue**
  injected into the current queue, with the tapped track as the active
  item. Subsequent results play in order.
- **Closing search** (× or back) restores the *original* queue. The
  currently-playing track keeps playing until natural end or user skip,
  then playback resumes the restored queue from where it was.
- If the currently-playing track is itself a search result match, the
  search list **includes it** so the user can identify and tap it
  (no-op or restart — pick one). Document this in the help/About sheet.

**Implementation sketch**:
- Add a "search session" notion to `PlaybackController` that snapshots
  the prior queue + currentIndex, installs a new queue derived from
  search results, and restores on close.
- Surface a help row (`HelpScreen`) explaining the sub-queue behaviour
  and the "tap your current track in search" affordance.
- Add a new explainer paragraph to `HelpScreen` covering the search
  model.

**Area**: search / playback

---

## B-015 (major): Browser doesn't follow now-playing; needs explicit jump

**Symptom**: When playback moves to a track in a different folder than the
one the user is browsing (shuffle, auto-advance, recursive shuffle), the
browser does not navigate to that track's folder and does not highlight
any row. There is **no user-driven way to ask "take me to what's
playing right now"** without manually walking the tree.

**Repro**: long-press `Indie` from `Music/` → recursive shuffle. Player
starts with `Arcade Fire – Wake Up`. `drive.py up` walks the browser back
to `Music/`. Hit `next`:
```
playback.currentIndex = 1
playback.songInfo.title = "The Strokes - Last Nite"
library.currentPath = "/storage/emulated/0/Music"
```
Screenshot `.tmp/agent_shots/after_next.png` shows the browser at `Music/`
with no highlighted row — the now-playing track is in `Indie/`, off the
visible list entirely.

**Decision**: **No auto-follow.** Auto-navigating on every track change
would fight users who deliberately browse elsewhere. Instead, add an
explicit "jump to now-playing" affordance.

**Desired — explicit jump interaction (proposal)**:
- Show a small glyph in the crumb (right-aligned, near the existing
  text) whenever
  `dirname(songInfo.track.path) != library.currentPath`. Suggested
  glyph: `⊙` or `↩` in `fgSecondary`.
- Tapping the glyph: `loadFolder(dirname(songInfo.track.path))`
  followed by `Scrollable.ensureVisible` on the now-playing row, with
  alignment ≈ 0.5 (centered).
- When `dirname(...) == currentPath`, the glyph is hidden — so the
  control only appears when there's somewhere to go. This makes it
  discoverable when the user actually needs it.
- Alternative entry point: tap the parent-folder label that already
  appears under the title in the song info display (e.g. "Indie" in
  the screenshots) — same action. Both can coexist; pick one if
  duplication feels noisy. Note: this alternative depends on the hero
  rendering song info, so it doesn't work in Dot until B-020.

**Notes**: `VoidBrowser` has no `ScrollController` today; its list is
`reverse: true` (`lib/widgets/void_browser.dart:283-289`). Scrolling
needs a controller + `Scrollable.ensureVisible` on the row's key
(alignment math is inverted by the reverse axis).

**Area**: chrome / browser / playback
