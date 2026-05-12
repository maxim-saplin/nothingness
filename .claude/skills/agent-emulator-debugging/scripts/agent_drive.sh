#!/usr/bin/env bash
set -euo pipefail

usage() {
  cat <<'EOF'
Usage: .claude/skills/agent-emulator-debugging/scripts/agent_drive.sh --base <url> <command> [options]

Commands:
  state
  settings
  play
  pause
  next
  prev
  set-queue --paths <comma-separated> [--start-index N]
  set-setting --name <setting> --value <value>
  widget-tree [--depth N]

Examples:
  BASE=http://127.0.0.1:PORT/AUTH= .claude/skills/agent-emulator-debugging/scripts/agent_drive.sh state
  .claude/skills/agent-emulator-debugging/scripts/agent_drive.sh --base http://127.0.0.1:PORT/AUTH= play
  .claude/skills/agent-emulator-debugging/scripts/agent_drive.sh --base http://127.0.0.1:PORT/AUTH= set-queue --paths /sdcard/Music/a.mp3,/sdcard/Music/b.mp3
  .claude/skills/agent-emulator-debugging/scripts/agent_drive.sh --base http://127.0.0.1:PORT/AUTH= set-setting --name fullScreen --value true
  .claude/skills/agent-emulator-debugging/scripts/agent_drive.sh --base http://127.0.0.1:PORT/AUTH= widget-tree --depth 20
EOF
}

BASE="${BASE:-}"
CMD=""
PATHS=""
START_INDEX=0
DEPTH=50
SETTING_NAME=""
SETTING_VALUE=""

while [[ $# -gt 0 ]]; do
  case "$1" in
    --base)
      BASE="${2:-}"
      shift 2
      ;;
    --paths)
      PATHS="${2:-}"
      shift 2
      ;;
    --start-index)
      START_INDEX="${2:-}"
      shift 2
      ;;
    --depth)
      DEPTH="${2:-}"
      shift 2
      ;;
    --name)
      SETTING_NAME="${2:-}"
      shift 2
      ;;
    --value)
      SETTING_VALUE="${2:-}"
      shift 2
      ;;
    -h|--help)
      usage
      exit 0
      ;;
    *)
      CMD="$1"
      shift
      break
      ;;
  esac
done

case "$CMD" in
  set-queue)
    while [[ $# -gt 0 ]]; do
      case "$1" in
        --paths)
          PATHS="${2:-}"
          shift 2
          ;;
        --start-index)
          START_INDEX="${2:-}"
          shift 2
          ;;
        *)
          echo "Unknown arg for set-queue: $1" >&2
          exit 2
          ;;
      esac
    done
    ;;
  set-setting)
    while [[ $# -gt 0 ]]; do
      case "$1" in
        --name)
          SETTING_NAME="${2:-}"
          shift 2
          ;;
        --value)
          SETTING_VALUE="${2:-}"
          shift 2
          ;;
        *)
          echo "Unknown arg for set-setting: $1" >&2
          exit 2
          ;;
      esac
    done
    ;;
  widget-tree)
    while [[ $# -gt 0 ]]; do
      case "$1" in
        --depth)
          DEPTH="${2:-}"
          shift 2
          ;;
        *)
          echo "Unknown arg for widget-tree: $1" >&2
          exit 2
          ;;
      esac
    done
    ;;
  state|settings|play|pause|next|prev)
    if [[ $# -gt 0 ]]; then
      echo "Unexpected extra args for ${CMD}: $*" >&2
      exit 2
    fi
    ;;
  "")
    ;;
  *)
    echo "Unknown command: ${CMD}" >&2
    usage
    exit 1
    ;;
esac

if [[ -z "$CMD" ]]; then
  usage
  exit 1
fi

if [[ -z "$BASE" ]]; then
  echo "BASE is required (use --base or set BASE=...)." >&2
  exit 1
fi

if ! command -v python3 >/dev/null 2>&1; then
  echo "python3 is required" >&2
  exit 1
fi

BASE="${BASE%/}"

get_isolate() {
  python3 - "$BASE" <<'PY'
import json
import sys
import urllib.request

base = sys.argv[1]
with urllib.request.urlopen(base + '/getVM', timeout=10) as resp:
    vm = json.load(resp)

isolate = next(i for i in vm['result']['isolates'] if i['name'] == 'main')
print(isolate['id'])
PY
}

ISOLATE="$(get_isolate)"

call_ext() {
  local name="$1"
  local query="${2:-}"
  python3 - "$BASE" "$name" "$ISOLATE" "$query" <<'PY'
import json
import sys
import urllib.parse
import urllib.request

base, name, isolate, raw_query = sys.argv[1:5]
params = {'isolateId': isolate}
if raw_query:
    for key, value in urllib.parse.parse_qsl(raw_query, keep_blank_values=True):
        params[key] = value

query = urllib.parse.urlencode(params)
url = f"{base}/ext.nothingness.{name}?{query}"
with urllib.request.urlopen(url, timeout=15) as resp:
    payload = json.load(resp)

if 'error' in payload:
    details = payload['error'].get('data', {}).get('details', '')
    message = payload['error'].get('message', 'unknown error')
    if details:
        print(f"error: {message}: {details}", file=sys.stderr)
    else:
        print(f"error: {message}", file=sys.stderr)
    raise SystemExit(1)

print(json.dumps(payload['result']))
PY
}

case "$CMD" in
  state)
    call_ext "getPlaybackState" \
      | python3 -c "import sys,json; s=json.load(sys.stdin); print(json.dumps({'isPlaying': s['isPlaying'], 'currentIndex': s['currentIndex'], 'queueLength': s['queueLength'], 'spectrumNonZero': s['spectrumNonZero']}))"
    ;;
  settings)
    call_ext "getSettings" \
      | python3 -c "import sys,json; s=json.load(sys.stdin); print(json.dumps({'screenType': s.get('screenType'), 'screenName': s.get('screenName'), 'fullScreen': s.get('fullScreen'), 'debugLayout': s.get('debugLayout'), 'useFilenameForMetadata': s.get('useFilenameForMetadata'), 'audioSource': s.get('spectrumSettings', {}).get('audioSource'), 'barCount': s.get('spectrumSettings', {}).get('barCount')}))"
    ;;
  play|pause|next|prev)
    call_ext "$CMD" | python3 -c "import sys,json; print(json.dumps(json.load(sys.stdin)))"
    ;;
  set-queue)
    if [[ -z "$PATHS" ]]; then
      echo "set-queue requires --paths." >&2
      exit 1
    fi
    call_ext "setQueue" "paths=${PATHS}&startIndex=${START_INDEX}" \
      | python3 -c "import sys,json; print(json.dumps(json.load(sys.stdin)))"
    ;;
  set-setting)
    if [[ -z "$SETTING_NAME" || -z "$SETTING_VALUE" ]]; then
      echo "set-setting requires --name and --value." >&2
      exit 1
    fi
    call_ext "setSetting" "name=${SETTING_NAME}&value=${SETTING_VALUE}" \
      | python3 -c "import sys,json; print(json.dumps(json.load(sys.stdin)))"
    ;;
  widget-tree)
    call_ext "getWidgetTree" "depth=${DEPTH}" \
      | python3 -c "import sys,json; print(json.load(sys.stdin)['tree'])"
    ;;
esac
