# Agent-Driven Debugging via VM Service Extensions

Date: 2026-02-10
Owner: Nothingness

## Overview

The app exposes custom Dart VM service extensions under `ext.nothingness.*` that allow an external agent (AI or script) to fully drive the app in debug mode — reading state, triggering actions, and inspecting the UI — without screenshots or user interaction.

Extensions are registered in `lib/testing/agent_service.dart` and wired into the production entrypoint:
- `lib/main.dart` (debug builds)

`lib/main_test.dart` does **not** include AgentService — it is exclusively for deterministic `integration_test/` automation with fake transport and should never be used for agent-driven debugging.

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
│  AgentService (lib/testing/agent_service.dart)  │
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

## Quick Start

### 1. Launch the app in debug mode

```bash
# Android emulator
flutter run -d emulator-5554 --debug

# macOS
flutter run -d macos --debug
```

> **Never use `-t lib/main_test.dart`** for agent-driven debugging. That entrypoint uses fake transport with no real audio — it exists only for `integration_test/` deterministic test automation.

The output contains the observatory URL:
```
A Dart VM Service on sdk gphone64 arm64 is available at: http://127.0.0.1:PORT/AUTH=/
```

### 2. Extract the base URL

From the flutter run output, extract:
- `BASE=http://127.0.0.1:<port>/<auth>=`

### 2b. Helper script (optional)

The helper script avoids manual isolate lookups and URL-encodes `setQueue` paths.
Requires `curl` and `python3`.

```bash
chmod +x .claude/skills/agent-emulator-debugging/scripts/agent_drive.sh

BASE=http://127.0.0.1:PORT/AUTH= .claude/skills/agent-emulator-debugging/scripts/agent_drive.sh state
BASE=http://127.0.0.1:PORT/AUTH= .claude/skills/agent-emulator-debugging/scripts/agent_drive.sh set-queue \
  --paths /sdcard/Music/track1.mp3,/sdcard/Music/track2.mp3 \
  --start-index 0
BASE=http://127.0.0.1:PORT/AUTH= .claude/skills/agent-emulator-debugging/scripts/agent_drive.sh play
BASE=http://127.0.0.1:PORT/AUTH= .claude/skills/agent-emulator-debugging/scripts/agent_drive.sh widget-tree --depth 20
```

### 3. Get the isolate ID

```bash
curl -s "${BASE}/getVM" | python3 -c "
import sys, json
vm = json.load(sys.stdin)
iso = [i for i in vm['result']['isolates'] if i['name']=='main'][0]
print(iso['id'])
"
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
| `getSettings` | — | Full settings JSON | Read all app settings (spectrum, screen type, decoder, etc.). |
| `setSetting` | `name`, `value` | `{set, value}` | Change a setting. Supported: `androidSoloudDecoder`, `fullScreen`, `debugLayout`, `useFilenameForMetadata`. |

### Playback Shortcuts

| Extension | Params | Returns | Purpose |
|---|---|---|---|
| `getPlaybackState` | — | Full state JSON | Playing status, queue, current track, spectrum data summary. |
| `play` | — | `{isPlaying: true}` | Start playback (no-op if already playing). |
| `pause` | — | `{isPlaying: false}` | Pause playback (no-op if already paused). |
| `next` | — | `{ok: true}` | Skip to next track. |
| `prev` | — | `{ok: true}` | Skip to previous track. |
| `setQueue` | `paths` (comma-separated), `startIndex` (optional) | `{queued: N}` | Load tracks into queue and start at given index. |

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

To use `tapByKey` with the real app, add `ValueKey<String>` to production widgets you want agents to interact with. The keys below are only available in the `main_test.dart` test overlay and are **not** present in production builds:

| Key | Widget | Available in |
|---|---|---|
| `test.dump` | Diagnostics dump button | `main_test.dart` only |
| `test.emitEnded` | Emit track-ended event | `main_test.dart` only |
| `test.prev` | Previous track | `main_test.dart` only |
| `test.playPause` | Play/pause toggle | `main_test.dart` only |
| `test.next` | Next track | `main_test.dart` only |
| `test.queueItem.<index>` | Queue list item at index | `main_test.dart` only |

For the real app, use `getWidgetTree` to discover the widget hierarchy and add `ValueKey`s to production widgets as needed.

## Example: SoLoud Spectrum Fix Verification

An agent can verify the SoLoud spectrum fix end-to-end without any user interaction:

```bash
# 1. Launch app
flutter run -d emulator-5554 --debug &
# 2. Parse BASE and ISOLATE from output (see above)

# 3. Check SoLoud decoder is enabled
curl -s "${BASE}/ext.nothingness.getSettings?isolateId=${ISOLATE}" \
  | python3 -c "import sys,json; print(json.load(sys.stdin)['result']['androidSoloudDecoder'])"

# 4. Load tracks
curl -s "${BASE}/ext.nothingness.setQueue?isolateId=${ISOLATE}&paths=/sdcard/Music/track1.mp3,/sdcard/Music/track2.mp3"

# 5. Start playback
curl -s "${BASE}/ext.nothingness.play?isolateId=${ISOLATE}"

# 6. Wait and check spectrum
sleep 2
curl -s "${BASE}/ext.nothingness.getPlaybackState?isolateId=${ISOLATE}" \
  | python3 -c "import sys,json; s=json.load(sys.stdin)['result']; print(f'playing={s[\"isPlaying\"]} spectrum={s[\"spectrumNonZero\"]}')"
# Expected: playing=True spectrum=True
```

## Extending

To add a new extension:

1. Add a handler method in `lib/testing/agent_service.dart`
2. Register it in `AgentService.register()` with `developer.registerExtension('ext.nothingness.<name>', _handler)`
3. Update the count in the `debugPrint` message
4. Document it in this file

Generic primitives (`getWidgetTree`, `tapByKey`) work for any UI without new extensions. Domain shortcuts are optional convenience for frequently-used agent workflows.

## Limitations

- **Debug/profile mode only** — stripped from release builds.
- **Semantics** — requires an accessibility service to be active (or `SemanticsDebugger` widget). Use `getWidgetTree` as the primary UI inspector instead.
- **tapByKey** — only works with widgets that have `ValueKey<String>` and a `GestureDetector` or `InkWell` ancestor. For production UI (non-test overlay), add `ValueKey`s to buttons you want agents to tap.
- **Observatory URL** — changes every launch. Agent must parse it from `flutter run` stdout.
