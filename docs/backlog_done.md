# Backlog — Closed

Items moved here when fixed. Append-only trail for regression context and
extraction-just-in-case. See [`backlog.md`](backlog.md) for open items and
the shared conventions.

Each closed entry preserves its original H2 (`## B-0NN (severity): title`)
and body, plus a `**Closed**: YYYY-MM-DD — summary` line at the bottom.

## B-033 (major): Swipe-up browser pops without animation; jump glyph + drag handle invisible on real hardware

**Symptom**: Three concrete user-reported failures on real-device install
after B-030..B-032 landed:

1. **Browser open/close pops with no animation.** Settings sheet has a
   nice slide-in; the swipe-up browser just appears/disappears
   atomically. The Positioned widget that holds the browser is
   conditionally rendered (`if (!browserCollapsed)`); there's no
   `AnimatedPositioned`, `AnimatedSlide`, or transition tween on the
   `_browserExpanded` flip. Verified in `lib/screens/void_screen.dart`
   ~line 487.
2. **Jump-to-now-playing glyph hard to see.** `_buildJumpGlyph` renders
   `⊙` at `typography.crumbSize` (~13 px) in `palette.fgSecondary`
   (mid-gray). A tiny low-contrast character in a 44×44 hit target.
   "Most of the time I don't see the icon."
3. **Drag handle invisible.** B-032 spec'd 32×4 px in `fgTertiary` —
   that's a thin dark pill on a dark background. Combined with the
   missing slide animation (point 1), the user has no visual cue that
   the browser can be pulled down to close.

**Desired**:
1. **Animate the browser presentation**: replace the conditional
   `Positioned(...)` with an `AnimatedPositioned` (or wrap in
   `AnimatedSlide`) that tweens the browser's top/bottom edges over
   ~280 ms with `Curves.easeOutCubic`. Same direction in both modes —
   slides up from the bottom of the screen on expand, slides back down
   on collapse. The hero's height interpolates in lockstep so there's
   no layout pop. Match the feel of the settings sheet open animation
   (whatever its duration/curve is — find it and reuse).
2. **Bump glyph visibility**: render the `⊙` at `typography.rowSize`
   (matches search-input bump from B-013) in `palette.fgPrimary` (full
   contrast) — same hit target. Optionally add a subtle background
   circle in `palette.fgPrimary.withAlpha(40)` for further visibility.
3. **Bump drag handle**: 40 px wide × 6 px tall, `palette.fgSecondary`
   (mid contrast, was fgTertiary), top/bottom margin 10 px. Sits
   centered above the crumb. Visible even on darkest backgrounds.

**Validation note**: the user's previous build may have predated B-031
and B-032 — confirm via reinstall before judging. But the three fixes
above are correctness regardless of which build they're on.

**Area**: chrome / browser / heroes

**Closed**: 2026-05-25 — AnimatedPositioned slide for swipe-up browser (280 ms easeOutCubic); jump glyph bumped to rowSize/fgPrimary; drag handle bumped to 40×6 in fgSecondary.

## B-032 (minor): Browser needs a drag-down-to-close affordance

**Symptom**: With swipe-up browser presentation, the browser opens via
upward swipe but the only documented close gesture is Android Back,
which is unintuitive. The crumb's `×` (for search) and the back button
are both available, but neither is discoverable from the browser open
state. Users learning the app expect the browser to close by pulling it
back DOWN, the way it opened.

**Desired**:
1. Add a small drag handle at the top of the open browser — a thin
   horizontal pill in `fgTertiary`, centered, ~32 px wide × 4 px tall,
   placed above the crumb. Telegraphs the drag-down gesture.
2. Vertical-drag-DOWN on the non-scrolling regions of the browser
   closes it. Non-scrolling regions include:
   - the drag handle itself,
   - the crumb area (path readout + glyphs),
   - the search bar when active,
   - any gap between crumb and the start of the scrollable list.
3. Threshold: same pattern as B-027's velocity escape — fire on EITHER
   distance > ~60 dp OR velocity > 300 dp/s. Use Flutter's
   `onVerticalDragEnd` velocity sign for direction.
4. Back button still closes (don't remove that path — `_onPopInvoked` in
   `void_screen.dart` covers it per B-007).
5. The browser's scrollable list MUST NOT be affected — vertical drags
   inside the list keep scrolling the list, not closing the browser.

**Notes**: `lib/widgets/void_browser.dart` for the drag handle + crumb
region; `lib/screens/void_screen.dart` for the swipe-up presentation
state and the close path the gesture should call. Don't conflict with
the swipe-up open gesture (it lives on the home screen, not the open
browser).

**Area**: chrome / browser

**Closed**: 2026-05-25 — drag handle + vertical-drag-down close gesture on browser non-scrolling regions; back button preserved; fixed presentation untouched.

## B-031 (major): Jump-to-now-playing glyph is unreliable

**Symptom**: User report from real-device install. Three concrete failure modes:

1. The crumb's `⊙` glyph sometimes disappears unexpectedly — a brief race
   between `library.currentPath` and `playback.songInfo` updates makes
   `dirname(songInfo.path) == currentPath` true for a frame, so the glyph
   hides even when there's still somewhere to go.
2. When the browser is **closed** (swipe-up presentation, browser hidden
   until the user pulls up), tapping the glyph fires `loadFolder` but
   the user sees nothing — the browser is off-screen, so the navigation
   and any subsequent `ensureVisible` have no visible effect.
3. When the browser is open, the now-playing row often isn't actually
   scrolled into view. `_jumpToNowPlaying` does `loadFolder` →
   `await endOfFrame` → `Scrollable.ensureVisible` on a per-row
   `GlobalKey`. One frame isn't enough for the SliverList to lazy-build
   the target row in long folders; `ensureVisible` finds no
   `RenderObject` and silently no-ops. B-015's implementer flagged this
   exact case as a follow-up.

**Desired**:
1. **Stabilize glyph visibility**: hold a 150-200 ms debounce before
   hiding the glyph — if `dirname(songInfo.path) != currentPath` again
   within the window, never flip.
2. **Open the browser when closed**: if the browser is in swipe-up
   presentation and currently dismissed, the jump action should first
   open it (slide-in), THEN navigate + scroll. Reuse the existing
   browser-open path.
3. **Scroll reliably**:
   - Compute the target row's INDEX in the new folder's tracks (post
     `loadFolder`).
   - `await` until that index is laid out: pump frames until either the
     row's `GlobalKey.currentContext` exists OR a max wait elapses
     (~500 ms with a couple of `endOfFrame`s).
   - Then call `ensureVisible` (still with `alignment: 0.5`).
   - If the row never builds, fall back to `ScrollController.animateTo`
     using `itemExtent * index` as the estimated offset.

**Notes**: `lib/screens/void_screen.dart` `_jumpToNowPlaying` (per
B-015); `lib/widgets/void_browser.dart` `VoidBrowserState.scrollToTrack`
(per B-015); browser open/close logic lives in `void_screen.dart`
(swipe-up presentation gate). Reuse existing animation paths; don't
introduce a new one.

**Area**: chrome / browser / playback

**Closed**: 2026-05-25 — glyph debounced 200 ms; tap opens browser when closed; scroll-by-index with frame-pumping + animateTo fallback for long folders.

## B-031 (minor): Expose Android intents for play/pause automation

**Symptom**: No third-party automation surface — MacroDroid/Tasker
cannot start the app and toggle playback. The user wants two macros
(BT device connected → resume, BT device disconnected → pause) and
today must reach for the app by hand on every BT toggle.

**Desired**: Three exported actions on `MainActivity`, dispatchable via
`am start -a <action>` (and from MacroDroid's "Send Intent → Activity"):

- `com.saplin.nothingness.action.PLAY` — resume if paused.
- `com.saplin.nothingness.action.PAUSE` — pause if playing.
- `com.saplin.nothingness.action.PLAY_PAUSE` — toggle.

**Notes**: Intents arrive at `MainActivity` (singleTop), are decoded in
Kotlin, and pushed to Dart via a new
`com.saplin.nothingness/automation` MethodChannel. Dart side dispatches
against `AudioPlayerProvider.playPause()`, gating on `isPlaying` —
mirrors `ext.nothingness.play/pause` semantics
(`lib/testing/agent_service.dart:423-441`). Cold-start delivery uses a
pending-action buffer drained by Dart on startup; warm-start uses
`onNewIntent` → `invokeMethod` push.

**Area**: automation

**Closed**: 2026-05-24 — Added PLAY/PAUSE/PLAY_PAUSE intent-filters on
MainActivity, decoded in Kotlin and forwarded to Dart over a new
`com.saplin.nothingness/automation` MethodChannel. Cold-start drain +
warm-start push both covered; 8 new unit tests in
`test/services/automation_intent_service_test.dart`.

## B-030 (major): No press feedback on most tappable surfaces

**Symptom**: On a real device (not the emulator), tapping a track row in
the browser produces no visible feedback for ~500 ms — then the
now-playing row inverse-color highlight catches up when playback
finally advances. The user reads the half-second of nothing as "the app
ignored my tap". Same for settings rows, search results, help-screen
rows, the crumb glyphs (search-close, jump-to-now-playing). The
MediaButton has a press dip from B-012 but at 80 ms / opacity 0.55 it
is below the perception threshold on real hardware, especially for the
primary play button (the dip is on the whole circle but the strong
accent backdrop doesn't change).

**Root cause**: B-012's scope was hero + transport buttons. Most
tappable surfaces never got touch-down state. `_VoidRow`
(`lib/widgets/void_browser.dart:704-`) is a plain `GestureDetector`
with `onTap` only. Settings sheet rows use bare `GestureDetector` too.
The B-015 "now-playing row highlight" is a *consequence* of playback
state, not a *response* to the user's tap.

**Desired**:
1. A single `PressFeedback` widget that wraps any child and reflects
   touch-down/up/cancel as a perceptible opacity (or other monochrome)
   change. Calibration tuned for real-hardware visibility:
   - Pressed opacity: 0.4 (was 0.55 for MediaButton — too subtle).
   - Fade-in: 120 ms with `Curves.easeOut`.
   - Fade-out (release): 200 ms with `Curves.easeOut` so the dip is
     visible even on very brief taps.
2. Apply `PressFeedback` to every tappable surface:
   - `_VoidRow` in `void_browser.dart` (file rows, folder rows, search
     results, parent row).
   - `_toggleRow` and tappable static rows in `void_settings_sheet.dart`.
   - Help-screen tappable rows in `help_screen.dart`.
   - Crumb glyphs: search-close (`void-search-close`),
     jump-to-now-playing (`void-crumb-jump-to-playing`).
   - Tap-to-grant gate.
3. Re-tune `MediaButton` to the same calibration constants.
4. Bump `HeroFeedbackSurface` tap-ring visibility: `fgSecondary` at
   1.5× current alpha and 2× stroke width so it's actually visible on
   a hand-held device.

**Tests**:
- Widget test for `PressFeedback`: opacity transitions correctly on
  `onTapDown`/`onTapUp`/`onTapCancel`; survives no-op rebuilds.
- Update `_VoidRow` tests (and add coverage if missing) to assert the
  press path lives in the row.
- Re-snap `MediaButton` test to the new pressed-opacity constant.

**Notes**: This is the user-facing followup to B-012 — same idea,
comprehensive scope. The QA prompt template should also be updated to
require the implementer to enumerate every `GestureDetector`/`InkWell`
in the diff context and confirm each has a visible feedback surface.

**Area**: chrome / browser / settings / heroes / transport

**Closed**: 2026-05-24 — PressFeedback wrapper applied to all tappable surfaces; MediaButton + hero tap-ring recalibrated for real-device visibility.

---

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

---

## B-029 (minor): `drive.py reset` kills the live `flutter run`

**Symptom**: `drive.py reset` internally calls
`adb shell am force-stop com.saplin.nothingness` + `pm clear`, which
crashes any attached `flutter run` session with `Lost connection to
device` and forces a 60-90 s rebuild. The SKILL.md note added for
B-021..B-025 warns about `force-stop` and `pm revoke RECORD_AUDIO` but
does not name `reset` directly, so an agent reading the skill can
trigger the hazard via the wrapper without noticing.

**Repro**: surfaced during B-027 implementer work. With flutter run
attached, running `drive.py reset` ended the session and the running
APK reverted to the pre-fix binary.

**Desired**:
1. Update `drive.py reset` to detect a live flutter run session (check
   `/tmp/flutter_run.log` mtime + VM service responding via the cached
   WS URI). If alive, refuse with a clear message; accept `--force` to
   override.
2. Update `.claude/skills/agent-emulator-debugging/SKILL.md` to:
   - Name `drive.py reset` explicitly in the "Do not kill the live
     flutter run" note (point at the `--force` flag).
   - Add a short note that **ADB synthetic-event swipes do not reliably
     hit Flutter's velocity thresholds**, so hero/swipe gestures should
     be verified with `tester.fling` in widget tests rather than chased
     via `adb shell input swipe X1 Y X2 Y duration` (surfaced during
     B-027 live verification).

**Area**: testing / agent-skill / drive

**Closed**: 2026-05-24 — drive.py reset refuses when flutter run alive (--force override); SKILL.md names reset by name and warns about ADB synthetic-event velocity unreliability.

---

## B-028 (minor): Per-screen `screen_config` persistence

**Symptom**: Settings persistence uses a single `screen_config`
SharedPreferences key holding the active screen's config blob. When the
agent (or user) swaps from Dot → Spectrum → Dot, the Dot config is
overwritten with Spectrum's blob during the middle step, so the second
Dot switch loses any non-default fields (e.g. `showSongInfo` from B-020).

**Repro**: surfaced during B-023 QA. Set Dot `showSongInfo=true`; switch
to Spectrum via `ext.nothingness.setSetting name=screen value=spectrum`;
switch back to Dot. The `showSongInfo=true` is gone.

**Desired**: Persist per-screen configs under separate keys
(`screen_config_dot`, `screen_config_spectrum`, `screen_config_polo`,
`screen_config_void`). On `screen` swap, write the OUTGOING screen's
config to its own key, read the INCOMING screen's persisted config (or
default) from its key. Migration: on first read after upgrade, if the
old `screen_config` key still exists, parse its `screenId` and write
the blob to the matching per-screen key, then delete the old key.

**Notes**: Look at `lib/services/settings_service.dart` for the current
load/save paths. B-023's `_resolveScreenConfig` already has a live-
notifier shortcut + persisted-JSON reload — the new keys plug in below
that. Keep the migration small and idempotent.

**Area**: settings / persistence

**Closed**: 2026-05-24 — per-screen `screen_config_<id>` keys + one-shot migration from legacy `screen_config`; cross-skin cycles no longer clobber per-skin fields.

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

**Investigation 2026-05-24**: Tried moving `LibraryService.init`,
`AudioService.init`, and `AudioPlayerProvider.init` behind a post-frame
callback in `_NothingAppState.initState`. 5-run paired comparison on
emulator-5554 (debug, x86_64):

- Baseline-A first-skip [30, 77, 33, 33, 75]; second-skip [184, 168, 174, 160, 153].
- Post-fix first-skip [164, 136, 135, 36, 35] / [129, 139, 180]; second-skip [188, 174, 209, 290, 256].
- Baseline-B (rebuild): first-skip [37, 165, 137, 130, 195]; second-skip [294, 186, 177, 207, 188].
- `Displayed`: ~8s on every variant.

Run-to-run variance on nominally identical baseline builds exceeds the
delta between baseline and post-fix. `runApp` is synchronous after the
deferral, but `AudioService.init` still blocks the platform thread when
it runs post-frame, so total skipped-frame count and time-to-Displayed
do not measurably improve. Working tree restored to clean; no commit
landed.

Real wins likely require: (a) push `AudioService.init` off the platform
thread (upstream `audio_service` plugin change), (b) a splash widget that
keeps the engine in cheap-render mode until init returns, or (c) measure
on real hardware where emulator JIT warmup doesn't dominate. The second
skip-burst (~170-290 frames) is probably `flutter_soloud` native init,
not `audio_service` — worth isolating before another attempt.

**Investigation 2026-05-24 (splash attempt)**: Switched approach to
option (b) above. `main()` is now `void main()` (not `Future<void>`) and
calls `runApp(const _BootstrapApp())` synchronously — zero awaits before
`runApp`. `_BootstrapApp` is a `StatefulWidget` whose first build returns
a bare `ColoredBox(Color(0xFF000000))` (no MaterialApp, no theme, no
fonts, no service lookups). `initState` kicks the heavy bootstrap (Hive,
LibraryService, settings, AudioService, AudioPlayerProvider) into a
`scheduleMicrotask`, then `setState`s once it completes to swap in the
real `NothingApp`.

Switched the measurement signal to Dart-side time-to-first-frame
(`Stopwatch` started at `main` entry, sampled inside
`addPostFrameCallback`) because the prior "Skipped N frames" signal had
too much variance. Hot-restart 5-run paired comparison on emulator-5554
(debug, x86_64):

- Baseline first-frame (ms): [4554, 4568, 4474, 4893, 4810] — median 4568.
- Splash    first-frame (ms): [327, 376, 282, 319, 268] — median 319.
- Delta: -4249 ms (-93%).
- Splash-to-NothingApp swap (ms): [3236, 2719, 2929, 2502, 3661] —
  median 2929, i.e. roughly the original `runApp` time, just now spent
  behind a cheap splash instead of blocking the first frame.

`drive.py inspect` returns valid library/router data after the swap,
confirming the deferred init still completes. Hot-restart isn't a true
cold launch (engine already warm) but the dominant signal — synchronous
plugin init before `runApp` — applies to both. `flutter analyze` is
clean (one unrelated info-level lint pre-existed); 270/270 tests pass;
new `test/main_bootstrap_test.dart` pins the "no awaits above runApp"
invariant structurally.

**Closed**: 2026-05-24 — splash-widget pattern; time-to-first-frame
reduced from 4568 ms to 319 ms (median of 5 hot-restart runs on
emulator-5554, debug build).
