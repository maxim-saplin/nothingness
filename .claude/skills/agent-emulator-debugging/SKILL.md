---
name: agent-emulator-debugging
description: Efficient app-driving workflow for the real Flutter app on emulator or Linux/macOS desktop via VM service extensions, including common blocker recovery.
---
# Agent App Driving

Drive the **real** app to inspect runtime state and unblock UI/action dead-ends, via the `ext.nothingness.*` VM-service extensions wrapped by `scripts/drive.py`. Works against an Android emulator/device (through `adb`) or a Flutter **desktop** build (`-d linux`/`-d macos`, no ADB) — the extension surface is identical on both. This file is the operational entry point; for the per-extension reference and architecture see `docs/agent-driven-debugging.md`.

`D=.claude/skills/agent-emulator-debugging/scripts/drive.py` is used as shorthand below.

## Step 0: `drive.py preflight`

**Don't assume which targets exist — detect them.** Which platforms you can/can't see depends on the host (WSL is a feature of *this* env, not a law), so start every session with:

```bash
$D preflight
```

It probes, with no hardcoded verdicts, and prints JSON (stdout) plus a one-line human summary (stderr):

- **host** — OS/platform and whether this is WSL (`/proc/version`).
- **flutter_devices** — `flutter devices --machine`; which targets exist (linux / android / chrome).
- **adb** — an adb on PATH or `$ANDROID_HOME/platform-tools/adb`, and `adb devices` output.
- **live_run** — is `/tmp/flutter_run.log` (or `$DRIVE_RUN_LOG`) present/fresh, does it carry a VM URI, and does the VM actually answer (isolate + extension count)?
- **recommendation** — the `DRIVE_TARGET` that would be used and the exact next command.

Follow its `recommendation.next`. The three shapes:

- **`ready`** → a live VM answers. Set the reported `DRIVE_TARGET` and go (`$D inspect`).
- **`needs-launch`** → a target exists but nothing is running yet. It prints the launch line (Linux fifo+`flutter run`, or the x86_64 Android line). See **Appendix: target variants** for the full launch recipes.
- **`no-target`** → nothing reachable; it tells you how to start one.

The agent-driving entrypoint is always `dev/main_debug.dart` (`flutter run -t dev/main_debug.dart`): it installs the harness onto the `lib/debug_hooks.dart` seam, then runs the real `lib/main.dart`, so the extensions register. Plain `flutter run` (lib/main.dart) exposes **no** extensions; never use `dev/main_test.dart` (that's for `integration_test/` with fake transport).

First time on a host: `uv sync` once (creates `.venv`, installs `websockets`). `drive.py` also carries a PEP 723 block + `uv run --script` shebang, so `./drive.py …` works before `uv sync`.

## Command reference

```bash
export DRIVE_TARGET=linux   # whatever preflight reported; or unset for the sniff/Android default

# Discovery / contract
$D preflight          # detect environment + recommend next command (Step 0)
$D contract           # list registered ext.nothingness.* names + count (never hardcode it)

# State + UI
$D inspect            # router + library + playback + overflow ring buffer
$D tree 40            # widget tree as text
$D overflows          # FlutterError.onError ring buffer
$D shoot before_x     # PNG → .tmp/agent_shots/before_x.png (adb screencap on android,
                      # ext.nothingness.screenshot on desktop)

# Navigation (Void shell)
$D screen void                                # active hero: spectrum|polo|dot|void
$D variant dark                               # dark|light|system
$D mode own                                   # own|background
$D nav /home/user/Music                       # navigate the library to a path
$D up                                         # navigateVoidUp
$D settings open                              # settings sheet open|close
$D permit                                     # programmatic library permission (no-op on desktop)

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

# Lifecycle
$D reload                                     # hot reload (sends `r` to /tmp/flutter_input)
$D restart                                    # hot restart
$D reset                                      # Android only; refuses on desktop / a live run

# Audio focus simulation (cheap; safe on a live run)
$D call ext.nothingness.simulateInterruption phase=begin kind=pause
$D call ext.nothingness.simulateNoisy
$D logcat 500                                 # adb logcat (android); /tmp/flutter_run.log (desktop)
$D replay smoke.txt                           # one drive.py invocation per line

# Runtime inspection (look inside a running build)
$D probe hero-song                            # live rendered text + resolved TextStyle for ValueKey<String>
$D frames --clear                             # reset frame-timing window; drive; then `frames` for jank counts
$D timeline --clear                           # arm VM timeline; drive; then `timeline` (per-name spans + agent.skip markers)
$D profile --seconds 2                        # raw getCpuSamples over a window; top self-time fns; no isolate pause
$D breakpoint --line 692 --watch _track.path --trigger prev   # TRUE breakpoint + var watch; run ALONE (see Hazards)
```

For any extension not yet wrapped, `$D call ext.nothingness.<method> k=v k=v …` calls it with arbitrary params (the **fully-qualified** name is required). The exact registered set + count is whatever `$D contract` reports against the running build — don't quote a fixed number. Per-extension params/returns live in `docs/agent-driven-debugging.md`.

The five runtime-inspection lenses (`probe`/`frames`/`timeline`/`profile`/`breakpoint`) are detailed — with their caveats — in `docs/agent-driven-debugging.md`. `probe`/`frames` wrap `ext.nothingness.*`; `timeline`/`profile`/`breakpoint` are raw VM-service RPCs.

## Which lens when

| Symptom | Reach for |
|---|---|
| Stuck navigating / can't find a control | `tree` (hierarchy + keys), `tapByKey`, `nav`/`up`/`screen` |
| Wrong pixels / label rendered wrong | `probe <key>` (live text + resolved TextStyle), `shoot` (PNG) |
| Slow / janky / a "hang" | `timeline` (what ran on the UI isolate), `profile` (CPU hot spot), `frames` (visible-rebuild jank — Android/real device) |
| Need a live variable at a point in code | `breakpoint --line N --watch expr` (run ALONE) |
| Layout overflow / errors | `overflows`, `emulate <preset>` to repro a portrait phone |
| Audio focus / route behavior | `call ext.nothingness.simulateInterruption` / `simulateNoisy`, then `inspect` |

## Hazards

- **Cadence ≤5/s with jitter** for mutating RPCs (`setSetting`/`setPreference` cost ~140 ms each on emulator). Above ~7/s the response queue backs up and *looks* like a wedged isolate (it just hasn't drained). Hammering the same path (20+ ops <100 ms) belongs in a widget test (`test/p6_adversarial_test.dart`), not the VM service. Recovery if a session hangs: `rm .claude/skills/agent-emulator-debugging/scripts/.vm_ws.txt && $D restart`.
- **Never kill the live `flutter run`.** No `adb shell am force-stop`, `pm clear`, or `pm revoke` against `com.saplin.nothingness` — they trigger `Lost connection to device` + a 60-90 s rebuild. `$D reset` wraps the same hazard, so it refuses (exit 1) when a live run is detected; pass `--force` only if you accept the rebuild. To reset isolate state without wiping app data, use `$D restart` (hot restart). For audio-focus/transport exercises use the cheap side-channel: `$D call ext.nothingness.simulateInterruption …`, `$D pause`/`$D resume`.
- **Velocity-gated gestures need widget tests.** `adb shell input swipe` injects fixed-cadence synthetic events whose computed velocity is far below a real flick, so hero swipes / `PageView` flings / dismissibles silently no-op. Don't chase them via adb/VM service — regress with `tester.fling(finder, Offset(dx, 0), velocity)` (see `test/screens/void_screen_test.dart`, B-027). ADB swipes are fine for coarse distance-only pan/scroll.
- **`breakpoint` pauses the UI isolate → run it ALONE.** While paused, *every* `ext.nothingness.*` extension (and any other driver) is frozen — never run it concurrently with another `drive.py` call. It always `removeBreakpoint`+`resume`s in a `finally`; if orphaned, recover with `rm .vm_ws.txt && $D restart`. `--trigger next` no-ops at the last queue index — use `--trigger prev` from the end.
- **`frames` is empty on the headless Linux build.** `addTimingsCallback` fires only for on-screen compositor frames; background-only activity (a skip storm with no visible change) leaves `count=0`. It populates on real UI churn (navigation, hero rebuilds) and is the primary jank lens on Android. On Linux, prove UI-isolate blocking with `timeline`+`breakpoint`.

## Common blockers (fast recovery)

1. **"could not find Dart VM service URI"** — the app isn't in debug mode (release build / `flutter run` exited), or `.vm_ws.txt` points at a dead session. Run `$D preflight` to see what's actually reachable; delete the cache and relaunch.
2. **Install fails `INSTALL_FAILED_UPDATE_INCOMPATIBLE`** (Android) — uninstall the package, then re-run `flutter run`.
3. **Queue empty after reinstall** — `queueLen=0`; queue real files via `$D play <path>` or the Appendix `adb push` snippet.
4. **`SoLoudFileNotFoundException` for `/sdcard/...`** (Android emulator) — push a host file into the sandbox: `adb -s <device> push <host> /data/user/0/com.saplin.nothingness/files/<name>`, then `$D play /data/user/0/com.saplin.nothingness/files/<name>`.
5. **`Permissions Required` overlay** (Android) — run the Appendix `pm grant` loop, or `$D permit`.
6. **Can't tap a control via `tapByKey`** — the production widget has no `ValueKey<String>`. Drive via `drive.py` (settings/nav/pref) or `adb shell uiautomator dump` + tap by bounds.
7. **`reload` reports "no changes detected"** — hot reload skips `initState` / static / top-level changes; use `$D restart` or a full rebuild.

## Minimal drive loop

1. Read baseline (`$D inspect`).
2. Apply precondition (queue/permission/screen).
3. Trigger one action.
4. Read state immediately.
5. Assert only required fields (index, isPlaying, title, position).

## Appendix: target variants

Moved out of the happy path — `drive.py preflight` tells you which of these applies.

### Target selection (how `DRIVE_TARGET` resolves)

`drive.py` picks its target from, in order: (1) `DRIVE_TARGET={android|linux|macos}`; (2) sniffing `/tmp/flutter_run.log` for `Launching … on Linux|macOS|Android`; (3) default `android`. On `linux`/`macos`, ADB is bypassed, `shoot` rasterizes via `ext.nothingness.screenshot`, `logcat` tails the run log, and `reset` refuses. **Which of these targets is actually reachable is a `preflight` output, not an assumption** — drive.py never hard-asserts "emulator unavailable" or "must use linux".

### Linux / macOS desktop (no ADB)

```bash
# One-time per host: a fifo + a writer that holds it open (so reload/restart work)
[ -p /tmp/flutter_input ] || mkfifo /tmp/flutter_input
nohup sleep infinity > /tmp/flutter_input &
# Launch (Linux shown; -d macos is identical)
nohup flutter run -d linux --debug -t dev/main_debug.dart \
    < /tmp/flutter_input > /tmp/flutter_run.log 2>&1 &
export DRIVE_TARGET=linux
$D inspect
```

Library permissions are a no-op on desktop; stage audio by passing any readable absolute host path to `$D play`. The only feature gap vs Android is MediaStore-backed library scans (Android-only); desktop is folder-based.

### Android (emulator or device), x86_64

On an x86_64 emulator you **must** build x86_64. This project's `android/app/build.gradle.kts` defaults `target-platform`/abiFilters to the device ABI (arm64 on release for size); a default `flutter run` cross-compiles `flutter_soloud` for arm64, which fails on the snap Flutter toolchain (host glibc headers leak into the NDK aarch64 sysroot — **B-045**). Set the ABI explicitly:

```bash
CI_EMULATOR_ABI=x86_64 flutter run -d emulator-5554 --debug -t dev/main_debug.dart
```

Then prepare the device once (idempotent — fine to re-run after a reinstall):

```bash
for P in RECORD_AUDIO READ_MEDIA_AUDIO READ_EXTERNAL_STORAGE POST_NOTIFICATIONS; do
  adb -s emulator-5554 shell pm grant com.saplin.nothingness "android.permission.$P" || true
done
adb -s emulator-5554 push .tmp/test_tone.wav \
    /data/user/0/com.saplin.nothingness/files/test_tone.wav
$D play /data/user/0/com.saplin.nothingness/files/test_tone.wav
```

**Android alongside a live Linux session** (parallel regression): drive.py resolves the VM URI from the run log, defaulting to `/tmp/flutter_run.log`. If a Linux session owns that path, point Android at its own log so it doesn't read the stale Linux URI:

```bash
CI_EMULATOR_ABI=x86_64 flutter run -d emulator-5554 --debug -t dev/main_debug.dart < /dev/null > /tmp/flutter_run_android.log 2>&1 &
export DRIVE_TARGET=android DRIVE_RUN_LOG=/tmp/flutter_run_android.log
```

### WSL2 + Windows-hosted emulator (only if preflight shows WSL + no working local adb)

This is **conditional**, not the default story: only when `preflight` reports `host.is_wsl=true` **and** adb can't reach an emulator locally. Bridge to the Windows adb server:

```bash
"/mnt/c/Users/<windows-user>/AppData/Local/Android/Sdk/platform-tools/adb.exe" -a start-server
HOST_IP=$(ip route | awk '/default/ {print $3; exit}')
ADB_SERVER_SOCKET=tcp:${HOST_IP}:5037 CI_EMULATOR_ABI=x86_64 flutter run -d emulator-5554 --debug -t dev/main_debug.dart
```

If `adb devices` shows nothing from WSL2, run the `wsl2-adb-setup` skill first. If the emulator is flaky on this host (a recurring x86 WSL2 issue), prefer the Linux desktop path above — every drive.py command except `reset` and Android perm grants works identically without ADB.

Reference: `docs/agent-driven-debugging.md` (extension reference + architecture), `docs/regression-testing-playbook.md` (QA process).
