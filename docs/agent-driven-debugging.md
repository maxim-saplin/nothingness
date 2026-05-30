# Agent-Driven Debugging via VM Service Extensions

Date: 2026-02-10
Owner: Nothingness

## Overview

The app exposes custom Dart VM service extensions under `ext.nothingness.*` that allow an external agent (AI or script) to fully drive the app in debug mode — reading state, triggering actions, and inspecting the UI — without screenshots or user interaction.

Extensions live in the out-of-tree harness `dev/agent_service.dart` (no longer in `lib/`). The production entrypoint `lib/main.dart` does **not** import the harness; it only populates the thin `lib/debug_hooks.dart` seam in debug builds. To attach the harness, launch the agent-driving entrypoint:

```bash
flutter run -t dev/main_debug.dart
```

`dev/main_debug.dart` calls `AgentService.install()` (which wires `DebugHooks.onAppReady`) and then runs the normal `lib/main.dart` app, so the `ext.nothingness.*` extensions register once init completes. The plain `lib/main.dart` entrypoint will **not** expose these extensions.

`dev/main_test.dart` does **not** include AgentService — it is exclusively for deterministic `integration_test/` automation with fake transport and should never be used for agent-driven debugging.

Extensions are **only active in debug mode** (`kDebugMode` guard) and are completely stripped from release builds.

## Architecture

```
┌─────────────────────────────────────────────────┐
│  AI Agent / Script (terminal, Python, etc.)     │
│  Speaks HTTP GET or WebSocket JSON-RPC          │
└────────────────┬────────────────────────────────┘
                 │  curl / websocket
                 ▼
┌─────────────────────────────────────────────────┐
│  Dart VM Service (observatory)                  │
│  ws://127.0.0.1:<port>/<auth>/ws                │
│  http://127.0.0.1:<port>/<auth>/                │
└────────────────┬────────────────────────────────┘
                 │  ext.nothingness.*
                 ▼
┌─────────────────────────────────────────────────┐
│  AgentService (dev/agent_service.dart)  │
│  ├── Generic: getWidgetTree, tapByKey, ...      │
│  └── Domain:  getPlaybackState, play, ...       │
└────────────────┬────────────────────────────────┘
                 │
                 ▼
┌─────────────────────────────────────────────────┐
│  App internals                                  │
│  AudioPlayerProvider, SettingsService, etc.      │
└─────────────────────────────────────────────────┘
```

## Primary CLI: `drive.py`

For most workflows, drive the app via `drive.py` rather than raw `curl`. It auto-discovers the VM service WebSocket (scanning logcat + `/tmp/flutter_run.log`), caches it between calls, resolves the main isolate, wraps every `ext.nothingness.*` extension as a typed subcommand, and offers screenshot, hot-reload, hot-restart, and clear-data conveniences.

The script is managed by `uv`: it carries a PEP 723 inline metadata block and a `#!/usr/bin/env -S uv run --script` shebang, so `./drive.py …` works directly with no setup. For a stable project venv (useful for IDE completion), run `uv sync` once after checkout — it creates `.venv/` and installs `websockets` from the repo-root `pyproject.toml`.

```bash
# All examples assume the app is running in debug mode on emulator-5554.

# State
.claude/skills/agent-emulator-debugging/scripts/drive.py inspect
.claude/skills/agent-emulator-debugging/scripts/drive.py tree 40
.claude/skills/agent-emulator-debugging/scripts/drive.py overflows

# Navigation
.claude/skills/agent-emulator-debugging/scripts/drive.py screen void
.claude/skills/agent-emulator-debugging/scripts/drive.py nav /storage/emulated/0/Music
.claude/skills/agent-emulator-debugging/scripts/drive.py up
.claude/skills/agent-emulator-debugging/scripts/drive.py settings open
.claude/skills/agent-emulator-debugging/scripts/drive.py settings close

# Theming
.claude/skills/agent-emulator-debugging/scripts/drive.py variant dark
.claude/skills/agent-emulator-debugging/scripts/drive.py mode own

# Playback
.claude/skills/agent-emulator-debugging/scripts/drive.py play /sdcard/Music/foo.mp3
.claude/skills/agent-emulator-debugging/scripts/drive.py pause
.claude/skills/agent-emulator-debugging/scripts/drive.py resume
.claude/skills/agent-emulator-debugging/scripts/drive.py next
.claude/skills/agent-emulator-debugging/scripts/drive.py prev

# Preferences
.claude/skills/agent-emulator-debugging/scripts/drive.py pref void_hint_shown=false:bool
.claude/skills/agent-emulator-debugging/scripts/drive.py clearpref void_hint_shown

# Lifecycle
.claude/skills/agent-emulator-debugging/scripts/drive.py reload      # hot reload (via /tmp/flutter_input fifo)
.claude/skills/agent-emulator-debugging/scripts/drive.py restart     # hot restart
.claude/skills/agent-emulator-debugging/scripts/drive.py reset       # force-stop + clear data + cold launch

# Diagnostics
.claude/skills/agent-emulator-debugging/scripts/drive.py shoot before_x       # → .tmp/agent_shots/before_x.png
.claude/skills/agent-emulator-debugging/scripts/drive.py logcat 500
.claude/skills/agent-emulator-debugging/scripts/drive.py call setSetting name=fullScreen value=true  # arbitrary extension
.claude/skills/agent-emulator-debugging/scripts/drive.py replay script.txt    # one extension call per newline
```

The cache lives next to the script as `.vm_ws.txt`. If you kill `flutter run` and restart it, `drive.py reset` (or simply deleting the cache) refreshes it.

Subcommand source: `.claude/skills/agent-emulator-debugging/scripts/drive.py`. For extensions drive.py doesn't yet wrap, use `drive.py call <ext> k=v k=v …` to make an arbitrary `ext.nothingness.*` call — no need to drop down to the raw `curl` recipe below.

## Quick Start

### 1. Launch the app in debug mode

```bash
# Android emulator
flutter run -d emulator-5554 --debug -t dev/main_debug.dart

# macOS
flutter run -d macos --debug -t dev/main_debug.dart
```

> The `-t dev/main_debug.dart` entrypoint is **required** for agent-driven debugging — it installs the harness onto the `lib/debug_hooks.dart` seam so the `ext.nothingness.*` extensions register. Plain `lib/main.dart` (the default `flutter run`) ships without the harness and exposes no extensions.

> **Never use `-t dev/main_test.dart`** for agent-driven debugging. That entrypoint uses fake transport with no real audio — it exists only for `integration_test/` deterministic test automation.

The output contains the observatory URL:
```
A Dart VM Service on sdk gphone64 arm64 is available at: http://127.0.0.1:PORT/AUTH=/
```

#### 1a. (Android) Prepare device — runtime permissions + sandbox audio files

Fresh-installed Android builds stop at the in-app `Permissions Required` overlay until the user taps `Grant Permissions` and approves the OS dialog. SoLoud also can't open shared-storage paths like `/sdcard/...` on emulators (raises `SoLoudFileNotFoundException`) — files have to live under the app's private dir.

Use raw `adb` for both — idempotent and works pre- or post-launch:

```bash
# Grant runtime perms (idempotent)
for P in RECORD_AUDIO READ_MEDIA_AUDIO READ_EXTERNAL_STORAGE POST_NOTIFICATIONS; do
  adb -s emulator-5554 shell pm grant com.saplin.nothingness "android.permission.$P" || true
done

# Stage one or more host audio files into the app sandbox
adb -s emulator-5554 push .tmp/test_tone.wav \
    /data/user/0/com.saplin.nothingness/files/test_tone.wav
adb -s emulator-5554 push /path/to/another.mp3 \
    /data/user/0/com.saplin.nothingness/files/another.mp3
```

After staging `foo.wav`, queue it as `/data/user/0/com.saplin.nothingness/files/foo.wav`.

Permissions granted: `RECORD_AUDIO`, `READ_MEDIA_AUDIO`, `READ_EXTERNAL_STORAGE`, `POST_NOTIFICATIONS`. `pm grant` requires no UI interaction.

Linux/macOS desktop has no sandbox — skip both steps and pass any readable absolute host path to `drive.py play` directly.

### 2. Extract the base URL

From the flutter run output, extract:
- `BASE=http://127.0.0.1:<port>/<auth>=`

### 2b. Helper script (preferred)

`drive.py` covers every common workflow (state inspection, queue setup, widget tree, screenshots, hot reload, replay scripts) for both Android and Linux/macOS desktop. See `.claude/skills/agent-emulator-debugging/SKILL.md` for the full subcommand surface.

```bash
D=.claude/skills/agent-emulator-debugging/scripts/drive.py

$D inspect                                       # router/library/playback/overflows
$D play /data/user/0/com.saplin.nothingness/files/track1.mp3
$D tree 20                                       # widget tree, depth-capped
```

### 3. Get the isolate ID

```bash
python3 - <<'PY'
import json
import urllib.request

with urllib.request.urlopen(f"${BASE}/getVM") as resp:
  vm = json.load(resp)

iso = [i for i in vm['result']['isolates'] if i['name'] == 'main'][0]
print(iso['id'])
PY
```

### 4. Call extensions

All extensions use HTTP GET:

```bash
ISOLATE="isolates/<id>"

# Read state
curl -s "${BASE}/ext.nothingness.getPlaybackState?isolateId=${ISOLATE}"
curl -s "${BASE}/ext.nothingness.getSettings?isolateId=${ISOLATE}"
curl -s "${BASE}/ext.nothingness.getWidgetTree?isolateId=${ISOLATE}&depth=50"

# Trigger actions
curl -s "${BASE}/ext.nothingness.play?isolateId=${ISOLATE}"
curl -s "${BASE}/ext.nothingness.pause?isolateId=${ISOLATE}"
curl -s "${BASE}/ext.nothingness.next?isolateId=${ISOLATE}"
curl -s "${BASE}/ext.nothingness.prev?isolateId=${ISOLATE}"
curl -s "${BASE}/ext.nothingness.tapByKey?isolateId=${ISOLATE}&key=test.playPause"

# Configure
curl -s "${BASE}/ext.nothingness.setSetting?isolateId=${ISOLATE}&name=debugLayout&value=true"
curl -s "${BASE}/ext.nothingness.setQueue?isolateId=${ISOLATE}&paths=/sdcard/a.mp3,/sdcard/b.mp3&startIndex=0"
```

## Extension Reference

### Generic Primitives

| Extension | Params | Returns | Purpose |
|---|---|---|---|
| `getWidgetTree` | `depth` (optional, line limit) | `{tree: "..."}` | Full element tree as text. Primary UI inspection tool. |
| `getSemantics` | — | `{semantics: "..."}` | Semantics tree (requires accessibility enabled). |
| `tapByKey` | `key` (ValueKey string) | `{tapped: "key"}` | Find widget by `ValueKey<String>` and invoke its tap callback. |
| `getSettings` | — | Full settings JSON | Read current app settings, including screen and spectrum configuration. |
| `setSetting` | `name`, `value` | `{set, value}` | Change a setting. Supported: `fullScreen`, `debugLayout`, `useFilenameForMetadata`, `audioDiagnosticsOverlay`. |

### Playback Shortcuts

| Extension | Params | Returns | Purpose |
|---|---|---|---|
| `getPlaybackState` | — | Full state JSON | Playing status, queue, current track, spectrum data summary. |
| `play` | — | `{isPlaying: true}` | Start playback (no-op if already playing). |
| `pause` | — | `{isPlaying: false}` | Pause playback (no-op if already paused). |
| `next` | — | `{ok: true}` | Skip to next track. |
| `prev` | — | `{ok: true}` | Skip to previous track. |
| `setQueue` | `paths` (comma-separated), `startIndex` (optional) | `{queued: N}` | Load tracks into queue and start at given index. |

### Audio Diagnostics

| Extension | Params | Returns | Purpose |
|---|---|---|---|
| `getDiagnostics` | — | `{snapshot: {...}}` | Full `PlaybackController.diagnosticsSnapshot()` (queue state, last error, recent logs, **audioEvents** ring buffer). |
| `getAudioEvents` | — | `{audioEvents: [...]}` | Just the audio-event ring buffer (timestamped lines for interruption / noisy / devicesChanged / load / ended / error). |
| `simulateInterruption` | `phase=begin\|end`, `kind=pause\|duck\|unknown` | `{phase, kind}` | Drive `PlaybackController._onInterruption` directly. Equivalent to a real OS audio focus event. |
| `simulateNoisy` | — | `{simulated: "noisy"}` | Drive `PlaybackController._onBecomingNoisy` directly (headphones/BT yanked). |

### Void Shell / Library Navigation

These extensions were added during the `ui-revamp` arc to drive the unified Void chrome and the library browser.

| Extension | Params | Returns | Purpose |
|---|---|---|---|
| `getRouterState` | — | Active hero, immersive flag, settings-sheet state | Snapshot of the `VoidScreen` shell. |
| `getLibraryState` | — | Current path, listing, permission state | Snapshot of `LibraryController`. |
| `navigateVoid` | `path` | `{path: "..."}` | Navigate the library browser to `path` (Android: MediaStore-derived; macOS: filesystem). |
| `navigateVoidUp` | — | `{path: "..."}` | Pop one level up in the library tree. |
| `openSettingsSheet` / `closeSettingsSheet` | — | `{open: true/false}` | Toggle the in-shell settings sheet. |
| `playTrackByPath` | `path` | `{queued, started}` | Equivalent to tapping a track in the browser; queues + starts it. |
| `setPreference` | `name`, `value` (typed: `value=foo:bool`/`int`/`string`) | `{set, value}` | Write any `SettingsService` field at runtime. Broader than `setSetting`. |
| `clearPreference` | `name` | `{cleared: true}` | Remove a preference key (back to default). |
| `requestLibraryPermission` | — | `{granted: bool}` | Programmatically trigger the storage / audio permission flow on Android. |
| `getOverflowReports` | `clear=true` (optional) | `{reports: [...]}` | Returns the `FlutterError.onError` ring buffer, including layout overflow incidents. |

Total: **26 extensions** registered in `dev/agent_service.dart:67-145`. Use `drive.py` (see top of this doc) for typed access from the command line.

### Response Format

All responses follow JSON-RPC 2.0:

**Success:**
```json
{"jsonrpc": "2.0", "result": { ... }, "id": ""}
```

**Error:**
```json
{"jsonrpc": "2.0", "error": {"code": -32000, "message": "Server error", "data": {"details": "..."}}, "id": ""}
```

## Stable UI Keys (for tapByKey)

To use `tapByKey` with the real app, add `ValueKey<String>` to production widgets you want agents to interact with. The keys below are only available in the `dev/main_test.dart` test overlay and are **not** present in production builds:

| Key | Widget | Available in |
|---|---|---|
| `test.dump` | Diagnostics dump button | `dev/main_test.dart` only |
| `test.emitEnded` | Emit track-ended event | `dev/main_test.dart` only |
| `test.prev` | Previous track | `dev/main_test.dart` only |
| `test.playPause` | Play/pause toggle | `dev/main_test.dart` only |
| `test.next` | Next track | `dev/main_test.dart` only |
| `test.queueItem.<index>` | Queue list item at index | `dev/main_test.dart` only |

For the real app, use `getWidgetTree` to discover the widget hierarchy and add `ValueKey`s to production widgets as needed.

## Example: Audio Interruption (Bug #1) Verification

Verify the phone-call-pause path end-to-end without placing a real call:

```bash
# 1. Set queue + start playback
curl -s "${BASE}/ext.nothingness.setQueue?isolateId=${ISOLATE}&paths=/data/user/0/com.saplin.nothingness/files/t1.mp3,/data/user/0/com.saplin.nothingness/files/t2.mp3"
curl -s "${BASE}/ext.nothingness.play?isolateId=${ISOLATE}"

# 2. Simulate incoming call (transient focus loss)
curl -s "${BASE}/ext.nothingness.simulateInterruption?isolateId=${ISOLATE}&phase=begin&kind=pause"
curl -s "${BASE}/ext.nothingness.getPlaybackState?isolateId=${ISOLATE}" \
  | python3 -c "import sys,json; r=json.load(sys.stdin)['result']; print(f'playing={r[\"isPlaying\"]}')"
# Expected: playing=False

# 3. Simulate call end (focus regain)
curl -s "${BASE}/ext.nothingness.simulateInterruption?isolateId=${ISOLATE}&phase=end&kind=pause"
curl -s "${BASE}/ext.nothingness.getPlaybackState?isolateId=${ISOLATE}" \
  | python3 -c "import sys,json; r=json.load(sys.stdin)['result']; print(f'playing={r[\"isPlaying\"]}')"
# Expected: playing=True

# 4. Simulate headphones/BT unplug
curl -s "${BASE}/ext.nothingness.simulateNoisy?isolateId=${ISOLATE}"
# Expected: playing=False, userIntent=pause (no auto-resume on later focus regain)

# 5. Inspect the audio-event ring buffer
curl -s "${BASE}/ext.nothingness.getAudioEvents?isolateId=${ISOLATE}" | python3 -m json.tool
```

The OS-level focus subscription itself is harder to fake; verify it independently with:

```bash
adb shell dumpsys audio | grep -A2 "Audio Focus stack"
```

The entry should show `pack: com.saplin.nothingness` with `client: ...audio_session.AudioManagerSingleton...` — that's the listener `PlaybackController` is subscribed to via `audio_session`.

## Example: Real-Device BT Route Diagnostics (Bug #2 / #3)

For "spectrum dies / no car audio" reports, the user drives with the diagnostics overlay on; we read the audio-event log afterwards.

```bash
# 1. Enable the in-app overlay (also accessible via Settings → DIAGNOSTICS)
curl -s "${BASE}/ext.nothingness.setSetting?isolateId=${ISOLATE}&name=audioDiagnosticsOverlay&value=true"

# 2. User drives, plugs in / out of BT, hits the problem, opens Logs in app.

# 3. Pull the full diagnostics blob for analysis
curl -s "${BASE}/ext.nothingness.getDiagnostics?isolateId=${ISOLATE}" \
  | python3 -c "import sys,json; print(json.dumps(json.load(sys.stdin)['result']['snapshot']['audioEvents'], indent=2))"
```

Look for `devicesChanged added=…` / `removed=…` lines around the moment audio went silent — that's the route swap the follow-up fix has to handle.

## Example: SoLoud Spectrum Fix Verification

An agent can verify the SoLoud spectrum fix end-to-end without any user interaction:

```bash
# 1. Launch app
flutter run -d emulator-5554 --debug &
# 2. Parse BASE and ISOLATE from output (see above)

# 3. Load tracks
curl -s "${BASE}/ext.nothingness.setQueue?isolateId=${ISOLATE}&paths=/sdcard/Music/track1.mp3,/sdcard/Music/track2.mp3"

# 4. Start playback
curl -s "${BASE}/ext.nothingness.play?isolateId=${ISOLATE}"

# 5. Wait and check spectrum
sleep 2
curl -s "${BASE}/ext.nothingness.getPlaybackState?isolateId=${ISOLATE}" \
  | python3 -c "import sys,json; s=json.load(sys.stdin)['result']; print(f'playing={s[\"isPlaying\"]} spectrum={s[\"spectrumNonZero\"]}')"
# Expected: playing=True spectrum=True
```

If the emulator reports `SoLoudFileNotFoundException` for shared-storage paths like `/sdcard/...`, stage the file into the app sandbox instead:

```bash
adb push track.wav /data/local/tmp/track.wav
adb shell 'run-as com.saplin.nothingness mkdir -p files && run-as com.saplin.nothingness cp /data/local/tmp/track.wav files/track.wav'

curl -s "${BASE}/ext.nothingness.setQueue?isolateId=${ISOLATE}&paths=/data/user/0/com.saplin.nothingness/files/track.wav"
```

## Extending

To add a new extension:

1. Add a handler method in `dev/agent_service.dart`
2. Register it in `AgentService.register()` with `developer.registerExtension('ext.nothingness.<name>', _handler)`
3. Update the count in the `debugPrint` message
4. Document it in this file

Generic primitives (`getWidgetTree`, `tapByKey`) work for any UI without new extensions. Domain shortcuts are optional convenience for frequently-used agent workflows.

## Limitations

- **Debug/profile mode only** — stripped from release builds.
- **Semantics** — requires an accessibility service to be active (or `SemanticsDebugger` widget). Use `getWidgetTree` as the primary UI inspector instead.
- **tapByKey** — only works with widgets that have `ValueKey<String>` and a `GestureDetector` or `InkWell` ancestor. For production UI (non-test overlay), add `ValueKey`s to buttons you want agents to tap.
- **Observatory URL** — changes every launch. Agent must parse it from `flutter run` stdout.
