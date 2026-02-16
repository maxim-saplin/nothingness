# Zeekr OS 6.7 media button routing investigation

## Scope

- Platform under test: Zeekr DHU (`aptiv/zeekr_dhu`), Android 12 (SDK 32)
- Head unit software: Zeekr OS 6.7 (as reported during testing)
- App under test: `com.saplin.nothingness`
- Comparative app: `org.videolan.vlc`
- Date: 2026-02-13

## Goal

Determine why steering-wheel media buttons (pause/next/previous) no longer reliably control Nothingness after the OS update.

## Test method

Timed capture rounds were executed with synchronized windows:

- Operator handshake: "Ready" -> "Go - N seconds"
- During window: steering-wheel button sequence (`play/pause -> next -> previous`)
- Collected per round:
  - `adb logcat -v time -s MediaSessionService:V MediaFocusControl:V AudioService:V MediaButtonReceiver:V`
  - `adb shell getevent -lt`
  - pre/post snapshots:
    - `adb shell dumpsys media_session`
    - `adb shell dumpsys audio`
    - `adb shell cmd media_session list-sessions`

Primary capture files (Cursor terminal logs):

- `/Users/admin/.cursor/projects/Users-admin-src-nothingness/terminals/664842.txt`
- `/Users/admin/.cursor/projects/Users-admin-src-nothingness/terminals/350248.txt`
- `/Users/admin/.cursor/projects/Users-admin-src-nothingness/terminals/456101.txt`
- `/Users/admin/.cursor/projects/Users-admin-src-nothingness/terminals/56373.txt`
- `/Users/admin/.cursor/projects/Users-admin-src-nothingness/terminals/157461.txt`
- `/Users/admin/.cursor/projects/Users-admin-src-nothingness/terminals/99690.txt`
- `/Users/admin/.cursor/projects/Users-admin-src-nothingness/terminals/676140.txt`

## Findings

### 1) Button press windows cause transient media-button owner reassignment

Observed repeatedly in BT-source windows:

- `Media button session is changed to com.android.bluetooth/BluetoothMediaBrowserService`
- then returns to `com.saplin.nothingness/media-session`

This pattern appears in:

- `664842.txt` (Round B)
- `350248.txt` (Round C)
- `56373.txt` (final 10s BT window)

### 2) Audio focus follows the same transient takeover

During the same windows:

- `requestAudioFocus ... callingPack=com.android.bluetooth`
- `abandonAudioFocus ... com.saplin.nothingness`

Then focus can return to Nothingness later.

### 3) Comparative run with VLC shows same class of behavior

In `456101.txt`:

- Session changes to `org.videolan.vlc/VLC` when VLC plays
- Session toggles back to `com.saplin.nothingness/media-session` when VLC pauses

This confirms the behavior is not app-specific to Nothingness.

### 4) `getevent` does not show standard media keycodes in tested windows

Across captures, `getevent` either showed no key events or touch-only events (`BTN_TOUCH`) and no clear `KEY_PLAYPAUSE`/`KEY_NEXTSONG`/`KEY_PREVIOUSSONG`.

This suggests steering-wheel inputs are handled through an OEM mediation path rather than exposed as standard Linux input key events in these scenarios.

### 5) Nothingness media session plumbing remains present

Pre/post snapshots consistently show:

- active Nothingness media session in stack
- media button receiver exists for Nothingness
- in many states: `Media button session is com.saplin.nothingness/media-session`

So the issue is not simply "session missing".

## Interpretation

The dominant pattern is OEM/BT policy arbitration:

1. steering-wheel action occurs
2. BT/media-center path briefly claims focus and media-button target
3. ownership may return to Nothingness after the event

That is enough for button actions to be consumed outside the app, even when Nothingness is otherwise active.

## Phase 2: Reversible ADB component toggle experiments

Executed per the [reversible ADB workaround plan](zeekr-os-6.7-reversible-adb-workaround-plan.md).

### Constraints discovered

Component-level `pm disable-user` is blocked by `SecurityException` for all OEM and system packages on this build. Whole-package disables (`pm disable-user --user 0 <package>`) do work.

### Test A: Disable `com.zeekr.mediacenter` (whole package)

- **Result**: Steering-wheel buttons stopped working entirely.
- Logcat and session poller showed zero media events during button presses.
- The Zeekr MediaCenter `MediaKeyReceiver` is the **entry point** for steering-wheel media button events into the Android media system.
- Rollback: `pm enable --user 0 com.zeekr.mediacenter` — confirmed re-enabled.

### Test B: Disable `com.arcvideo.car.video` (whole package)

- **Result**: Steering-wheel buttons still did not work. Chinese-language error notifications appeared on screen.
- Logcat showed zero media events during button presses.
- The arcvideo package is an **intermediate relay** in the routing chain.
- Rollback: `pm enable --user 0 com.arcvideo.car.video` — confirmed re-enabled.

### Test BT: Disconnect A2dpSink profile (BT media audio)

- Disconnected via phone BT settings (disabled "Media audio") and ADB broadcast.
- HeadsetClient (phone calls) remained connected.
- **Result**: Steering-wheel buttons did not work. Zero logcat events.
- The BT A2dpSink/AVRCP stack is the **final stage** of the routing chain — not just an interferer.
- Rollback: re-enabled Media audio on phone.

### Verification: Direct `input keyevent` via ADB

- `adb shell input keyevent 127` (MEDIA_PAUSE) and `126` (MEDIA_PLAY) both worked perfectly.
- Logcat confirmed: `dispatchMediaKeyEvent ... Sending ... to com.saplin.nothingness/media-session`.
- No BT session hijack occurred with direct key injection.
- Nothingness media session is fully functional when events arrive through a clean path.

### Discovered routing architecture

The Zeekr OS 6.7 routes steering-wheel media buttons through the Bluetooth AVRCP stack:

```
Steering wheel
  → com.zeekr.mediacenter (MediaKeyReceiver)
    → com.arcvideo.car.video (MediaSessionService)
      → com.android.bluetooth (A2dpSink / AVRCP Controller)
        → Android MediaSessionService (dispatchMediaKeyEvent)
```

Every component in this chain is required. Disabling or disconnecting any one of them causes buttons to stop working entirely.

The BT stack transiently claims audio focus and media-button session ownership as part of processing the AVRCP command, creating a race condition where the key event may be dispatched to `BluetoothMediaBrowserService` instead of the active app's media session.

### Why this architecture causes the bug

The platform treats its own physical steering-wheel buttons as if they were remote BT media commands from a connected phone. When the BT A2dpSink processes the AVRCP passthrough command, it briefly:

1. Calls `requestAudioFocus` for `com.android.bluetooth`
2. Starts a transient `MediaPlayer` playback (state: started → stopped in ~50ms)
3. This causes `MediaSessionService` to flip `Media button session` to `BluetoothMediaBrowserService`
4. The key event is dispatched during this window, potentially to BT instead of the target app
5. Focus and session ownership return to the app after the transient, but the event is already consumed

## Phase 3: Root-level experiments

Root shell access enabled via the following sequence:

```bash
adb shell setprop service.adb.root 1
adb usb          # restarts adbd
adb wait-for-device
adb shell id     # should show uid=0(root)
```

Root is read-only — `/system` remains verity-protected, `adb remount` fails.

### Root Test 1: Disable `BluetoothMediaBrowserService` component

- `pm disable com.android.bluetooth/.avrcpcontroller.BluetoothMediaBrowserService`
- **Result**: All BT profiles (A2dpSink, HeadsetClient, AvrcpController) disconnected immediately. Tightly coupled — AVRCP Controller cannot function without its MediaBrowserService.
- Rollback required both re-enable and a full BT cycle:

```bash
adb shell pm enable com.android.bluetooth/.avrcpcontroller.BluetoothMediaBrowserService
adb shell svc bluetooth disable && sleep 3 && adb shell svc bluetooth enable
# wait ~15s for profiles to reconnect
```

### Root Test 2: Disable `A2dpSinkService` component

- `pm disable com.android.bluetooth/.a2dpsink.A2dpSinkService`
- **Result**: Same — all BT profiles torn down. BT components are deeply interdependent.
- Rollback: same `pm enable` + BT cycle pattern as Root Test 1.

### Root Test 3: `appops` deny PLAY_AUDIO + TAKE_AUDIO_FOCUS for BT

- `appops set com.android.bluetooth PLAY_AUDIO deny`
- `appops set com.android.bluetooth TAKE_AUDIO_FOCUS deny`
- All BT profiles remained connected (A2dpSink, HeadsetClient, AvrcpController).
- **Result**: Steering-wheel buttons did not work. Zero logcat events.
- Rollback: `appops set ... allow` for both operations.

### Critical insight: audio focus grab IS the delivery mechanism

The `appops` test proves that the BT audio focus acquisition is not merely a side effect of key event routing — it is the **mechanism** by which key events enter Android's MediaSessionService. The sequence is:

1. AVRCP passthrough command arrives at the BT stack
2. A2dpSink starts transient audio playback → requests audio focus
3. The audio playback state change triggers `MediaSessionService` to dispatch the key event
4. Blocking step 2 (via appops deny) prevents step 3 entirely

This means the hijack and the delivery are **the same operation**. There is no way to surgically permit key event delivery while preventing the transient session takeover without modifying BT stack code.

## Conclusion

For Zeekr OS 6.7, this is a **platform architecture issue**: steering-wheel buttons are routed through the BT AVRCP stack, and key event delivery depends on a transient BT audio focus grab that inherently causes a race condition in media-button session ownership.

**Approaches exhausted** (all cause buttons to stop working entirely):

| Approach | Why it fails |
|----------|-------------|
| Disable Zeekr MediaCenter | Kills the entry point |
| Disable arcvideo | Kills the intermediate relay |
| Disconnect A2dpSink | Kills the routing endpoint |
| Disable BluetoothMediaBrowserService (root) | Tears down all BT profiles |
| Disable A2dpSinkService (root) | Tears down all BT profiles |
| `appops` deny BT audio focus (root) | Blocks the delivery mechanism itself |

**Approaches that work** (confirming the app is correct):

| Approach | Result |
|----------|--------|
| `adb shell input keyevent 127/126` | Perfect pause/play — bypasses OEM chain entirely |

**App-side tuning** can improve resilience but cannot eliminate the race condition.

## Post-experiment cleanup and cautions

### Residual state found after experiments

A `settings put global bluetooth_a2dp_sink_priority_24:75:B3:0E:E5:CC 0` was written during Phase 2 experimentation and was **not** included in the original rollback checklist. This setting persisted across reboots and may have contributed to:

- BT audio connected but silent (Media Center showed song name and position advancing, no sound output)
- Possibly increased frequency of DHU cold boots

Cleanup:

```bash
adb shell settings delete global bluetooth_a2dp_sink_priority_24:75:B3:0E:E5:CC
```

### Full post-experiment rollback checklist

Run after any experiment session to ensure no residual state:

```bash
# OEM packages
adb shell pm enable --user 0 com.zeekr.mediacenter
adb shell pm enable --user 0 com.arcvideo.car.video

# BT components (requires root)
adb shell pm enable com.android.bluetooth/.avrcpcontroller.BluetoothMediaBrowserService
adb shell pm enable com.android.bluetooth/.a2dpsink.A2dpSinkService

# appops
adb shell appops set com.android.bluetooth PLAY_AUDIO allow
adb shell appops set com.android.bluetooth TAKE_AUDIO_FOCUS allow

# stale settings
adb shell settings delete global bluetooth_a2dp_sink_priority_24:75:B3:0E:E5:CC

# BT reconnect cycle (if profiles are disconnected)
adb shell svc bluetooth disable && sleep 3 && adb shell svc bluetooth enable
# wait ~15s for all profiles to reconnect
```

### Side effects observed

- Repeated BT toggle cycles and component enable/disable operations may destabilize the DHU. After the experiment session, more frequent cold boots on DHU startup were observed (even after short 30-minute parking intervals). This may resolve on its own after the system stabilizes.
- BT component disables cascade to all profiles (A2dpSink, HeadsetClient, AvrcpController are tightly coupled). Always plan for a BT toggle cycle after re-enabling.

## Next actions

- Use this report for OEM escalation. The core issue is that steering-wheel buttons should not be routed through BT AVRCP on the same device. The platform should dispatch media key events directly to `MediaSessionService` without the A2dpSink audio focus round-trip.
- Investigate app-side audio focus resilience improvements (faster re-acquisition, `AUDIOFOCUS_GAIN` flags) as a partial mitigation.
- Consider whether a background accessibility service or input method could intercept and re-route media keys before the BT stack processes them (requires user opt-in).
