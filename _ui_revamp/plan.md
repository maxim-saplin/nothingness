# Bug-hunt swarm — end-to-end QA + fix, single arc, no approvals

## Context

The earlier QA passes rubber-stamped the app from source review and trivial happy-path runs. As a result the user found multiple regressions in seconds:

- Smart paths regressed — Void shows the full Android internal-storage tree (Alarms, Android, …, Ringtones). This is a music player, not a file explorer.
- Void's bottom overlaps the Android nav-gesture bar.
- Immersive transition flashes a "BOTTOM OVERFLOWED BY 54 PIXELS" stripe.
- Settings on Void are hard to reach (tiny `·` glyph, ~36 dp).
- 4 MP3s copied to the emulator and not surfaced by smart paths.

**These are not the bugs to fix. These are the bugs that prove the QA process is broken.** The plan below assumes there are many more, fixates on none of them, and engages a swarm explicitly chartered to **break** the app across every imaginable axis until it stops breaking.

Authorised mode: single arc, no per-phase approvals. The loop terminates only when the bug queue is empty AND every domain in the hunt matrix has been swept against the most recent build with zero open blocker or major findings.

---

## Operating principles for every agent in this swarm

1. **Assume the app is broken.** Default verdict is BLOCK. ACCEPT requires evidence.
2. **Validate visually on the live emulator.** Source review alone is never sufficient. Every "works" claim is backed by a screenshot, a `getRouterState` / `getLibraryState` / `getPlaybackState` JSON snapshot, or a logcat scrape.
3. **Try to break it.** For every interactive surface ask "what does the user-from-hell do here?" — rapid taps, gesture chords, permission flips mid-session, queue mutation during playback, screen-rotate during animation, system font 200 %, RTL locale, low memory, background → foreground at the wrong moment. **Test what the user might do, not what the happy path expects.**
4. **The bug queue is the source of truth.** Every finding goes immediately into `_ui_revamp/bugs.md` with a unique ID. No batching, no "let me verify first" gating. Triage and fix happen against the queue, not the agent's memory.
5. **Fixes require regression verification.** Reproduce, fix, re-run the same `drive.py` repro, attach before/after evidence to the entry, mark `fixed`. A different agent must close-verify on a clean cold launch of the latest APK before the entry is `closed`.
6. **No bug is too small to log.** Cosmetic, transient, debug-build-only — all logged. Triage decides severity, not the hunter.

---

## Phase A — Build the inspection surface (foundation)

The bug hunt is only ergonomic if agents can drive the app without pixel pushing. Build this once, use it everywhere downstream.

### A.1 — Extend `lib/testing/agent_service.dart`

Add these `ext.nothingness.*` extensions on top of the existing 15:

| Extension | Params | Returns |
|---|---|---|
| `getRouterState` | — | `{screen, themeVariant, operatingMode, immersive}` |
| `getLibraryState` | — | `{currentPath, hasPermission, isLoading, error, isAndroid, folders[], tracks[], smartRoots[]}` |
| `navigateVoid` | `path` | `{currentPath, folders, tracks}` |
| `navigateVoidUp` | — | `{currentPath, folders, tracks}` |
| `openSettingsSheet` | — | `{opened}` |
| `closeSettingsSheet` | — | `{closed}` |
| `playTrackByPath` | `path` | `{ok, index}` or `{error}` |
| `setPreference` | `key`, `value`, `type` | `{set, value}` |
| `clearPreference` | `key` | `{cleared}` |
| `requestLibraryPermission` | — | `{granted}` |
| `getOverflowReports` | — | `{reports[]}` — captures `FlutterError.onError` overflow stripes the agent may miss visually |

Wire via a small registry inside `AgentService`:

- `LibraryController` reference — registered by `VoidScreen.initState`, unregistered in `dispose`.
- `MaterialApp.navigatorKey` — created in `main.dart`, registered with `AgentService.register(...)`.
- Settings opener closure — registered by `MediaControllerPage.initState`; the closure knows which screen is active and calls the right entry.
- Overflow-report queue — install a `FlutterError.onError` hook in `main.dart` that appends `RenderFlex overflow` / `RenderBox` overflow events into a ring buffer that `getOverflowReports` returns.

All registration `kDebugMode`-gated as today.

### A.2 — Build `_ui_revamp/drive/drive.py`

Single Python entry point. Auto-discovers VM service URI from `adb -s emulator-5554 logcat`. Subcommands (each prints structured JSON, exit 0 on success, non-zero on RPC error):

```
drive.py inspect                  # router + library + playback + overflow reports
drive.py screen <name>            # spectrum | polo | dot | void
drive.py variant <name>           # dark | light | system
drive.py mode <name>              # own | background
drive.py nav <path>               # navigateVoid
drive.py up                       # navigateVoidUp
drive.py settings open|close      # open / close
drive.py play <path>              # playTrackByPath
drive.py pause | resume | next | prev
drive.py pref <key>=<value>:<type>   # setPreference
drive.py clearpref <key>          # clearPreference
drive.py permit                   # requestLibraryPermission
drive.py shoot <name>             # adb screencap -> _ui_revamp/shots/<name>.png
drive.py tree [depth]             # getWidgetTree
drive.py tap <key>                # tapByKey
drive.py logcat [lines]           # tail logcat
drive.py overflows                # getOverflowReports
drive.py reset                    # force-stop, clear app data, cold launch
drive.py replay <script.txt>      # newline-separated drive.py invocations as a script
```

A.1 + A.2 must compile, install, and pass a smoke run (`drive.py inspect` returns valid JSON on each screen) before the hunt starts.

---

## Phase B — Bug-hunt swarm

Six hunter agents, each owning a domain. Each hunter:

1. Reads the latest `_ui_revamp/bugs.md` so it does not duplicate entries.
2. Runs **its full domain matrix below**, even items the hunter suspects are fine.
3. Appends every finding to `_ui_revamp/bugs.md` with a unique `B-NNN` ID.
4. Reports a one-line summary "matrix swept / N findings filed" when done.

The hunters share one emulator. They run **sequentially** to avoid clobbering each other's state. `drive.py reset` returns the app to a known cold state between hunters.

### Bug entry schema

```
### B-NNN — <one-line summary>
- **Severity:** blocker | major | minor | cosmetic
- **Hunter:** H<n>
- **Screen / state:** <where>
- **Repro:** <exact drive.py / adb sequence>
- **Expected:** <what should happen>
- **Actual:** <what happened, screenshot path>
- **Evidence:** _ui_revamp/shots/<png>, logcat snippet, JSON snapshot
- **Status:** open
```

### Hunter H1 — Screen × variant × mode matrix

Sweep every combination of screens (spectrum, polo, dot, void) × variants (dark, light, system) × modes (own, background) — **24 states**. For each:

- App renders without crash (`getRouterState`, screencap, logcat clean).
- No overflow reports (`drive.py overflows` empty).
- Contrast: every visible label > 3:1 vs background — pixel-sample brightest and darkest text regions in the screencap.
- Touch targets: every interactive widget ≥ 44 dp on its smallest axis — `getWidgetTree` + reported size.
- System chrome (status bar, gesture bar, cutouts) does not overlap content.
- Animations land in their final state within 500 ms of trigger.

### Hunter H2 — Gesture / interaction matrix

For every interactive widget on every screen × variant × mode, exercise:

- Single tap (light, heavy).
- Long-press at 200 ms / 500 ms / 1000 ms / 2000 ms.
- Double-tap at 50 ms gap, 250 ms gap.
- Rapid taps 5/s for 3 s.
- Vertical swipe up / down.
- Horizontal swipe left / right.
- Two-finger pinch where applicable.
- Drag across widget boundaries (start in A, release in B).
- Tap during animation (e.g. play/pause while immersive transition is mid-flight).

MUST cover specifically:

- Void hero: tap, swipe-down (immersive on), swipe-up (immersive off), swipe in immersive.
- Void crumb: tap, long-press (search mode), swipe.
- Void browser rows: tap file, long-press file (one-shot), tap folder, long-press folder (recursive shuffle), tap up-row, scroll, fling.
- Search mode: type, backspace, paste, submit, dismiss via `×`, dismiss via back, dismiss via tap-outside, dismiss via focus loss.
- Spectrum / Polo / Dot: prev / next / play / pause, more_vert, library handle.
- Library panel: drag handle (open / close / partial / fling), tap row, long-press row.
- Settings sheet: every cycle chip, every toggle, every slider, every dismiss method.

### Hunter H3 — Lifecycle / state transitions

- Cold launch from each variant; first paint < 2 s.
- Warm resume after HOME → app (state preserved).
- Backgrounding while playing → audio continues; tap notification → resumes UI without crash.
- Backgrounding > 30 s then resume (low-memory simulation via `adb shell am send-trim-memory <pid> RUNNING_LOW`).
- Rotate while playing (if AVD allows).
- Toggle system theme mid-app (system variant follows).
- Toggle screen mid-playback (audio survives).
- Toggle operating mode mid-playback (matches mode contract).
- Variant cycle 20× in 10 s. Screen cycle 20× in 10 s. Both alternating 20× in 10 s.
- Settings open → screen cycle → settings should close or follow.
- Permission revoke mid-session: `adb shell pm revoke com.saplin.nothingness android.permission.READ_MEDIA_AUDIO` while VoidBrowser is showing tracks. UI must react sensibly, not crash.
- Permission grant mid-session (the reverse).
- Adversarial: kill the audio service from outside (`adb shell am stopservice ...`) while playing.

### Hunter H4 — Library / playback adversarial

Library setups to exercise (`drive.py` + `adb push`):

- 0 tracks.
- 1 track.
- 4 tracks (the user's state — **must be discoverable** per "not a file explorer" intent).
- 50 tracks across multiple folders.
- A track with Cyrillic / RTL / emoji / 200-char filename.
- A "broken" file (zero-byte MP3, malformed header, wrong extension).
- A deeply nested folder structure (8 levels deep).
- A folder containing 0 audio + 50 non-audio files — must NOT appear as music.

Playback adversarial:

- Rapid play/pause 10× in 2 s.
- Next during last track (queue wrap or stop).
- Prev during first track.
- Seek to end of track repeatedly.
- Mutate queue during playback (one-shot → another → resume).
- One-shot while shuffle queue active → queue resumes after.
- Phone-call interruption (`adb shell am broadcast -a android.intent.action.PHONE_STATE -e state RINGING`).
- Headphone disconnect / audio-becoming-noisy via `simulateNoisy`.
- Audio focus loss / regain via `simulateInterruption`.
- Background mode: confirm mic / notification listener prompts; audio plays in foreground; handover works.

### Hunter H5 — Layout edges / accessibility

- System font scale 0.85, 1.0, 1.3, 2.0.
- Display density override (small / default / large / huge).
- AVD rotation if supported.
- Status bar hidden / visible (immersive contract).
- Edge-to-edge / cutout simulation.
- RTL locale (`adb shell setprop persist.sys.locale ar-EG` + reboot or `adb shell am restart`).
- High-contrast mode.
- Reduce-motion (animations either still complete or are replaced with instant transitions).
- Talkback / semantics tree completeness via `getSemantics`.

### Hunter H6 — Spec adherence + logcat + leak watch

- Compare Void to `_ui_revamp/ui_structure_rethinking/v6_monk.html` row-by-row (hero, hint, crumb, file tree, progress hairline, settings affordance, search-mode morph, search-result rendering). Every divergence is a bug.
- Compare each legacy screen (Spectrum, Polo, Dot) to its design reference in `_ui_revamp/ui_ideas/` / `_ui_revamp/ui_structure_rethinking/` if present.
- Read `_ui_revamp/intent.md` and check every promise against the running app.
- Run > 5 min, watch for stuck rebuilds, dropped frames, "Skipped N frames", leaked Timer/StreamSubscription messages.
- Full logcat scan: zero matches for `FATAL`, `AndroidRuntime: E`, `Exception`, `^E flutter`, `^W flutter`, `Choreographer.*Skipped`, `StrictMode`, `leaked window`, `ANR`.

---

## Phase C — Triage + fix loop

After all six hunters finish first pass, the lead agent (me) triages `_ui_revamp/bugs.md`:

- **blocker** — crashes, data loss, music can't play, the user's reported regressions, contract violations (file-explorer behaviour, audio mishandled).
- **major** — visible defects, overflow stripes, missed gesture, contrast failures, touch targets < 44 dp, missing settings affordance.
- **minor** — small layout misalignments, subpixel divider issues, off-by-N px.
- **cosmetic** — typos, off-tone colours that still meet contrast.

Fix loop (one fixer agent per ~5 bugs, dispatched sequentially because emulator is shared):

1. Fixer reads bugs assigned to it.
2. For each bug:
   - Reproduce via `drive.py` sequence recorded in the entry.
   - Capture before state.
   - Fix the root cause — no `--no-verify`-style bypasses.
   - Re-run the repro on the new APK.
   - Capture after state.
   - Append both screenshot paths; status → `fixed`.
3. When all assigned bugs are `fixed`, hand back.

### Known structural fixes pre-loaded as seed entries

So we don't pretend they are discoveries — they came from the user:

- **B-001 (blocker):** smart paths show full filesystem on Android. Drop fs fallback on Android entirely. `lib/services/android_smart_roots.dart:51-55`, `lib/controllers/library_controller.dart:260-281`, `lib/services/library_browser.dart:99-139`. Verify with 4 MP3s in `/sdcard/Music`: smart roots show only `Music`, navigating in reveals exactly those 4 tracks.
- **B-002 (major):** Void content overlaps Android gesture-nav bar. `lib/screens/void_screen.dart` — `SafeArea(bottom: true)`, progress-hairline `bottom: MediaQuery.viewPadding.bottom`.
- **B-003 (major):** immersive transition 54 px overflow stripe. Clip the Column or use `AnimatedSize` / `AnimatedCrossFade` for the conditional children, OR wrap in `ClipRect(clipBehavior: Clip.hardEdge)`.
- **B-004 (major):** Void settings tap-target ~36 dp, glyph too dim. 48 dp target, larger glyph (`⋮` at `rowSize`, colour `fgPrimary.withAlpha(180)`), maybe a hairline outline.
- **B-005 (minor):** launch hint shows only once-ever (`void_hint_shown` pref). Show on every cold launch, fade after 3-5 s.

These are seed entries; hunters add many more.

---

## Phase D — Closure verification + second hunt pass

Closure-verifier agent (different from each fixer) sweeps the queue:

- For each `fixed`, runs the original repro on a clean cold launch of the latest APK.
- If gone → `closed`.
- If still occurs → re-open as `regressed`, severity escalated by one notch.

Then the hunter swarm runs its **second pass** against the patched APK. Any new findings re-enter the fix loop. Iterate until:

- Hunt matrix yields zero new blocker or major findings.
- All previously logged blocker / major bugs are `closed`.

Minor and cosmetic bugs may remain open at sign-off if the fix would be disproportionate; the queue records the rationale.

---

## Phase E — Sign-off

A single sign-off agent produces `_ui_revamp/qa_report.md` containing:

- Hunt matrix coverage table (each domain / sub-matrix, "swept" / "partial" / "skipped" with reason).
- Bug-queue summary (counts by severity, by status).
- Screenshot matrix (4 screens × 3 variants × 2 modes = 24 + Void immersive + Void search-mode + settings-on-each = 30+).
- Logcat summary (residual warnings).
- Verdict.

ACCEPT requires:

- Zero open blocker.
- Zero open major (or explicit signed waiver per item).
- All seed bugs B-001…B-005 closed.
- Second-pass hunt clean.

---

## Execution constraints

- Single emulator `emulator-5554`. Hunters and fixers run sequentially. Parallelism is in planning + analysis, not in emulator access.
- `CI_EMULATOR_ABI=x86_64` mandatory for every build.
- Every agent uses `drive.py` for state changes; raw `adb input tap` is reserved for cases `drive.py` doesn't cover (and those gaps become A.1 follow-up extensions).
- Every agent's report cites at least one screenshot per claim. Source review alone is not evidence.
- Loop terminates only at Phase E ACCEPT. No intermediate approvals.

## Critical files

- `lib/testing/agent_service.dart` — inspection surface (Phase A).
- `lib/main.dart` — global wiring (navigatorKey, FlutterError.onError hook).
- `lib/screens/void_screen.dart`, `void_browser.dart`, `void_settings_sheet.dart` — Void (most user pain).
- `lib/screens/{spectrum,polo,dot,media_controller_page,settings_screen}.dart` — legacy screens.
- `lib/services/{android_smart_roots,library_browser,library_service,settings_service,playback_controller}.dart` — data + audio.
- `lib/controllers/library_controller.dart` — library state machine.
- `_ui_revamp/ui_structure_rethinking/v6_monk.html` — Void design ground truth.
- `_ui_revamp/intent.md` — overall product intent.
- `_ui_revamp/bugs.md` — shared bug queue (created Phase A).
- `_ui_revamp/qa_report.md` — final sign-off (Phase E).
- `_ui_revamp/drive/drive.py` — CLI driver (Phase A).
- `_ui_revamp/shots/` — every screenshot referenced by a bug entry.

## End-to-end verification

The arc is done when:

1. `_ui_revamp/qa_report.md` is written with verdict **ACCEPT**.
2. `_ui_revamp/bugs.md` has zero open blocker / major.
3. Fresh `drive.py reset` + cold launch + smoke sweep (screen × variant × mode × inspect) returns no errors; screenshots match v6_monk for Void and the visible-design references for the other screens.
4. `flutter analyze` → no new issues vs the branch starting point.
5. `flutter test` → green.
6. `CI_EMULATOR_ABI=x86_64 flutter build apk --debug` → builds.

The user does not authorise intermediate approvals. The arc runs straight through to step 6.
