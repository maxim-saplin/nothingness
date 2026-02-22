# Emulator power diagnostics (evidence → culprit)

This doc is for **Android emulator troubleshooting only**.

- Goal: **find evidence** of unexpected background work (CPU, wakeups, services, listeners) and map it to likely culprits in the codebase.
- Non-goal: compute accurate real-device energy usage. Emulator “battery drain %” is not representative.

## Why emulator is still useful

Even if energy numbers are off, the emulator is good at showing:

- a process that is never idle (CPU stays non-zero)
- a foreground service that stays alive after you think it should stop
- spammy log patterns or callbacks firing while the UI is backgrounded
- wake locks / partial wake behavior (when present)

## Quick constants

```bash
DEVICE=emulator-5554
PKG=com.saplin.nothingness
ACTIVITY=$PKG/.MainActivity
```

## Baseline capture loop (copy/paste)

## Automated quick check (local + CI)

For fast regression signal, use the automated runner:

```bash
tool/power/emulator_power_regression.sh --window-sec 120 --sample-sec 5
```

Artifacts are written under `.tmp/power/<timestamp>-auto-regression/` and include:

- sampled package CPU for S0 control and S1 background-idle
- `dumpsys` snapshots (`cpuinfo`, `power`, `activity services`, `jobscheduler`, `alarm`)
- `logcat` slice + parsed `summary.json`

The parser (`tool/power/evaluate_power_capture.py`) marks regressions using quick-win thresholds:

- idle median CPU delta (S1 - S0) too high
- idle p95 CPU too high or sustained high CPU streak
- playback-state churn signature too high in logcat

Use `--ci` to enforce strict exit behavior:

```bash
tool/power/emulator_power_regression.sh --ci --window-sec 120 --sample-sec 5
```

### 0) Prepare a clean baseline window

```bash
adb -s "$DEVICE" shell dumpsys batterystats --reset
adb -s "$DEVICE" shell dumpsys batterystats enable full-history

# Optional: treat stats as if screen is off (useful if you want to keep the emulator visible)
adb -s "$DEVICE" shell dumpsys batterystats enable pretend-screen-off
```

### 1) Run a scenario for 10–30 minutes

Keep the scenario simple and consistent. See scenarios below.

### 2) Capture evidence into local files

```bash
mkdir -p .tmp/power

adb -s "$DEVICE" shell pidof "$PKG" > .tmp/power/pid.txt || true

adb -s "$DEVICE" shell dumpsys batterystats --checkin "$PKG" > .tmp/power/batterystats_checkin.txt
adb -s "$DEVICE" shell dumpsys batterystats --history > .tmp/power/batterystats_history.txt
adb -s "$DEVICE" shell dumpsys batterystats --cpu > .tmp/power/batterystats_cpu.txt

adb -s "$DEVICE" shell dumpsys cpuinfo > .tmp/power/dumpsys_cpuinfo.txt
adb -s "$DEVICE" shell dumpsys power > .tmp/power/dumpsys_power.txt
adb -s "$DEVICE" shell dumpsys activity processes > .tmp/power/dumpsys_activity_processes.txt
adb -s "$DEVICE" shell dumpsys activity services "$PKG" > .tmp/power/dumpsys_activity_services_pkg.txt

# Media + notification wiring (relevant to NotificationListenerService / audio_service)
adb -s "$DEVICE" shell dumpsys media_session > .tmp/power/dumpsys_media_session.txt
adb -s "$DEVICE" shell dumpsys notification --noredact > .tmp/power/dumpsys_notification.txt

# Jobs/alarms should usually be empty for this app; capture anyway
adb -s "$DEVICE" shell dumpsys jobscheduler > .tmp/power/dumpsys_jobscheduler.txt
adb -s "$DEVICE" shell dumpsys alarm > .tmp/power/dumpsys_alarm.txt

# A log slice around collection time
adb -s "$DEVICE" logcat -d -v time > .tmp/power/logcat_dump.txt
```

Tip: to keep logs small, clear then re-run your scenario:

```bash
adb -s "$DEVICE" logcat -c
```

## Scenarios (emulator-focused)

Run each scenario from a clean state (force-stop), then leave the emulator idle.

### S0: Control (app not running)

```bash
adb -s "$DEVICE" shell am force-stop "$PKG"
```

If S0 is already “hot” (CPU/wakeups), the emulator itself (or other apps) are noisy.

### S1: Launch once, then background

```bash
adb -s "$DEVICE" shell am start -n "$ACTIVITY"

# Background it
adb -s "$DEVICE" shell input keyevent KEYCODE_HOME
```

### S2: Notification access OFF (isolates listener overhead)

The app registers a `NotificationListenerService` in Android:

- `android/app/src/main/kotlin/com/saplin/nothingness/MediaSessionService.kt`

If notification access is enabled, **other apps’ notifications** can wake this service.

On emulator, check whether the listener is enabled:

```bash
adb -s "$DEVICE" shell settings get secure enabled_notification_listeners \
  | tr ':' '\n' \
  | grep -i "$PKG" || true
```

Then run S1.

### S3: Playback-related states

This app uses `audio_service` and requests wake/foreground service permissions.

The current Android init config includes:

- `androidStopForegroundOnPause: false` in `lib/main.dart`

That means “paused” may still keep a service alive by design.

On emulator, run one of:

- Play something (if you have media in the emulator) → pause → background
- Or just background the app and capture whether the service exists anyway

Collect service state:

```bash
adb -s "$DEVICE" shell dumpsys activity services com.ryanheise.audioservice.AudioService \
  | sed -n '1,220p'
```

### S4: Spectrum / visualization overhead

Two separate spectrum paths exist:

- **Player spectrum (SoLoud FFT in Dart)**: can poll very frequently.
- **Microphone spectrum (native AudioRecord thread)**: runs ~30fps when started.

In code, likely hot loops include:

- 16ms polling timer: `lib/services/soloud_spectrum_provider.dart`
- 300ms timers: `lib/services/playback_controller.dart`, `lib/services/soloud_transport.dart`
- Native mic capture thread: `android/app/src/main/kotlin/com/saplin/nothingness/AudioCaptureService.kt`

Run with the spectrum screen visible for a short window, then background it and see if CPU drops.

## What to look for (evidence)

### 1) “Why is it using CPU while idle?”

Quick checks:

```bash
adb -s "$DEVICE" shell dumpsys cpuinfo | grep -i -E "nothingness|$PKG" || true
adb -s "$DEVICE" shell pidof "$PKG" || true
```

If the app shows up consistently in `dumpsys cpuinfo` while backgrounded and screen-off, treat that as evidence of a timer/stream/loop still running.

### 2) “Is a foreground service running?”

```bash
adb -s "$DEVICE" shell dumpsys activity services "$PKG" | sed -n '1,260p'
adb -s "$DEVICE" shell dumpsys activity services com.ryanheise.audioservice.AudioService | sed -n '1,260p'
```

Evidence that matters:

- `isForeground=true`
- `foregroundId=`
- ongoing notification presence

### 3) “Are there wake locks?”

```bash
adb -s "$DEVICE" shell dumpsys power | sed -n '1,240p'
```

Look for:

- partial wake locks attributed to the app UID / package
- “Wake Locks:” sections that mention the package

### 4) “Is notification/media-session plumbing causing churn?”

The app uses a notification listener to discover active media sessions.

Collect:

```bash
adb -s "$DEVICE" shell dumpsys media_session | grep -n -i "$PKG" -n || true
adb -s "$DEVICE" shell dumpsys notification --noredact | grep -n -i "$PKG" -n || true
```

Also check logcat for the service tag:

```bash
adb -s "$DEVICE" logcat -v time | grep -i "MediaSessionService" 
```

If you see repeated `updateActiveController()` patterns or frequent callbacks while the app is backgrounded, that’s a plausible culprit.

### 5) “Is MediaStore observation waking the app?”

`MainActivity` registers a MediaStore `ContentObserver` when the Dart side listens.

Capture:

```bash
adb -s "$DEVICE" logcat -v time | grep -i "MediaStore" 
```

Then correlate with:

- `lib/services/android_media_store_freshness.dart`
- `lib/services/platform_channels.dart`

## Culprit map (symptom → likely code hot spot)

Use this to prioritize where to look **after** you have evidence.

- CPU stays non-zero while spectrum is enabled
  - `lib/services/soloud_spectrum_provider.dart` (16ms polling)
  - `lib/services/soloud_transport.dart` (timer-based ended checks)

- CPU stays non-zero even when UI is backgrounded
  - `lib/services/playback_controller.dart` (300ms periodic timer)
  - `lib/services/nothing_audio_handler.dart` (transport event listeners that may keep state updates flowing)

- Foreground service persists when paused
  - `lib/main.dart` (`AudioServiceConfig(androidStopForegroundOnPause: false)`)

- Work correlates with other apps’ notifications / media changes
  - `android/app/src/main/kotlin/com/saplin/nothingness/MediaSessionService.kt` (`NotificationListenerService`)

- Mic-spectrum path causes drain
  - `android/app/src/main/kotlin/com/saplin/nothingness/AudioCaptureService.kt` (AudioRecord + FFT loop)
  - `lib/screens/media_controller_page.dart` (mic mode starts a 700ms song-info timer)

## Optional: debug-mode state probing (emulator)

In debug builds, the app registers VM service extensions (see `docs/agent-driven-debugging.md`).

This is not a power baseline, but it helps confirm runtime state like:

- audio source (player vs microphone)
- whether spectrum capture is enabled

Use it when you need to answer “what does the app think it’s doing right now?” while reproducing an idle-CPU symptom.

### Quick start (drive the real app)

Use the real entrypoint (`lib/main.dart`) in debug mode:

```bash
flutter run -d emulator-5554 --debug
```

From the `flutter run` output, copy the VM service base URL:

```
http://127.0.0.1:<PORT>/<AUTH>=/
```

Then use the helper script:

```bash
chmod +x .claude/skills/agent-emulator-debugging/scripts/agent_drive.sh

BASE=http://127.0.0.1:<PORT>/<AUTH>= \
  .claude/skills/agent-emulator-debugging/scripts/agent_drive.sh state

BASE=http://127.0.0.1:<PORT>/<AUTH>= \
  .claude/skills/agent-emulator-debugging/scripts/agent_drive.sh settings

BASE=http://127.0.0.1:<PORT>/<AUTH>= \
  .claude/skills/agent-emulator-debugging/scripts/agent_drive.sh widget-tree --depth 60
```

Combine this with the ADB loop above to correlate **observed state** (playing/paused, spectrum non-zero) with **evidence** (CPU/services/wakelocks).

## Notes / limitations

- Emulator battery percentages and “time remaining” are not reliable. Treat them as a trigger to gather CPU/service evidence.
- Prefer **release** or **profile** builds for CPU realism. Prefer **debug** builds only when you need VM-service introspection.
