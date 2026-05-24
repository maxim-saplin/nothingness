# Backlog — Closed

Items moved here when fixed. Append-only trail for regression context and
extraction-just-in-case. See [`backlog.md`](backlog.md) for open items and
the shared conventions.

Each closed entry preserves its original H2 (`## B-0NN (severity): title`)
and body, plus a `**Closed**: YYYY-MM-DD — summary` line at the bottom.

## Pre-existing closed items (ui-revamp arc, 2026-05-22 and earlier)

`B-001` through `B-006` and `B-009` were closed during the `ui-revamp` arc
and merged into `main` as commit `4fb5d27` (v3.0.0+40). Their detailed
entries lived in the arc's `bugs.md`, which was deleted at merge time. The
short tags below are sufficient for "have we seen this before?" lookups; if
you need the full original write-up, `git show 4fb5d27~1:bugs.md` (or walk
the `ui-revamp` branch's history) recovers it.

- **B-001** — smart-roots showed the full filesystem.
- **B-002** — gesture-nav overlapped chrome at the bottom edge.
- **B-003** — 54 px immersive transition overflow stripe.
- **B-004** — settings entry-point `·` glyph was too small to hit.
- **B-005** — launch hint was once-only (now shows on every cold launch
  and fades after 3 s).
- **B-006** — background-mode hijacked the screen on first run.
- **B-009** — search scope was limited to `currentPath` instead of the
  whole library.

**Closed**: 2026-05-22 — shipped together in merge `4fb5d27`.

---

## B-007 (minor): Android Back exits Void silently — verify

**Symptom** (historical): Pressing Android Back from `VoidScreen` exited the
app silently. Audio kept playing but UI state was lost.

**Status**: Plausibly already fixed — `PopScope` is wired at
`lib/screens/void_screen.dart:302` with `_onPopInvoked` at line 454
that collapses the swipe-up browser, exits search, then walks the
library tree up before letting the OS pop. **Needs an explicit live
verification** before closing: on the emulator, press Back from various
chrome states and confirm the order above holds.

**Area**: chrome / navigation

**Closed**: 2026-05-24 — verified on emulator-5554, PopScope order holds across all five chrome states (root → background; subfolder → folder up; expanded swipe-up browser → collapse; search mode → exits search after the standard IME-dismiss tap; settings sheet → closes via Navigator pop).

---

## B-010 (major): Rapid `setSetting(themeVariant)` saturates the VM service

**Symptom**: Driving `ext.nothingness.setSetting name=themeVariant ...`
at >15 calls/second over the VM service stops the isolate responding.

**Likely cause**: VM-service RPC saturation, not user-facing logic. The
in-tree widget test `test/p6_adversarial_test.dart` exercises the same
code path at the same cadence in-process and passes.

**Desired**: Either rate-limit the extension handler, or document that the
test agent must throttle. No user-facing fix needed if the diagnosis
holds — but if a user-driven path can reach the same cadence (e.g. a
settings cycle held down with hardware key repeat), we need a real fix.

**Area**: testing / agent-service

**Closed**: 2026-05-24 — diagnosis confirmed on emulator-5554: each `setSetting` RPC costs ~140 ms steady-state (awaits `SharedPreferences.setString`), so sustained send rates above ~7/s back up the response queue. At >500/s pipelined the queue grows beyond reasonable drain timeouts, matching the original "stops responding" symptom; isolate recovers once drained. No user-driven path can reach this cadence: the only write paths are `agent_service._setSetting` and `VoidSettingsSheet._cycleVariant` (tap-only, no hardware-key repeat or timer). Documented the cadence ceiling and recovery in `.claude/skills/agent-emulator-debugging/SKILL.md`; recommended ≤5/s for `setSetting`-style calls, with `test/p6_adversarial_test.dart` as the in-process equivalent for higher cadences.

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

**Closed**: 2026-05-24 — head-truncating widget added; wired into crumb + browser file rows + search result rows.

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

**Closed**: 2026-05-24 — status strip (queue size + shuffle toggle) added above MODE group in void settings sheet.

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

**Closed**: 2026-05-24 — search input bumped to `typography.rowSize` (parity with result rows); × kept at crumb-size/fgTertiary visual weight but wrapped in a 44×44 hit target keyed `void-search-close`; downward fling on the search crumb dismisses (gesture region keyed `void-search-crumb-region`); `_onSearchFocusChanged` now collapses on focus-out regardless of query (and clears the controller) — tap-away ends the session, re-tap resumes.

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

**Closed**: 2026-05-24 — minSdk 29; mic + storage dropped from OWN-mode gate; hasPermission keyed off audio only.

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

**Closed**: 2026-05-24 — transport contract: ScreenConfig.hostsChromeTransport gates chrome transport; Polo bespoke; hosted heroes get hero-band via Expanded.

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

**Closed**: 2026-05-24 — DotScreenConfig.showSongInfo flag + settings toggle; default off.

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

**Closed**: 2026-05-24 — touch-down opacity dip on MediaButton + transport
icons (no Material ripple), tap-ring overlay on the hero surface, and a
directional `‹` / `›` flash when a horizontal swipe trips prev/next. New
`HeroFeedbackSurface` widget owns the hero overlay; transport row replaced
`InkResponse` with a custom `_TouchDownDimmer`. Widget tests added for all
three surfaces.

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

**Closed**: 2026-05-24 — search sub-queue model: results install as session sub-queue, original queue restored on dismiss; help text added.

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

**Closed**: 2026-05-24 — crumb glyph ⊙ jumps to now-playing folder when dirname(playing) != currentPath; centers row via ensureVisible.

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

**Closed**: 2026-05-24 — `SoLoudTransport.play()` was calling
`AudioSession.setActive(true)` on every resume, triggering a redundant
Android audio-focus IPC (~100 ms on emulator) even when the session was
already active from `init()`. Cached the session instance and tracked
activation state so the IPC only fires on transitions (init / resume from
suspend / focus-loss recovery via the interruption stream). Median
play→audible latency on emulator-5554 dropped from ~225 ms to ~107 ms
(profiled across 5 pause→resume cycles in debug builds; SoLoud `setPause`
AAudio stream restart still costs ~80 ms and is native, not Dart-addressable).
Visual feedback from B-012 already masks the residual gap.

---

## B-021 (minor): `requestLibraryPermission` side-channel bundles mic+storage

**Symptom**: After B-017 the production OWN-mode gate is audio-only, but
the QA-only `ext.nothingness.requestLibraryPermission` extension still
calls a list that includes `Permission.microphone` and `Permission.storage`.
QA runs that trigger it see misleading 3-permission dialogs and report
spurious mic prompts.

**Desired**: Drop mic and storage from the side-channel's request list in
`lib/testing/agent_service.dart`. The probe should mirror the production
controller (`LibraryController.requestPermission` → audio-only) so QA
runs see the same gate the user sees.

**Notes**: Surfaced during B-017 QA. The production path is correct; only
the test-extension probe drifted.

**Area**: testing / agent-service

**Closed**: 2026-05-24 — `_requestLibraryPermission` now requests only `Permission.audio` (mirrors `LibraryController.ownModePermissionList`); list exposed as `AgentService.requestLibraryPermissionList` for regression coverage.

---

## B-022 (minor): `setSetting` has no `transport` case

**Symptom**: `ext.nothingness.setSetting` switches `screen`,
`themeVariant`, `operatingMode`, `fullScreen`, `debugLayout`, `uiScale`,
`immersive` — but **not** `transport`. Driving transport position
(top/bottom/off) from the agent requires writing the underlying
SharedPreferences key + a `restart`, which is two extra hops.

**Repro**: B-018 smoke test required this; QA fell back to settings-sheet
tap, which only works when the sheet isn't blocked by F-024.

**Desired**: Add a `transport` case to the switch in `_setSetting`
(`lib/testing/agent_service.dart`). Route it through the same notifier
the in-app settings UI uses for the transport row, so changes propagate
live without restart.

**Area**: testing / agent-service

**Closed**: 2026-05-24 — `setSetting name=transport value=<top|bottom|off>` routes through `SettingsService.setTransportPosition`; chrome updates live without restart.

---

## B-023 (minor): `screen` setSetting clobbers per-skin configs

**Symptom**: `ext.nothingness.setSetting name=screen value=dot` (or any
hero) constructs `const DotScreenConfig()` (and equivalent for other
heroes), discarding any persisted per-skin settings — including B-020's
`showSongInfo`. After a `screen` swap via the agent, the active config
is whatever the constructor literal says, not what's on disk.

**Repro**: surfaced during B-020 QA when toggling `showSongInfo` via
preference then `screen dot` reset it back to default false.

**Desired**: The `screen` case should change the active screen identity
without recreating the screen's config from scratch. Load the persisted
config (or the in-memory one if already loaded) and reapply.

**Notes**: `lib/testing/agent_service.dart` around the `screen` case in
`_setSetting`. Should reuse whatever load path `main.dart` uses on
startup.

**Area**: testing / agent-service

**Closed**: 2026-05-24 — added `_resolveScreenConfig` (live-notifier shortcut + persisted-JSON reload mirroring main.dart's load path); per-skin fields like `showSongInfo` now survive a `screen` swap when a matching config is on disk.

---

## B-024 (minor): `openSettingsSheet` extension hangs the RPC

**Symptom**: `ext.nothingness.openSettingsSheet` awaits
`Navigator.push(...)`. `push` does not complete until the route pops, so
the VM-service call never returns. `drive.py settings open` times out
even though the sheet IS visible on the device.

**Repro**: noticed in B-007 QA (benign stderr leak) and re-confirmed in
B-020 implementer work (forced a tooling workaround).

**Desired**: Detach the push from the await. `unawaited(Navigator.push(...))`
returns immediately, while the route is still scheduled. The extension's
response payload (`{"opened": true}`) can fire right after `push` is
called.

**Area**: testing / agent-service

**Closed**: 2026-05-24 — `_openSettingsSheet` now `unawaited`s the opener and returns immediately; `drive.py settings open` round-trips in ~0.5 s (was: hung indefinitely).

---

## B-025 (minor): `tapByKey` requires the keyed widget to handle the tap

**Symptom**: `ext.nothingness.tapByKey` walks the widget tree for a
`ValueKey<String>` match and then looks for a `GestureDetector` /
`InkResponse` at that node. B-012's `_TouchDownDimmer` carries the
`void-settings-…` keys but the gesture handler is a descendant
(`GestureDetector` inside the dimmer); `tap` errors `no tappable
ancestor`.

**Repro**: B-012 QA hit this trying `drive.py tap transport-play`.
Workaround was raw `adb input tap` at coordinates.

**Desired**: Locate the keyed widget's `RenderBox` and dispatch a
synthetic tap event at its center via `GestureBinding.instance`. This
keeps `ValueKey` as the addressing scheme while letting the actual
gesture handler be anywhere in the descendant subtree.

**Area**: testing / agent-service

**Closed**: 2026-05-24 — `_tapByKey` now (1) walks descendants for a `GestureDetector`/`InkResponse` callback, (2) falls back to synthetic `PointerAdded/Down/Up/Removed` dispatch via `GestureBinding`, (3) keeps the legacy ancestor walk; `drive.py tap transport-play` now toggles playback (live-verified pause).

---

## B-026 (minor): Spectrum sub-pixel overflow at uiScale=2.5

**Symptom**: At `uiScale=2.5` on Spectrum, a RenderFlex reports a 0.453 px
overflow. Visually negligible but noisy in logs and a latent bug if
the rounding error grows on different devices.

**Repro**: `drive.py call ext.nothingness.setSetting name=uiScale value=2.5`,
`drive.py screen spectrum`. `drive.py overflows` (or check logcat) reports
the 0.453 px overflow. At `uiScale=1.0` no overflow.

**Desired**: Find the offending RenderFlex (probably the Spectrum hero's
song-info column) and either wrap the inner child with `Flexible`/
`Expanded`, add `mainAxisSize: MainAxisSize.min`, or round the affected
size up via `ceil`/`floor`. Sub-pixel-stable layout.

**Notes**: Surfaced during B-019 and B-018 QA — not introduced by either.
Pre-existing; would have been a tip-of-iceberg if the rounding grew.

**Area**: heroes / spectrum

**Closed**: 2026-05-24 — `SpectrumHero` outer Column now reserves typography-derived text height (+ small safety buffer) and caps the visualiser slot to remaining space via `floorToDouble()`; the visualiser is hidden entirely when the squeezed slot falls below the threshold needed to host its own bars + labels Column. Live `drive.py overflows` reports zero overflows at `uiScale=2.5` (was: 19+31 px RenderFlex exceptions) and stays clean at `uiScale=1.5`.

---

## B-027 (minor): Hero swipe misses fast-but-short flicks

**Symptom**: B-012 added a 60-dp horizontal-drag accumulator on the hero
to fire prev/next. A short fast flick (e.g. 40 dp in 80 ms) never crosses
the distance threshold and silently does nothing — even though the user
clearly intended a swipe.

**Repro**: `adb shell input swipe 200 1200 350 1200 80` on Spectrum.
Distance 150 px ≈ 50 dp at 1× density. Accumulator never crosses 60 dp.
Compare with PageView's swipe: also tracks velocity, fires when either
distance OR velocity threshold passes.

**Desired**: In the hero's horizontal drag handler, also track the final
velocity. If velocity at end exceeds ~300 dp/s (tune to feel), fire
prev/next even when distance is under 60 dp. Direction is sign of
velocity.

**Notes**: Implementer of B-012 flagged this as a separate ticket. Look
at `lib/widgets/hero_feedback_surface.dart` and the gesture wiring in
`lib/screens/void_screen.dart`.

**Area**: chrome / heroes / transport

**Closed**: 2026-05-24 — velocity escape (>300 px/s) fires prev/next even when drag distance is under 60 dp. `_VoidScreenState._onHeroHorizontalDragEnd` reads `DragEndDetails.primaryVelocity` and routes positive sign → `next()` / negative → `previous()`; a `_horizDragFired` latch guards against double-firing when a single gesture both trips the 60-dp distance accumulator AND ends with high velocity. Six widget tests in `test/screens/void_screen_test.dart` cover: slow short (no-fire), slow long (existing distance fire), fast short rightward + leftward (velocity-escape fire with direction = sign of velocity), low-velocity short (no-fire), and the no-double-fire latch.
