---
name: agent-emulator-debugging
description: Efficient app-driving workflow for the real Flutter app on emulator or Linux/macOS desktop via VM service extensions, including common blocker recovery.
---
# Agent App Driving

Use this skill to drive the real app quickly, inspect runtime state, and unblock UI/action dead-ends. Works against:

- An Android emulator/device through `adb` (the default).
- A Flutter **desktop** build (`-d linux` or `-d macos`) when the emulator path is flaky — common in WSL2. Desktop driving bypasses ADB entirely; everything else (the 27 `ext.nothingness.*` extensions, hot reload, screenshots) is identical.

Always launch the agent-driving entrypoint `dev/main_debug.dart` (`flutter run -t dev/main_debug.dart`) — it installs the harness onto the `lib/debug_hooks.dart` seam and then runs the real `lib/main.dart` app, so the `ext.nothingness.*` extensions register. Plain `lib/main.dart` (the default `flutter run`) no longer loads the harness and exposes no extensions. Never use `dev/main_test.dart` — that's reserved for deterministic `integration_test/` runs with fake transport.

## First-time setup

The Python tooling (`drive.py`) is managed by `uv` against a repo-root `.venv`. Bootstrap once after checkout:

```bash
uv sync   # creates .venv at the repo root and installs websockets
```

`drive.py` carries a PEP 723 inline metadata block and a `#!/usr/bin/env -S uv run --script` shebang, so `./drive.py …` Just Works even before `uv sync` has been run — uv resolves the dep on demand. The project venv is still useful for IDE completion and any future Python tooling.

## Fast Setup

### Android (emulator or device)

```bash
# On an x86_64 emulator you MUST build x86_64 — this project's
# android/app/build.gradle.kts defaults `target-platform`/abiFilters to arm64
# (for release size), and a default `flutter run` would cross-compile
# flutter_soloud for arm64-v8a, which fails on the snap Flutter toolchain
# (host glibc headers leak into the NDK aarch64 sysroot — see B-045). Set:
CI_EMULATOR_ABI=x86_64 flutter run -d emulator-5554 --debug
```

After install, **prepare the device** so the first-launch UI doesn't stall on permission dialogs and SoLoud has a playable file in its sandbox. Granting library permissions and staging an audio file is a one-time idempotent step:

```bash
# Grant runtime permissions (idempotent, fine to re-run after every reinstall)
for P in RECORD_AUDIO READ_MEDIA_AUDIO READ_EXTERNAL_STORAGE POST_NOTIFICATIONS; do
  adb -s emulator-5554 shell pm grant com.saplin.nothingness "android.permission.$P" || true
done
# Stage a host audio file into the app sandbox so SoLoud can load it
adb -s emulator-5554 push .tmp/test_tone.wav \
    /data/user/0/com.saplin.nothingness/files/test_tone.wav
```

After staging `foo.mp3`, queue it via:

```bash
.claude/skills/agent-emulator-debugging/scripts/drive.py play \
    /data/user/0/com.saplin.nothingness/files/foo.mp3
```

### Linux / macOS desktop (no ADB)

Use this path when the emulator is flaky (a recurring WSL2 issue on x86 hosts). Run the app under `flutter run` with stdout going to `/tmp/flutter_run.log` and stdin attached to a fifo so `drive.py reload/restart` keeps working:

```bash
# One-time per host: create the fifo and a writer that holds it open
[ -p /tmp/flutter_input ] || mkfifo /tmp/flutter_input
nohup sleep infinity > /tmp/flutter_input &
# Launch the desktop build (Linux shown; `-d macos` works the same)
nohup flutter run -d linux --debug \
    < /tmp/flutter_input > /tmp/flutter_run.log 2>&1 &
# Drive it
export DRIVE_TARGET=linux        # or `macos`; auto-detected from the log too
$D inspect
```

Library permissions are a no-op on desktop. Stage an audio file by passing any absolute host path to `drive.py play`:

```bash
$D play /home/user/Music/foo.mp3      # any readable absolute path works
```

## Primary driver: `scripts/drive.py`

`scripts/drive.py` is the recommended way to puppet the app. It:

- Discovers the VM service WebSocket from `/tmp/flutter_run.log` (any target) or `adb logcat` (Android only).
- Caches the WS URI next to itself (`.vm_ws.txt`) so subsequent calls are instant.
- Sets up the ADB port-forward and resolves the main isolate (Android only — desktop skips ADB entirely).
- Wraps every `ext.nothingness.*` extension (27 of them) as a typed subcommand.
- Adds conveniences: screenshots into `.tmp/agent_shots/`, hot reload/restart via the `/tmp/flutter_input` fifo, force-stop + clear-data + cold launch (Android only), and a `replay` mode for newline-separated scripts.

### Target selection

`drive.py` picks its target from, in order:

1. `DRIVE_TARGET={android|linux|macos}` environment variable.
2. Sniffing `/tmp/flutter_run.log` for `Launching … on Linux|macOS|Android` (works for the common case where you only have one `flutter run` going).
3. Default: `android`.

On `linux` / `macos`, ADB calls are bypassed, `shoot` rasterizes via `ext.nothingness.screenshot` (no `adb screencap`), `logcat` tails `/tmp/flutter_run.log`, and `reset` refuses (restart the `flutter run` process to wipe state).

**Running Android *alongside* a live Linux session** (e.g. parallel regression): drive.py resolves the VM URI from the `flutter run` stdout log, defaulting to `/tmp/flutter_run.log`. If a Linux session owns that path, launch the Android run to a separate log and point drive.py at it, else Android reads the stale Linux URI:

```bash
CI_EMULATOR_ABI=x86_64 flutter run -d emulator-5554 --debug < /dev/null > /tmp/flutter_run_android.log 2>&1 &
export DRIVE_TARGET=android DRIVE_RUN_LOG=/tmp/flutter_run_android.log   # <- the override
```

drive.py reads the host-local DDS URI flutter prints there (`A Dart VM Service … available at: http://127.0.0.1:PORT/…`) — no manual `adb forward` needed.

```bash
D=.claude/skills/agent-emulator-debugging/scripts/drive.py
export DRIVE_TARGET=linux   # or `macos`; or unset for Android default

# State + UI
$D inspect            # router + library + playback + overflow ring buffer
$D tree 40            # widget tree as text
$D overflows          # FlutterError.onError ring buffer
$D shoot before_x     # PNG → .tmp/agent_shots/before_x.png (adb screencap on android,
                      # ext.nothingness.screenshot on desktop)

# Navigation (Void shell)
$D screen void                                # set active hero: spectrum|polo|dot|void
$D variant dark                               # dark|light|system
$D mode own                                   # own|background
$D nav /home/user/Music                       # navigate the library to a path
$D up                                         # navigateVoidUp
$D settings open                              # settings sheet open|close
$D permit                                     # programmatic library permission grant (no-op on desktop)

# Playback
$D play /home/user/Music/foo.mp3              # any absolute readable path
$D pause | $D resume | $D next | $D prev

# Preferences (broader than legacy setSetting)
$D pref void_hint_shown=false:bool            # types: bool|int|string
$D clearpref void_hint_shown

# Phone-frame the desktop build to repro portrait-phone layout (B-042; debug only)
$D emulate phone                              # preset 390x844 (also: small|tall|tiny|off)
$D emulate 360x800                            # arbitrary WxH
$D window 390 844                             # exact size; $D emulate off to clear
# Scales-to-fit the desktop window (FittedBox); MediaQuery reports phone dims,
# so layout/typography behave as on a phone. `shoot` then captures phone-sized PNGs.

# Lifecycle
$D reload                                     # hot reload (sends `r` to /tmp/flutter_input)
$D restart                                    # hot restart
$D reset                                      # Android only; refuses on desktop

# Audio diagnostics
$D call simulateInterruption phase=begin kind=pause
$D call simulateNoisy
$D call setSetting name=audioDiagnosticsOverlay value=true
$D logcat 500                                 # adb logcat (android); /tmp/flutter_run.log (desktop)
$D replay smoke.txt                           # one drive.py invocation per line
```

For extensions not yet wrapped, `drive.py call <ext> k=v k=v …` calls any `ext.nothingness.<name>` with arbitrary params.

### Cadence limits

VM-service extension calls are not free — `setSetting` (and any other handler that writes through `SharedPreferences`) costs ~140 ms per RPC on emulator-5554. Sustained send rates above ~7/s back up the response queue; agents that fire-and-forget at >15/s observe what looks like a wedged isolate but is just unbounded backpressure (the queue eventually drains; at ~1000/s pipelined it never catches up within a reasonable timeout). Keep driver loops at **≤5/s with small jitter** for `setSetting`-style calls; reserve higher cadences for read-only extensions. Recovery if a session does hang: `rm .claude/skills/agent-emulator-debugging/scripts/.vm_ws.txt && drive.py restart`. If a test needs to hammer the same code path faster (20+ flips in <100 ms), use the in-process widget test pattern in `test/p6_adversarial_test.dart` instead of going through the VM service.

### Do not kill the live flutter run session

Sub-agents driving the emulator MUST NOT use `adb shell am force-stop com.saplin.nothingness`, `adb shell pm revoke com.saplin.nothingness android.permission.RECORD_AUDIO`, or any other platform-level kill against the live `flutter run` session — they reliably trigger `Lost connection to device` and force a 60-90 s rebuild + reinstall. **`drive.py reset` is the same hazard wrapped**: it runs `am force-stop` + `pm clear` internally, so it now refuses with exit 1 whenever a live `flutter run` session is detected (fresh `/tmp/flutter_run.log` + responsive VM service). Pass `drive.py reset --force` only when you genuinely need to wipe persisted state and you have already accepted the 60-90 s rebuild cost. To exercise the same code paths without losing the session, use `drive.py call ext.nothingness.simulateInterruption phase=begin kind=pause` (and matching `phase=end`) for audio-focus loss, `drive.py pause` / `drive.py resume` for transport state, and `drive.py restart` (hot restart via the same `flutter run`) when isolate-level state must be reset without wiping app data. The audio side-channel (`ext.nothingness.simulateInterruption`, `simulateNoisy`) is purpose-built for this and is cheap.

### ADB synthetic-event swipes do not hit Flutter's velocity thresholds

`adb shell input swipe X1 Y X2 Y duration` injects a sequence of synthetic motion events at a fixed cadence, **not** a continuous touch stream with realistic per-frame deltas. Flutter's gesture arena computes pointer velocity from those samples and the result is consistently far below what a real finger flick produces — so hero swipes, `PageView` flings, dismissible thresholds, and any other velocity-gated gesture will silently no-op even when the swipe "looks" fast on the emulator. Do **not** chase velocity-gesture bugs via `adb shell input swipe`. Verify and regress them in widget tests with `tester.fling(finder, Offset(dx, 0), velocity)` (see `test/screens/void_screen_test.dart` for the B-027 pattern), which drives the same `GestureRecognizer` code path with deterministic velocities. ADB swipes remain fine for coarse pan/scroll where only distance matters.

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

**Emulator flaky on this x86 WSL2 host?** Use the Linux desktop path instead (see Fast Setup → Linux/macOS desktop). The 27 `ext.nothingness.*` extensions are platform-agnostic, so every drive.py command except `reset` and Android-specific perm grants works identically without ADB. The only feature gap is MediaStore-backed library scans (Android-only); on desktop the library is folder-based and stages files via any readable host path.

## Common Blockers (Fast Recovery)

1. **`drive.py` says "could not find Dart VM service URI"**:
   - The app isn't running in debug mode (release build, or `flutter run` exited).
   - Or the cached `.vm_ws.txt` points at a dead session. Either delete the cache or run `drive.py reset` then retry.

2. **App installs fail with signature mismatch (`INSTALL_FAILED_UPDATE_INCOMPATIBLE`)**:
   - Uninstall the existing package, then re-run `flutter run`.

3. **Queue is empty after reinstall**:
   - State shows `queueLen/queueLength = 0`. Set a queue with real files from `/sdcard/Music` (Android) / any readable host path (desktop), or stage one via the Fast Setup `adb push` snippet.

4. **SoLoud cannot load shared-storage file on emulator**:
   - Logcat shows `SoLoudFileNotFoundException` for `/sdcard/...` even though the file exists.
   - Fix: push a host file with `adb -s <device> push <host> /data/user/0/com.saplin.nothingness/files/<name>` (see Fast Setup), then `drive.py play /data/user/0/com.saplin.nothingness/files/<name>`.

5. **`Permissions Required` overlay blocks panel actions** (Android only):
   - Fix A (preferred): run the Fast Setup `pm grant` loop for all four perms in one shot.
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
