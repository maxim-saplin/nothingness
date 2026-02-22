# Zeekr OS 6.7 reversible ADB workaround plan

> **Status: Executed 2026-02-13.** All tests completed. No viable system-level workaround found. See [investigation report](zeekr-os-6.7-media-buttons-investigation.md) for full results.

## Purpose

Test whether OEM media-key handlers are intercepting steering-wheel media buttons, using strictly reversible ADB component toggles.

This plan is diagnostic. It does not modify app code.

## Safety rules

- Apply one change at a time.
- Validate behavior after each change.
- Revert immediately if behavior worsens.
- Keep a rollback section ready before any test.

## Preconditions

- `adb devices` shows the head unit online.
- Nothingness installed and playable.
- Known test sequence ready: steering-wheel `pause -> next -> previous`.
- Capture method ready (timed window with pre/post snapshots).

## Baseline snapshot (before any toggle)

```bash
mkdir -p .tmp
adb shell dumpsys media_session > .tmp/zeekr_media_session_baseline.txt
adb shell dumpsys audio > .tmp/zeekr_audio_baseline.txt
adb shell cmd media_session list-sessions > .tmp/zeekr_sessions_baseline.txt
adb shell pm query-receivers --components -a android.intent.action.MEDIA_BUTTON > .tmp/zeekr_media_button_receivers.txt
```

## Candidate OEM components to test

From observed package metadata and receiver queries:

- `com.zeekr.mediacenter/ecarx.xsf.mediacenter.key.MediaKeyReceiver`
- `com.arcvideo.car.video/com.arcvideo.ivi.media.sdk.mediasession.receiver.ArcMediaButtonReceiver`

Optional advanced candidate (higher risk):

- `com.arcvideo.car.video/com.arcvideo.ivi.media.sdk.mediasession.service.ArcMediaSessionService`

## Test matrix (reversible)

### Test A: Disable Zeekr MediaCenter key receiver

Disable:

```bash
adb shell pm disable-user --user 0 com.zeekr.mediacenter/ecarx.xsf.mediacenter.key.MediaKeyReceiver
```

Run timed capture and verify:

- does `Media button session` stop flipping away from Nothingness?
- do wheel buttons control Nothingness reliably?

Rollback:

```bash
adb shell pm enable --user 0 com.zeekr.mediacenter/ecarx.xsf.mediacenter.key.MediaKeyReceiver
```

### Test B: Disable Arc media button receiver

Disable:

```bash
adb shell pm disable-user --user 0 com.arcvideo.car.video/com.arcvideo.ivi.media.sdk.mediasession.receiver.ArcMediaButtonReceiver
```

Run the same timed capture and evaluate.

Rollback:

```bash
adb shell pm enable --user 0 com.arcvideo.car.video/com.arcvideo.ivi.media.sdk.mediasession.receiver.ArcMediaButtonReceiver
```

### Test C (optional, higher risk): Disable Arc media session service

Disable:

```bash
adb shell pm disable-user --user 0 com.arcvideo.car.video/com.arcvideo.ivi.media.sdk.mediasession.service.ArcMediaSessionService
```

Run timed capture and evaluate.

Rollback:

```bash
adb shell pm enable --user 0 com.arcvideo.car.video/com.arcvideo.ivi.media.sdk.mediasession.service.ArcMediaSessionService
```

## Validation commands for each test

```bash
adb shell dumpsys media_session | rg -n "Media button session is|BluetoothMediaBrowserService|com.saplin.nothingness|com.arcvideo.car.video|com.zeekr.mediacenter"
adb shell dumpsys audio | rg -n "focus owners|requestAudioFocus|abandonAudioFocus|com.android.bluetooth|com.saplin.nothingness"
adb shell cmd media_session list-sessions
```

## Full rollback checkpoint

Run at end of experiment set:

```bash
# OEM packages (whole-package level — component-level is blocked by SecurityException)
adb shell pm enable --user 0 com.zeekr.mediacenter
adb shell pm enable --user 0 com.arcvideo.car.video

# BT components (requires root: adb shell setprop service.adb.root 1 && adb usb && adb wait-for-device)
adb shell pm enable com.android.bluetooth/.avrcpcontroller.BluetoothMediaBrowserService
adb shell pm enable com.android.bluetooth/.a2dpsink.A2dpSinkService

# appops (may have been changed during experiments)
adb shell appops set com.android.bluetooth PLAY_AUDIO allow
adb shell appops set com.android.bluetooth TAKE_AUDIO_FOCUS allow

# stale settings (written during experimentation, not in original plan)
adb shell settings delete global bluetooth_a2dp_sink_priority_24:75:B3:0E:E5:CC

# BT reconnect cycle (needed if BT profiles were torn down by component disables)
adb shell svc bluetooth disable && sleep 3 && adb shell svc bluetooth enable
# wait ~15s for profiles to reconnect
```

Then verify enabled state:

```bash
adb shell pm dump com.zeekr.mediacenter | rg -n "MediaKeyReceiver|enabled="
adb shell pm dump com.arcvideo.car.video | rg -n "ArcMediaButtonReceiver|ArcMediaSessionService|enabled="
adb shell appops get com.android.bluetooth | rg "PLAY_AUDIO|TAKE_AUDIO_FOCUS"
adb shell settings get global bluetooth_a2dp_sink_priority_24:75:B3:0E:E5:CC  # should be "null"
adb shell dumpsys bluetooth_manager | rg "state=Connected"
```

## Exit criteria

A workaround is considered practical only if all are true:

- wheel buttons consistently control Nothingness in repeated timed windows
- no critical regression in system media UX
- behavior survives app restart and source changes
- all toggles remain reversible with commands above

## Outcome

No viable system-level workaround was found. Every component in the routing chain (Zeekr MediaCenter → arcvideo → BT A2dpSink/AVRCP) is required for steering-wheel buttons to function, and the transient BT audio focus grab that causes the session hijack is also the key event delivery mechanism. See the [investigation report](zeekr-os-6.7-media-buttons-investigation.md) for the complete analysis.
