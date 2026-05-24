---
name: agent-emulator-debugging
description: Efficient app-driving workflow for the real Flutter app on emulator via VM service extensions, including common blocker recovery.
---
# Agent App Driving

Use this skill to drive the real app quickly, inspect runtime state, and unblock UI/action dead-ends.

Always use the real app entrypoint: `lib/main.dart` (never `main_test.dart` — that's reserved for deterministic `integration_test/` runs with fake transport).

## First-time setup

The Python tooling (`drive.py`) is managed by `uv` against a repo-root `.venv`. Bootstrap once after checkout:

```bash
uv sync   # creates .venv at the repo root and installs websockets
```

`drive.py` carries a PEP 723 inline metadata block and a `#!/usr/bin/env -S uv run --script` shebang, so `./drive.py …` Just Works even before `uv sync` has been run — uv resolves the dep on demand. The project venv is still useful for IDE completion and any future Python tooling.

## Fast Setup

```bash
flutter run -d emulator-5554 --debug
```

After install, **prepare the device** so the first-launch UI doesn't stall on permission dialogs and SoLoud has a playable file in its sandbox:

```bash
.claude/skills/agent-emulator-debugging/scripts/agent_prepare.sh \
  -d emulator-5554 \
  --stage .tmp/test_tone.wav   # optional, repeatable
```

This grants `RECORD_AUDIO`, `READ_MEDIA_AUDIO`, `READ_EXTERNAL_STORAGE`, `POST_NOTIFICATIONS`, and (optionally) copies host audio files into `/data/user/0/com.saplin.nothingness/files/`. The script is idempotent — run it any time the app is reinstalled. After staging `foo.mp3`, queue it via:

```bash
.claude/skills/agent-emulator-debugging/scripts/drive.py play /data/user/0/com.saplin.nothingness/files/foo.mp3
```

## Primary driver: `scripts/drive.py`

`scripts/drive.py` is the recommended way to puppet the app. It:

- Discovers the VM service WebSocket from logcat or `/tmp/flutter_run.log`.
- Caches the WS URI next to itself (`.vm_ws.txt`) so subsequent calls are instant.
- Sets up the ADB port-forward and resolves the main isolate.
- Wraps every `ext.nothingness.*` extension (26 of them) as a typed subcommand.
- Adds conveniences: screenshots into `.tmp/agent_shots/`, hot reload/restart via the `/tmp/flutter_input` fifo, force-stop + clear-data + cold launch, and a `replay` mode for newline-separated scripts.

```bash
D=.claude/skills/agent-emulator-debugging/scripts/drive.py

# State + UI
$D inspect            # router + library + playback + overflow ring buffer
$D tree 40            # widget tree as text
$D overflows          # FlutterError.onError ring buffer
$D shoot before_x     # adb screencap → .tmp/agent_shots/before_x.png

# Navigation (Void shell)
$D screen void                                # set active hero: spectrum|polo|dot|void
$D variant dark                               # dark|light|system
$D mode own                                   # own|background
$D nav /storage/emulated/0/Music              # navigate the library to a path
$D up                                         # navigateVoidUp
$D settings open                              # settings sheet open|close
$D permit                                     # programmatic library permission grant

# Playback
$D play /data/user/0/com.saplin.nothingness/files/foo.mp3
$D pause | $D resume | $D next | $D prev

# Preferences (broader than legacy setSetting)
$D pref void_hint_shown=false:bool            # types: bool|int|string
$D clearpref void_hint_shown

# Lifecycle
$D reload                                     # hot reload (sends `r` to /tmp/flutter_input)
$D restart                                    # hot restart
$D reset                                      # force-stop, clear app data, cold launch

# Audio diagnostics
$D call simulateInterruption phase=begin kind=pause
$D call simulateNoisy
$D call setSetting name=audioDiagnosticsOverlay value=true
$D logcat 500
$D replay smoke.txt                           # one drive.py invocation per line
```

For extensions not yet wrapped, `drive.py call <ext> k=v k=v …` calls any `ext.nothingness.<name>` with arbitrary params.

### Cadence limits

VM-service extension calls are not free — `setSetting` (and any other handler that writes through `SharedPreferences`) costs ~140 ms per RPC on emulator-5554. Sustained send rates above ~7/s back up the response queue; agents that fire-and-forget at >15/s observe what looks like a wedged isolate but is just unbounded backpressure (the queue eventually drains; at ~1000/s pipelined it never catches up within a reasonable timeout). Keep driver loops at **≤5/s with small jitter** for `setSetting`-style calls; reserve higher cadences for read-only extensions. Recovery if a session does hang: `rm .claude/skills/agent-emulator-debugging/scripts/.vm_ws.txt && drive.py restart`. If a test needs to hammer the same code path faster (20+ flips in <100 ms), use the in-process widget test pattern in `test/p6_adversarial_test.dart` instead of going through the VM service.

## WSL2 + Host Emulator

When Flutter runs in WSL2 and the emulator runs on the Windows host:

```bash
"/mnt/c/Users/<windows-user>/AppData/Local/Android/Sdk/platform-tools/adb.exe" -a start-server
HOST_IP=$(ip route | awk '/default/ {print $3; exit}')
ADB_SERVER_SOCKET=tcp:${HOST_IP}:5037 CI_EMULATOR_ABI=x86_64 flutter run -d emulator-5554 --debug
```

If launch-only is needed:

```bash
ADB_SERVER_SOCKET=tcp:${HOST_IP}:5037 CI_EMULATOR_ABI=x86_64 flutter run -d emulator-5554 --no-resident
```

If `adb devices` shows nothing from WSL2, run the `wsl2-adb-setup` skill first.

## Common Blockers (Fast Recovery)

1. **`drive.py` says "could not find Dart VM service URI"**:
   - The app isn't running in debug mode (release build, or `flutter run` exited).
   - Or the cached `.vm_ws.txt` points at a dead session. Either delete the cache or run `drive.py reset` then retry.

2. **App installs fail with signature mismatch (`INSTALL_FAILED_UPDATE_INCOMPATIBLE`)**:
   - Uninstall the existing package, then re-run `flutter run`.

3. **Queue is empty after reinstall**:
   - State shows `queueLen/queueLength = 0`. Set a queue with real files from `/sdcard/Music` or stage one via `agent_prepare.sh --stage`.

4. **SoLoud cannot load shared-storage file on emulator**:
   - Logcat shows `SoLoudFileNotFoundException` for `/sdcard/...` even though the file exists.
   - Fix: `agent_prepare.sh --stage <host_file>` (preferred), then `drive.py play /data/user/0/com.saplin.nothingness/files/<name>`.

5. **`Permissions Required` overlay blocks panel actions**:
   - Fix A (preferred): `agent_prepare.sh -d <device>` — grants all runtime permissions in one shot.
   - Fix B: `drive.py permit` — triggers the in-app permission request flow.

6. **Cannot tap a control via `tapByKey`**:
   - Cause: the production widget has no `ValueKey<String>`.
   - Fix: drive via `drive.py` (open settings sheet, navigate, set preference), or use `adb shell uiautomator dump` and tap by bounds.

7. **`drive.py reload` reports "Reloaded but no changes detected"**:
   - Hot reload doesn't pick up `initState`, static init, or top-level field changes.
   - Use `drive.py restart` (hot restart) or a full rebuild for those.

8. **Action path ambiguity (UI vs extension)**:
   - Verify with before/after state around one action.
   - Prefer single-action runs with immediate state readback.

## Minimal Drive Loop

1. Read baseline (`drive.py inspect`).
2. Apply precondition (queue/permission/screen).
3. Trigger one action.
4. Read state immediately.
5. Assert only required fields (index, isPlaying, title, position).

Reference: `docs/agent-driven-debugging.md`.
