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
│  PlaybackController, SettingsService, etc.       │
└─────────────────────────────────────────────────┘
```

## Primary CLI: `drive.py`

For most workflows, drive the app via `drive.py` rather than raw `curl`. It auto-discovers the VM service WebSocket (scanning logcat + `/tmp/flutter_run.log`), caches it next to the script (`.vm_ws.txt`), resolves the main isolate, wraps every `ext.nothingness.*` extension as a typed subcommand, and offers screenshot, hot-reload, hot-restart, and clear-data conveniences.

**The operational entry point — `drive.py preflight`/`contract`, the full command surface, the "which lens when" guide, hazards, and per-target launch recipes — lives in `.claude/skills/agent-emulator-debugging/SKILL.md`.** Run `drive.py preflight` first; it detects the host (WSL?), flutter devices, adb, and any live `flutter run`, and recommends the next command. This doc holds the **per-extension reference** (params/returns) and the architecture; the skill holds the command-line workflow. Don't restate the command list here.

The script is managed by `uv`: it carries a PEP 723 inline metadata block and a `#!/usr/bin/env -S uv run --script` shebang, so `./drive.py …` works directly with no setup. For a stable project venv (useful for IDE completion), run `uv sync` once after checkout.

For extensions drive.py doesn't yet wrap, `drive.py call ext.nothingness.<name> k=v k=v …` makes an arbitrary call (fully-qualified name required) — no need to drop down to the raw `curl` recipe below. The exact registered set is whatever `drive.py contract` reports against the running build.

## Quick Start

**Launch + per-target setup (Linux desktop, Android x86_64, WSL adb bridge) and the device-prep `pm grant` / sandbox-push snippets live in the skill** (`.claude/skills/agent-emulator-debugging/SKILL.md` → Step 0 and Appendix). Run `drive.py preflight` and follow its recommendation. The essentials: always launch `-t dev/main_debug.dart` (it wires the harness; plain `flutter run` exposes no extensions, and `dev/main_test.dart` is for `integration_test/` only); extensions are debug-mode only.

The sections below are the **raw VM-service protocol** — useful when you need to talk to the VM directly rather than through `drive.py`.

### 1. Extract the base URL

`flutter run` output contains the observatory URL; extract `BASE=http://127.0.0.1:<port>/<auth>=`:
```
A Dart VM Service on sdk gphone64 arm64 is available at: http://127.0.0.1:PORT/AUTH=/
```

### 2. Get the isolate ID

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
| `setSetting` | `name`, `value` | `{set, value}` | Change a setting. Supported names include `fullScreen`, `debugLayout`, `useFilenameForMetadata`, `screen`, `themeVariant`, `operatingMode`, `uiScale`, `immersive`, `transport`, `browserPresentation`. |

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

### Runtime inspection

| Extension | Params | Returns | Purpose |
|---|---|---|---|
| `probeText` | `key` (ValueKey string) | `{text, style:{fontSize, color (ARGB hex), fontWeight, fontFamily, height, letterSpacing}, widgetType, size:{w,h}}` | Walks the element tree to the `ValueKey<String>(key)` widget's `RenderParagraph` and returns the **live rendered** text + resolved `TextStyle`. Reads what was actually painted, not a `toStringDeep` dump. |
| `getFrameTimings` | `clear=true` (optional) | `{count, janky16, janky33, worstBuildUs, worstRasterUs, worstTotalUs, frames:[…≤200]}` | Frame-timing ring buffer (cap 600) fed by `SchedulerBinding.addTimingsCallback`. `janky16`/`janky33` count frames over 16/33 ms total. `clear=true` starts a fresh measurement window. |

The full set is registered from the `_extensions` map in `dev/agent_service.dart`. **Don't quote a fixed count** — run `drive.py contract` to list the `ext.nothingness.*` names + count the running build actually registered (it reads `getIsolate.extensionRPCs` live). Use `drive.py` (see the skill) for typed access from the command line.

### Runtime inspection perspectives

Five `drive.py` subcommands look *inside* a running build — at painted text, frame timing, the VM timeline, CPU samples, and live variables. The last three are raw VM-service RPCs, not `ext.nothingness.*` calls. The harness also brackets `_next`/`_prev` with `Timeline.startSync('agent.skip')`/`finishSync()` markers (instrumentation only), so skip handlers show up as spans on the timeline.

- **`probe <key>`** → `probeText`. Reach for it to assert what a label *actually rendered* — text and resolved `TextStyle` (size, ARGB color, weight, family, height, letterSpacing) — instead of trusting a tree dump. e.g. `drive.py probe hero-song`.
- **`frames [--clear]`** → `getFrameTimings`. Reach for it for visible-rebuild jank: `frames --clear`, drive the actions, then `frames` and read `janky16`/`janky33`/`worst*Us`. **Caveat:** on the headless Linux desktop build `addTimingsCallback` fires only when on-screen compositor frames are produced, so background-only activity (a skip storm with no visible change) leaves `count=0`. It populates during real UI churn (navigation, hero rebuilds) and is the primary jank lens **on device (Android)**. On Linux, prefer `timeline`+`breakpoint` to prove UI-isolate blocking.
- **`timeline [--clear]`** → raw VM timeline RPCs. `--clear` does `setVMTimelineFlags {recordedStreams:[Dart,Embedder,GC]}` + `clearVMTimeline`; bare returns a per-name `summary` of completed (`dur`) spans plus `marked_spans` (the `agent.skip` spans with `args.dir`). Reach for it to see what ran on the UI isolate during a window. `getVMTimestamp` is unavailable on this VM, so the time origin is derived from `getVMTimeline`.
- **`profile [--seconds N]`** → raw `getCpuSamples` over a window (default 2s); returns `sampleCount` + top self-time `functions`. Does **not** pause the isolate. Reach for it to find a CPU hot spot. (CPU payloads can exceed 8 MiB, so the raw caller uses a 64 MiB frame ceiling.)
- **`breakpoint --line N [--uri <pkg-uri>] [--watch e1,e2] [--trigger next|prev|none] [--timeout S]`** → a **true** breakpoint + variable watch. Default uri `package:nothingness/services/playback_controller.dart`, default line 692 (the `await _loadTrack` UI-isolate await). It sets the breakpoint, fires the trigger fire-and-forget on a separate connection, waits for `PauseBreakpoint`, runs `getStack` + `evaluateInFrame` per `--watch` expr, then **always** `removeBreakpoint`+`resume` in a `finally`. Reach for it for "stop here and inspect variables", not tight loops.

  **Caveats:**
  - **`breakpoint` pauses the UI isolate, which freezes ALL `ext.nothingness.*` extensions.** It must run **ALONE** — never concurrently with any other `drive.py` call or another driver. It always resumes in a `finally`; if a session is ever orphaned, recover with the standard `rm .vm_ws.txt && drive.py restart`.
  - **`--trigger next` no-ops at the last queue index** (`nextOrderIndex()` returns null → no load runs). Use `--trigger prev` from the end, or position the queue so a load actually fires.

(`drive.py call` takes the fully-qualified name — `call ext.nothingness.<method>` — but these five are wrapped subcommands, so you won't need `call` for them.)

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

For "spectrum dies / no car audio" reports, the user drives with the app running; the audio-event ring buffer captures route swaps in-process, and we read it afterwards over the VM service (there is no in-app log viewer).

```bash
# 1. User drives, plugs in / out of BT, hits the problem.

# 2. Pull the full diagnostics blob for analysis
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
3. Document it in the reference table above (no count to maintain — `drive.py contract` reads the live list)

Generic primitives (`getWidgetTree`, `tapByKey`) work for any UI without new extensions. Domain shortcuts are optional convenience for frequently-used agent workflows.

## Limitations

- **Debug/profile mode only** — stripped from release builds.
- **Semantics** — requires an accessibility service to be active (or `SemanticsDebugger` widget). Use `getWidgetTree` as the primary UI inspector instead.
- **tapByKey** — only works with widgets that have `ValueKey<String>` and a `GestureDetector` or `InkWell` ancestor. For production UI (non-test overlay), add `ValueKey`s to buttons you want agents to tap.
- **Observatory URL** — changes every launch. Agent must parse it from `flutter run` stdout.
