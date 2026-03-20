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
ISOLATE=$(python3 - <<'PY'
import json
import urllib.request

base = "http://127.0.0.1:<PORT>/<AUTH>=/"
with urllib.request.urlopen(base + 'getVM') as resp:
	vm = json.load(resp)["result"]
print([i for i in vm["isolates"] if i["name"] == "main"][0]["id"])
PY
)
```

The shipped helper script uses `python3 urllib.request`, so it no longer depends on `curl`.

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
e(){ python3 - "$BASE" "$ISOLATE" "$1" "${2:-}" <<'PY'
import json
import sys
import urllib.parse
import urllib.request

base, isolate, name, extra = sys.argv[1:5]
params = {'isolateId': isolate}
if extra:
	for key, value in urllib.parse.parse_qsl(extra, keep_blank_values=True):
		params[key] = value
with urllib.request.urlopen(f"{base}ext.nothingness.{name}?" + urllib.parse.urlencode(params)) as resp:
	print(resp.read().decode())
PY
}

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

3. SoLoud cannot load shared-storage file on emulator:
- Symptom: logcat shows `SoLoudFileNotFoundException` for `/sdcard/...` even though the file exists.
- Fix: push the file to `/data/local/tmp`, then copy it into the app sandbox with `run-as com.saplin.nothingness cp ... files/...`, and queue `/data/user/0/com.saplin.nothingness/files/<name>`.

4. `Permissions Required` overlay blocks panel actions:
- Fix path A: tap in-app `Grant Permissions`.
- Fix path B: grant on device and reopen app.

5. Cannot tap Shuffle (or another panel control):
- First open library panel (handle tap or swipe up).
- If key tap fails, use adb UIAutomator dump and tap by bounds for visible text.

6. `tapByKey` returns not found:
- Cause: production widget has no `ValueKey<String>`.
- Fix: drive via panel open + text/bounds tap, not key tap.

7. Action path ambiguity (UI vs extension):
- Verify with before/after state around one action.
- Prefer single-action runs with immediate state readback.

## Minimal Drive Loop

1. Read baseline (`getPlaybackState`).
2. Apply precondition (queue/panel/permission).
3. Trigger one action.
4. Read state immediately.
5. Assert only required fields (index, isPlaying, title, position).

Reference: `docs/agent-driven-debugging.md`
