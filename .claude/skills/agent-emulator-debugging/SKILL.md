---
name: agent-emulator-debugging
description: How to drive the real app in debug mode on an emulator via VM service extensions for runtime verification and interaction. Use when verifying fixes, checking UI state, or driving the app on a device.
---
# Agent-Driven Emulator Debugging

**Always use the real app entrypoint (`main.dart`).** Never use `main_test.dart` — that is exclusively for `integration_test/` deterministic test automation with fake transport.

## When to Use
When you need to verify runtime behavior on an emulator/device — e.g. confirming a fix works, checking UI state, or driving the app through a scenario without user interaction.

## Setup (one-time per session)

1. **Launch the real app in debug mode:**
   ```bash
   flutter run -d emulator-5554 --debug
   ```

2. **Parse observatory URL from stdout** — look for:
   ```
   A Dart VM Service on ... is available at: http://127.0.0.1:<PORT>/<AUTH>=/
   ```
   Save as `BASE=http://127.0.0.1:<PORT>/<AUTH>=`

2b. **Helper script (optional):**

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

3. **Get isolate ID:**
   ```bash
   curl -s "${BASE}/getVM" | python3 -c "
   import sys, json
   vm = json.load(sys.stdin)
   iso = [i for i in vm['result']['isolates'] if i['name']=='main'][0]
   print(iso['id'])
   "
   ```
   Save as `ISOLATE=isolates/<id>`

## Reading State

```bash
# Full playback state (playing, queue, current track, spectrum)
curl -s "${BASE}/ext.nothingness.getPlaybackState?isolateId=${ISOLATE}"

# App settings (decoder, screen type, spectrum config)
curl -s "${BASE}/ext.nothingness.getSettings?isolateId=${ISOLATE}"

# Widget tree (primary UI inspection — no screenshots needed)
curl -s "${BASE}/ext.nothingness.getWidgetTree?isolateId=${ISOLATE}&depth=50"
```

## Triggering Actions

```bash
# Playback controls
curl -s "${BASE}/ext.nothingness.play?isolateId=${ISOLATE}"
curl -s "${BASE}/ext.nothingness.pause?isolateId=${ISOLATE}"
curl -s "${BASE}/ext.nothingness.next?isolateId=${ISOLATE}"
curl -s "${BASE}/ext.nothingness.prev?isolateId=${ISOLATE}"

# Load a queue
curl -s "${BASE}/ext.nothingness.setQueue?isolateId=${ISOLATE}&paths=/path/a.mp3,/path/b.mp3&startIndex=0"

# Tap any widget by ValueKey<String>
curl -s "${BASE}/ext.nothingness.tapByKey?isolateId=${ISOLATE}&key=test.playPause"

# Change a setting
curl -s "${BASE}/ext.nothingness.setSetting?isolateId=${ISOLATE}&name=debugLayout&value=true"
```

## Verification Pattern

For any fix or feature, follow this pattern:

1. **Read initial state** via `getPlaybackState` / `getSettings`
2. **Set up preconditions** via `setQueue`, `setSetting`, etc.
3. **Trigger the action** via `play`, `tapByKey`, etc.
4. **Assert on result** by reading state again and checking JSON fields
5. **Inspect UI if needed** via `getWidgetTree`

## Key Rules

- **Always use `main.dart`** — never `main_test.dart` (that is for `integration_test/` only).
- All responses are JSON-RPC 2.0 — parse `result` for success, `error` for failures.
- `getWidgetTree` is the primary UI inspector. Use `depth=N` to limit output lines.
- Real audio files must be on the device. Push with `adb push <file> /sdcard/Music/` if needed.
- Extensions only exist in debug builds — never in release.
- Observatory URL changes every launch — always re-parse it.
- Full reference: `docs/agent-driven-debugging.md`
