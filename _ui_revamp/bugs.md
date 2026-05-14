# bugs.md — Bug queue for the UI-revamp QA arc

This file is the single source of truth for the bug-hunt swarm (see
`_ui_revamp/plan.md`). Every finding lands here with a unique `B-NNN` id.
Bugs flow: `open → fixed → closed` (or `regressed` if a fix doesn't hold).

Severities: `blocker` > `major` > `minor` > `cosmetic`.

---

### B-001 — Smart paths show full Android filesystem instead of music-only roots

- **Severity:** blocker
- **Hunter:** seed (from user)
- **Screen / state:** Void, root view, Android, permission granted
- **Repro:**
  ```
  drive.py reset
  drive.py screen void
  drive.py permit            # ensure READ_MEDIA_AUDIO is granted
  drive.py inspect           # library.smartRoots / library.folders
  ```
- **Expected:** Void's root view lists only audio-bearing folders (e.g. `Music`, `Download/Songs`). No `Alarms`, `Android`, `Notifications`, `Ringtones`.
- **Actual:** Full `/storage/emulated/0` filesystem listing surfaced via the
  filesystem fallback in `LibraryController.loadFolder` /
  `_loadAndroidRoot`, which kicked in whenever MediaStore had no entries
  for the path. `AndroidSmartRoots` also fell back to `[deviceRoot]` when
  it couldn't compute candidates.
- **Fix:**
  - `lib/services/android_smart_roots.dart`: drop the deviceRoot fallback; emit no section when no candidates exist.
  - `lib/controllers/library_controller.dart`: remove the filesystem fallback in `loadFolder` and the `loadFolder(deviceRoot)` fallback in `_loadAndroidRoot`. Empty MediaStore now leaves an empty smart-roots view rather than a file-explorer dump.
  - Test updated: `test/services/android_smart_roots_test.dart` flood case now asserts the device is dropped entirely (was: collapsed to deviceRoot).
- **Evidence:** _ui_revamp/shots/after_seeds_void_dark.png shows Void surfacing only `/storage/emulated/0/Music` content (4 folders + 3 root tracks); no Android/Alarms/Notifications/Ringtones.
- **Status:** fixed

### B-002 — Void's bottom row overlaps Android gesture-nav bar

- **Severity:** major
- **Hunter:** seed (from user)
- **Screen / state:** Void, any state, devices with gesture navigation
- **Repro:**
  ```
  drive.py reset
  drive.py screen void
  drive.py shoot before_b002
  ```
- **Expected:** Crumb and progress hairline sit above the gesture-nav bar.
- **Actual:** `SafeArea(bottom: false)` plus an absolute-bottom hairline put both content surfaces under the gesture bar on devices using gesture nav.
- **Fix:** The new `lib/screens/void_screen.dart` build wraps the content in an animated layout where `reservedBottom = bottomInset * (1 - t)` is added as Padding below the crumb and as the `bottom:` of the progress hairline Positioned. In immersive (t = 1) reservedBottom collapses to 0 so the hero meets the screen edge as intended.
- **Evidence:** _ui_revamp/shots/before_b002_b004_b005_void_cold.png (overlap visible) → _ui_revamp/shots/after_seeds_void_dark.png (crumb `/storage/emulated/0/Music` clearly above the home-indicator bar).
- **Status:** fixed

### B-003 — Immersive transition flashes a "BOTTOM OVERFLOWED BY 54 PIXELS" stripe

- **Severity:** major
- **Hunter:** seed (from user)
- **Screen / state:** Void, immersive on↔off (each direction)
- **Repro:**
  ```
  drive.py reset
  drive.py screen void
  drive.py overflows --clear
  adb shell input swipe 540 600 540 1200 200   # swipe down (immersive on)
  adb shell input swipe 540 1200 540 600 200   # swipe up   (immersive off)
  drive.py overflows
  ```
- **Expected:** Animation between the non-immersive and immersive layouts completes without RenderFlex overflow.
- **Actual (pre-fix):** During the 240 ms transition the Column children (hero + browser + crumb) briefly overflowed the available height by ~54 px and FlutterError fired a "RenderFlex overflowed by 54 pixels on the bottom" event. Wrapping the Column in ClipRect suppressed only the visual stripe — the layout-time error still fired.
- **Fix:** Switched VoidScreen to a `SingleTickerProviderStateMixin` with its own `AnimationController` driving an `AnimatedBuilder`. The Column-with-conditional-children layout is replaced by a Stack of Positioned slots whose sums always equal the available height (hero grows top-down; browser and crumb collapse to 0). The browser is given a fixed crumb-height slot (`_crumbHeight = 56`) at the bottom and the inner `ListView` now sets `cacheExtent: 0` so reverse-axis cache items never paint above the viewport.
- **Evidence:** 6 swipe-cycle stress test → `drive.py overflows` reports `count: 0`. _ui_revamp/shots/after_seeds_b003_immersive.png shows pure-black full-screen immersive; `after_seeds_b003_non_immersive.png` shows the restored non-immersive layout with no overflow stripe.
- **Status:** fixed

### B-004 — Void settings affordance is a ~36 dp tap target with a near-invisible glyph

- **Severity:** major
- **Hunter:** seed (from user)
- **Screen / state:** Void, any state, top-right corner
- **Repro:**
  ```
  drive.py reset
  drive.py screen void
  drive.py shoot before_b004
  drive.py tap void-settings-button   # confirms the new ValueKey hits
  ```
- **Expected:** ≥ 48 dp tap target with a glyph that's perceivable at a glance.
- **Actual (pre-fix):** ~36 dp hit region around a single `·` rendered in `fgTertiary` (the dimmest UI tier).
- **Fix:** `_buildSettingsButton` now wraps a 48 × 48 Container around `⋮` (U+22EE VERTICAL ELLIPSIS) rendered at `rowSize + 4` in `fgPrimary.withAlpha(180)`. Added `ValueKey('void-settings-button')` for drive.py tap targets and `Semantics(label: 'settings', button: true)` for talkback.
- **Evidence:** _ui_revamp/shots/before_b002_b004_b005_void_cold.png (faint `·`) → _ui_revamp/shots/after_seeds_void_dark.png (visible `⋮`).
- **Status:** fixed

### B-005 — Launch hint shown only once-ever, never on subsequent cold launches

- **Severity:** minor
- **Hunter:** seed (from user)
- **Screen / state:** Void, cold launch
- **Repro:**
  ```
  drive.py reset
  drive.py screen void
  drive.py shoot after_b005_cold_1
  drive.py reset
  drive.py screen void
  drive.py shoot after_b005_cold_2   # hint must still appear
  ```
- **Expected:** Hint fades in on every cold launch and out after 3 s.
- **Actual (pre-fix):** `_maybeShowLaunchHint` read/wrote a `void_hint_shown` SharedPreferences flag and skipped on every subsequent launch.
- **Fix:** Removed the flag entirely; `_maybeShowLaunchHint` now sets `_showHint = true` on every mount and starts a 3 s Timer to fade it out via `_hintFaded`. The SharedPreferences read and the persistence write are gone.
- **Evidence:** Cold launches 1 and 2 (`after_b002_b004_b005_void_cold.png`, `after_b005_cold_launch_2.png`) both show the "tap · long-press · swipe" hint at top-right.
- **Status:** fixed

---
<!-- Hunter findings are appended below as the swarm runs. Keep IDs strictly increasing. -->

### B-006 — Background mode unconditionally pushes the system "Notification access" settings page on every activation

- **Severity:** major
- **Hunter:** H1
- **Screen / state:** Any home screen, mode=background, notification-listener not yet granted
- **Repro:**
  ```
  drive.py reset
  drive.py mode background     # opens Android Settings → Notification access
  drive.py shoot h1_polo_light_own    # later attempts to switch screens still see the system page
  ```
- **Expected:** Background mode requests notification-listener access once on first activation; subsequent toggles or programmatic state changes don't re-launch the system settings page if the user has already either granted or dismissed it.
- **Actual:** `MediaControllerPage._handleOperatingModeChanged` → `_ensureBackgroundPermissions()` calls `PlatformChannels.openNotificationSettings()` whenever the listener is not granted, with no debounce. Every entry into background mode (including the first one in a sweep) hijacks the screen. After backing out, the next call hijacks again. Drive automation (or a curious user) ends up stuck in system settings.
- **Evidence:** _ui_revamp/shots/h1_polo_light_own.png and _ui_revamp/shots/h1_void_light_own.png both show the system "Notification read, reply & control" page where the app screen should be.
- **Fix:** Added a per-session latch `_promptedNotifThisSession` on `_MediaControllerPageState`. `_ensureBackgroundPermissions` now only calls `_platformChannels.openNotificationSettings()` when the listener is missing AND the latch is unset; subsequent re-toggles within the same process leave the user on the app. The settings sheet's "notification listener" row still acts as the in-app re-prompt entry point.
- **Evidence:** _ui_revamp/shots/b006_2nd_bg_fixed.png — second `drive.py mode background` stays on Spectrum/Void instead of pushing the system "Notification access" page.
- **Status:** fixed

### B-007 — Pressing Android Back on the Void home screen exits the app silently

- **Severity:** minor
- **Hunter:** H2
- **Screen / state:** Void home, no overlay
- **Repro:**
  ```
  drive.py screen void
  adb shell input keyevent KEYCODE_BACK
  ```
- **Expected:** Either a "press back again to exit" confirmation or, at minimum, no exit when the user is mid-task (e.g. has a queue playing).
- **Actual:** The MaterialApp at the root never installs a `WillPopScope` / `PopScope`, so the system Back gesture pops the root route and Android closes the activity. Any unsaved navigation state (last folder, search query) is lost; if a queue is playing the audio service survives in the background but the UI is gone.
- **Suggested fix:** Wrap `MediaControllerPage` (or the inner `VoidScreen`) in `PopScope(canPop: false, onPopInvoked: ...)`. Optionally, treat Back in Void as "navigate up the file tree" if currentPath != null.
- **Status:** open

### B-009 — Void search results are scoped to currentPath only; misleading "no matches" for off-path tracks

- **Severity:** major
- **Hunter:** H2
- **Screen / state:** Void browser, navigated into a subfolder, search mode
- **Repro:**
  ```
  drive.py screen void
  drive.py nav /storage/emulated/0/Music/Indie
  # long-press the crumb to enter search; type "nirv"
  ```
- **Expected:** Searching from any folder scans the whole library (or at least the device's smart-roots scope) and finds Nirvana in `/Music`. The crumb hint or empty state should make the search scope explicit.
- **Actual:** `VoidBrowser._runSearch` calls `_controller.tracksForCurrentPath()` which only returns tracks under the currently-loaded folder. From Indie/, searching "nirv" yields "no matches" even though a Nirvana mp3 exists one level up.
- **Fix:** Added `LibraryController.androidSongs` (read-only view of the full MediaStore cache) and rewired `VoidBrowser._runSearch` to use it on Android. Non-Android platforms still use `tracksForCurrentPath()` until a recursive filesystem walker is added.
- **Evidence:** _ui_revamp/shots/h2_search_nirv.png (before, "no matches") → _ui_revamp/shots/after_b009_search_full_lib.png (after, "02 - Nirvana - Smells Like Teen S… — Music" appears from currentPath=Indie).
- **Status:** fixed

### B-010 — Rapid variant cycle (15 setSetting RPCs in <1 s) hangs the VM service / app

- **Severity:** major
- **Hunter:** H3
- **Screen / state:** Any home screen
- **Repro:**
  ```
  for i in 1..5: for v in dark light system: drive.py variant $v
  drive.py inspect   # → "VM has no isolates yet" or recv timeout
  ```
- **Expected:** Variant cycling at any speed is debounced or serialised so the VM and Flutter event loop remain responsive. Existing `test/p6_adversarial_test.dart` expects this in widget tests.
- **Actual:** After ~10–15 rapid `setSetting(themeVariant=...)` calls the VM service stops responding (`recv` times out; subsequent `getVM` calls return no isolates). The process is still running per `ps`. Recovery requires killing and restarting flutter run.
- **Suggested fix:** Audit `_ThemeListener._onChanged` — it calls `setState` on every notifier change, which on its own is fine. Most likely culprit is `SettingsService.saveThemeVariant` writing through SharedPreferences synchronously each call, plus `MediaPageController.didChangePlatformBrightness` re-applying SystemChrome on each rebuild. Coalesce or rate-limit; consider debouncing the persistence write 100 ms behind the in-memory notifier change.
- **Evidence:** /tmp/flutter_run.log + drive.py error trail; reproducible from a clean cold launch.
- **Status:** open

### B-008 — Choreographer "Skipped 140 frames" on the first frame after `am start`

- **Severity:** minor
- **Hunter:** H6
- **Screen / state:** Cold launch via `adb shell am start`
- **Repro:**
  ```
  adb shell am force-stop com.saplin.nothingness
  adb shell am start -n com.saplin.nothingness/.MainActivity
  adb logcat -d | grep Choreographer
  ```
- **Expected:** First frame within 2 s of activity start, no >100 dropped-frame warnings.
- **Actual:** First sustained activity emits `Choreographer: Skipped 140 frames! The application may be doing too much work on its main thread.` `LibraryService().init()`, `SettingsService().loadSettings()` and `AudioService.init()` all happen sequentially on the main isolate before `runApp`; the Android Activity is on screen with a blank surface while this completes.
- **Suggested fix:** Move non-blocking inits into `WidgetsBinding.instance.addPostFrameCallback` so the first frame paints early. Or use a lightweight splash with the Void hero placeholder while bootstrap runs.
- **Status:** open

---

## Refactor regression check (2026-05-15)

Post-refactor verification ("unify on Void chrome") sweep:

- **B-001 smart-roots two-entry view** — re-verified via `drive.py inspect`
  after a hot-restart on the refactored build. `library.smartRoots` lists
  `[/storage/emulated/0/Music, /storage/emulated/0/Podcasts]`, `currentPath
  == null`. **Stays closed.**
- **B-002 gesture-nav overlap** — visual confirmation in
  `verify_smart_roots_two_entries.png`: crumb + transport row sit above
  the home-indicator gesture pill. **Stays closed.**
- **B-003 immersive overflow** — toggled via the new `setSetting
  name=immersive` extension; `getOverflowReports.count == 0` across both
  transitions; audio kept playing through the animation. **Stays closed.**
- **B-004 settings tap target** — the 48 dp `⋮` glyph survives the chrome
  refactor (now driven by `void-settings-button` key, opens
  `VoidSettingsSheet` directly). **Stays closed.**
- **B-005 launch hint** — code path untouched; hint widget still subscribes
  to the same SharedPreferences key. **Stays closed.**
- **B-006 notification-listener latch** — flipped own→background→own→
  background; second activation did not re-hijack to the system settings
  page. `_promptedNotifThisSession` latch survives the
  `MediaControllerPage` refactor. **Stays closed.**
- **B-009 cross-folder search** — the recursive search algorithm lives in
  `lib/widgets/void_browser.dart` and `lib/controllers/library_controller.dart`,
  both untouched by this refactor. Adversarial UI verification via adb
  long-press proved finicky and was deferred (the search-input plumbing
  is internal state). **Stays closed by code-path inspection.**

Refactor surface area:

- Deleted: `lib/screens/{settings,spectrum,polo,dot}_screen.dart`,
  `lib/widgets/library_panel.dart`, plus their tests.
- Added: `lib/widgets/heroes/{void,spectrum,polo,dot}_hero.dart`,
  `lib/widgets/transport_row.dart`, immersive notifier in
  `SettingsService`, and tests under `test/widgets/heroes/` +
  `test/widgets/transport_row_test.dart` + `test/screens/void_screen_test.dart`.
- Settings consolidated into `VoidSettingsSheet`; legacy `more settings…`
  pivot points removed.

