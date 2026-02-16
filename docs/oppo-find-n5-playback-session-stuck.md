# Oppo Find N5: Playback session stuck (`Not Playing`, in-app Play unresponsive)

## Scope

- Device: Oppo Find N5
- OS: Android 16 (`targetSdk=36` app build)
- App package: `com.saplin.nothingness`
- Version observed: `2.2.0` (`versionCode=25`)
- Date: 2026-02-17

## Symptom

After the app has been running for a while, in-app playback toggle buttons stop working:

- Play/Pause/Next/Previous in app appear to do nothing
- Status shade media area shows greyed controls and `Not Playing`
- App restart restores playback immediately

## ADB evidence captured during failure

While the app was foreground and unresponsive:

- Process alive: `pidof com.saplin.nothingness` returned a valid PID
- `AudioService` alive and foreground (`isForeground=true`, notification id `1124`)
- Notification still present with media actions (`Previous`, `Play`, `Next`)
- Audio focus still owned by `com.saplin.nothingness`
- Media session exists and is selected as media-button target

But session state was stuck:

- `active=false`
- `PlaybackState state=NONE(0)`
- Position and update timestamp were static

Critical check:

- `adb shell cmd media_session dispatch play` and `play-pause` were routed to `com.saplin.nothingness/media-session/...` (visible in logcat), but session state still did not change from `NONE`.

This indicates a stale internal playback/session state (not a key routing issue at the Android dispatcher level).

## Attempted app-side fix

File changed: `lib/services/nothing_audio_handler.dart`

1. **Stop made non-destructive**
   - Previously `stop()` paused, then disposed controller/transport/listeners.
   - Now `stop()` pauses and updates playback state, but does not dispose internals.
   - Rationale: on some device paths, `stop()` may be triggered while process/UI remain alive. Full disposal can leave a non-recoverable in-memory session state until app restart.

2. **Play recovery fallback**
   - In `play()`, if `_controller.playPause()` throws, handler now retries by forcing reload of current queue index via `playFromQueueIndex(...)`.
   - Rationale: recover if underlying transport/source was invalidated while handler/session objects still exist.

## Verification after patch

- `flutter analyze` passed
- `flutter test test/services/playback_controller_test.dart` passed

## Current status

- Issue reproduced and diagnosed on Oppo Find N5 release build via ADB snapshots.
- Patch applied to improve session recovery and avoid destructive stop path.
- Requires real-device re-test on Oppo Find N5 with the patched build to confirm resolution across long-running/background scenarios.

## Fast re-check commands

Use these when the issue appears again:

```bash
adb -s <device> shell dumpsys media_session | rg -n "com.saplin.nothingness|active=|state=PlaybackState|Media button session is"
adb -s <device> shell dumpsys activity services com.ryanheise.audioservice.AudioService | rg -n "isForeground|foregroundId|startRequested|ServiceRecord"
adb -s <device> shell dumpsys notification --noredact | rg -n "com.saplin.nothingness|Audio playback|MediaStyle|\"Play\"|\"Pause\""
adb -s <device> shell cmd media_session dispatch play
adb -s <device> shell cmd media_session dispatch play-pause
```

