---
name: agent-emulator-debugging
description: Efficient app-driving workflow for the real Flutter app on emulator via VM service extensions, including common blocker recovery.
---
# Agent App Driving

Use this skill to drive the real app quickly, inspect runtime state, and unblock UI/action dead-ends.

Always use real app entrypoint: `lib/main.dart` (never `main_test.dart`).

## Fast Setup

```bash
flutter run -d emulator-5554 --debug
```

From stdout, capture VM URL:

```text
http://127.0.0.1:<PORT>/<AUTH>=/
```

Set:

```bash
BASE="http://127.0.0.1:<PORT>/<AUTH>=/"
ISOLATE=$(curl -s "${BASE}getVM" | python3 -c 'import sys,json; vm=json.load(sys.stdin)["result"]; print([i for i in vm["isolates"] if i["name"]=="main"][0]["id"])')
```

If `curl` is unavailable, use `python3 urllib.request` for the same endpoints.

## WSL2 + Host Emulator

When Flutter runs in WSL2 and emulator runs on Windows host:

```bash
"/mnt/c/Users/<windows-user>/AppData/Local/Android/Sdk/platform-tools/adb.exe" -a start-server
HOST_IP=$(ip route | awk '/default/ {print $3; exit}')
ADB_SERVER_SOCKET=tcp:${HOST_IP}:5037 CI_EMULATOR_ABI=x86_64 flutter run -d emulator-5554 --debug
```

If launch-only is needed:

```bash
ADB_SERVER_SOCKET=tcp:${HOST_IP}:5037 CI_EMULATOR_ABI=x86_64 flutter run -d emulator-5554 --no-resident
```

## Driving Shortcuts

```bash
e(){ curl -s "${BASE}ext.nothingness.$1?isolateId=${ISOLATE}${2:+&$2}"; }

# State
e getPlaybackState
e getSettings
e getWidgetTree "depth=40"

# Playback
e play
e pause
e next
e prev

# Queue
e setQueue "paths=/sdcard/Music/a.mp3,/sdcard/Music/b.mp3&startIndex=0"

# Key tap (only if widget has ValueKey<String>)
e tapByKey "key=test.playPause"
```

## Common Blockers (Fast Recovery)

1. App installs fail with signature mismatch:
- Symptom: `INSTALL_FAILED_UPDATE_INCOMPATIBLE`.
- Fix: uninstall existing package, then run again.

2. Queue is empty after reinstall:
- Symptom: state shows `queueLen/queueLength = 0`.
- Fix: set queue with real files from `/sdcard/Music`.

3. `Permissions Required` overlay blocks panel actions:
- Fix path A: tap in-app `Grant Permissions`.
- Fix path B: grant on device and reopen app.

4. Cannot tap Shuffle (or another panel control):
- First open library panel (handle tap or swipe up).
- If key tap fails, use adb UIAutomator dump and tap by bounds for visible text.

5. `tapByKey` returns not found:
- Cause: production widget has no `ValueKey<String>`.
- Fix: drive via panel open + text/bounds tap, not key tap.

6. Action path ambiguity (UI vs extension):
- Verify with before/after state around one action.
- Prefer single-action runs with immediate state readback.

## Minimal Drive Loop

1. Read baseline (`getPlaybackState`).
2. Apply precondition (queue/panel/permission).
3. Trigger one action.
4. Read state immediately.
5. Assert only required fields (index, isPlaying, title, position).

Reference: `docs/agent-driven-debugging.md`
