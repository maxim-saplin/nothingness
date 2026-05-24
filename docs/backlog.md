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

## B-012 (minor): No tap/swipe affordance on hero or transport buttons

**Symptom**: Tapping the hero or transport buttons (play / prev / next) gives
zero visual feedback at the moment of touch — the only change is the play
icon swap, ~200 ms later. Horizontal hero swipe for prev/next is equally
silent.

**Repro**: Captured three frames around an `adb shell input tap 540 388`
on the spectrum hero. Pre-tap and during-tap PNGs were
**byte-identical**; post-tap (200 ms) differs only because the play→pause
icon had flipped. Confirmed `MediaButton`
(`lib/widgets/media_button.dart:34-35`) uses a plain `GestureDetector` —
no `InkWell`, no Material ripple — and the hero surface
(`lib/screens/void_screen.dart:515-529`) uses `HitTestBehavior.opaque`
with no `Material` ancestor either.

**Desired**: Immediate touch-down indication everywhere a tap or swipe is
accepted. Keep it monochrome / typography-driven to fit the Void
aesthetic — e.g. a brief opacity dip on the button glyph, a 100 ms ring
ripple under the tap point on the hero, or a directional flash for
horizontal swipes.

**Area**: chrome / heroes / transport

---

## B-013 (minor): Search input font too small; close is a tiny faded ×

**Symptom**: Entering search mode shrinks the input to `typography.crumbSize`
(same as the path readout) — noticeably smaller than the search-result
rows above it. Close is a single `×` glyph in `fgTertiary` (low-contrast)
at the row end; easy to miss.

**Repro**: long-press the crumb, type `the`. Screenshot at
`.tmp/agent_shots/search_the.png` (this session): the input "? the" reads
visibly smaller than each result row beside it, and the × glyph is
identical to the result-row dividers in tone.

**Desired**: Bump the search input to at least `typography.rowSize` (the
same size as the result rows). Make dismissal more discoverable: enlarge
the × hit target without changing the visual weight, accept swipe-down on
the crumb as a dismissal gesture, and confirm `_onSearchFocusChanged`
(`lib/screens/void_screen.dart:215-222`) really collapses search on
focus-out (it does, but only when the query is empty — that may also be
worth relaxing).

**Notes**: `_buildSearchCrumb` lives at
`lib/screens/void_screen.dart:579-613`.

**Area**: chrome / search

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

---

## B-016 (minor): Settings sheet has no at-a-glance status

**Symptom**: Opening settings drops the user straight into the MODE group.
No queue size, no shuffle state — both require leaving settings to check.

**Repro**: Screenshot `.tmp/agent_shots/settings_top.png` — header reads
`< settings`, then MODE → operating mode. Nothing surfaces queue length
or shuffle.

**Desired**: A non-scrolling status strip above the MODE group:
- queue size (e.g. `queue · 47 tracks`)
- shuffle toggle (live; toggling here calls
  `AudioPlayerProvider.shuffleQueue` / `disableShuffle`)

**Notes**: Header lives at `lib/widgets/void_settings_sheet.dart:858-891`.
Insert the new row between `_header` and the first `_groupHeader`. Use
`_toggleRow` for shuffle to match existing visual language. There is no
shuffle row anywhere else in settings today — confirmed by reading the
full `_buildGroups` method.

**Area**: settings

---

## B-017 (major): Mic permission blocks the library in OWN mode; raise min SDK to 29

**Symptom**: First-launch "tap to grant" gate requests microphone alongside
storage/audio — but worse, **denying mic blocks the entire library** even
when storage was granted.

**Repro** (code-only — fresh install needed for an end-to-end repro):
`LibraryController.requestPermission`
(`lib/controllers/library_controller.dart:220-235`):

```dart
final statuses = await [
  Permission.storage,
  Permission.audio,
  Permission.microphone,  // line 229 — bundled into the OWN-mode gate
].request();

hasPermission =
    (statuses[Permission.storage]!.isGranted ||
        statuses[Permission.audio]!.isGranted) &&
    statuses[Permission.microphone]!.isGranted;  // line 235 — blocks library
```

So if the user denies the surprise mic prompt, the library is
unreachable in OWN mode even with storage granted. Mic is not used in
OWN mode — it's a BACKGROUND-mode dependency for audio capture.

**Desired**:
1. **Raise `minSdkVersion` to 29 (Android 10)** in
   `android/app/build.gradle.kts`. With API 29 as the floor, scoped
   storage is universal, and `Permission.audio` (which
   `permission_handler` maps to `READ_MEDIA_AUDIO` on 33+ and to
   `READ_EXTERNAL_STORAGE` on 29–32) covers the library on every
   supported version. **Drop `Permission.storage` from the request and
   from the manifest's `READ_EXTERNAL_STORAGE`** — note that on 29–32
   `Permission.audio` will request the legacy `READ_EXTERNAL_STORAGE`
   under the hood, so the manifest entry may still be needed depending
   on `permission_handler` internals; verify before deleting.
2. Drop `Permission.microphone` from the OWN-mode gate. Mic is
   BACKGROUND-only.
3. Make `hasPermission` depend only on the audio permission.
4. Surface mic + notification-listener requests behind explicit buttons
   in settings (the EXTERNAL group already has both for BACKGROUND mode
   at `lib/widgets/void_settings_sheet.dart:527-546`). They only appear
   in BACKGROUND today — that's correct; leave it.
5. Keep `MediaControllerPage._ensureBackgroundPermissions`
   (`lib/screens/media_controller_page.dart:203-219`) as the BACKGROUND
   path — already gated on `_operatingMode == background`.

**Notes**: Also re-check the OWN-mode `_checkPermissions` path
(`lib/screens/media_controller_page.dart:265-267`) which silently
requests `POST_NOTIFICATIONS`. That one is reasonable (lock-screen
controls need it on API 33+); just document the intentional split.
Current manifest has both `READ_EXTERNAL_STORAGE` and `READ_MEDIA_AUDIO`
— prune the former if step 1 verification allows.

**Area**: permissions / build

---

## B-018 (minor): Define a per-skin transport-row contract

**Symptom**: There is no shared convention for how each hero integrates the
chrome's transport row. Polo opts out entirely (bespoke LCD-style
controls); Spectrum, Dot, and Void all *can* respect the global
`transport` setting, but each has its own implicit layout assumption
about how much vertical room the transport row consumes and where it
sits relative to hero content. With `transport: off`, some heroes
(Dot in particular) end up with no on-screen controls at all and no
song info either.

**Repro**: Screenshot `.tmp/agent_shots/dot_top_transport.png` — Dot with
transport `top` renders the prev/play/next row beneath the pulsing dot.
At `transport: off` the Dot screen becomes "just a dot" with no controls
and no metadata, hero gestures only.

**Desired — transport contract**:
1. Each hero declares whether it **hosts** the chrome transport row
   (Spectrum, Dot, Void) or is **bespoke** (Polo). Hosted heroes are
   subject to the global `transport` setting (`top` / `bottom` / `off`).
2. Hosted heroes lay out their content within a guaranteed *hero band*
   (the region above the transport when `bottom`, below it when `top`,
   the full hero area when `off`). The shell allocates the transport
   slot; the hero never has to know its exact height.
3. `VoidScreen` (the shell) is the single owner of transport-row
   placement; heroes do not paint their own transport. Polo is the only
   exception and stays exempt.

**Implementation sketch**:
- Add a `bool ScreenConfig.hostsChromeTransport` (or equivalent) so the
  shell knows which heroes participate. Polo returns false; the others
  return true.
- The transport-position branch in `lib/screens/void_screen.dart:406-416`
  already does the placement work — extend it to gate on
  `hostsChromeTransport`, and pass the hero band size into the hero
  through `LayoutBuilder` constraints so the hero doesn't guess.

**Notes**: This is foundation for B-020 (Dot song info toggle) — both
features want the hero to honour a stable band given to it by the shell.

**Area**: heroes / chrome / transport

---

## B-019 (minor): Crumb and browser rows truncate the tail

**Symptom**: When text doesn't fit the row width, Flutter's default
`TextOverflow.ellipsis` clips the **end**. For the crumb this hides the
current folder name; for browser rows this hides the rest of the song
title. Both are the more informative end.

**Repro**: `drive.py call ext.nothingness.setSetting name=uiScale value=2.5`
→ navigate to `/storage/emulated/0/Music/Russian Rock`. Screenshot
`.tmp/agent_shots/crumb_scaled.png` shows:
- Crumb: `/storage/emulated…` — current folder gone.
- Browser rows: `Ария - Бесп…`, `Кино - Груп…` — song titles
  truncated to the artist + the start of the title.

**Desired**: Adopt a consistent "keep the meaningful tail" policy across
the chrome:
- Crumb: head-truncate, `…/Music/Russian Rock`.
- Browser file rows: head-truncate, `…бесп ангел`. (Folder rows are
  usually short enough not to matter, but the same rule should apply
  for safety.)
- Implement once as a small `MidEllipsis` widget that takes a
  `keepEnd` length hint, used by both call sites.

**Notes**:
- Crumb: `lib/screens/void_screen.dart:563-572`.
- Browser file rows: `lib/widgets/void_browser.dart:553-562, 469-487`
  (search result rows have a similar issue at lines 458-487).
- Watch RTL: the same trick that keeps the tail in LTR will keep the
  head in RTL, which is what RTL users actually want — so the
  implementation should respect ambient `TextDirection`.

**Area**: chrome / crumb / browser

---

## B-020 (minor): Toggleable song info on Dot screen

**Symptom**: Dot screen renders only a pulsing dot. The currently-playing
track's title and parent folder are invisible — the user can't see what
is playing without leaving the screen or watching the lock-screen
notification.

**Repro**: Screenshot `.tmp/agent_shots/dot_top_transport.png` —
empty above the dot, empty below it (transport row aside). No metadata
anywhere.

**Desired**: A toggleable song-info overlay for Dot, the same fields that
Spectrum and Void show (title, parent folder). Default off (preserves
the minimalist identity). Toggle lives in DISPLAY group of settings
under the Dot config, alongside the existing sensitivity / max size /
opacity sliders (`lib/widgets/void_settings_sheet.dart:734-806`).

**Implementation sketch**:
- Extend `DotScreenConfig` with `bool showSongInfo` (default false).
- In `DotHero`, when `showSongInfo == true`, render the same widget
  that Spectrum uses for title + parent folder, positioned within the
  hero band (per B-018).
- Add a `_toggleRow` for `show song info` to `_buildDotDisplayRows`
  (`lib/widgets/void_settings_sheet.dart:734`).

**Notes**: Cross-ref B-018 (transport contract) — both features want the
hero band to be a stable, shell-allocated rectangle. Build B-018 first
if both land in the same arc, otherwise B-020 has to assume layout it
will later have to redo.

**Area**: heroes / dot
