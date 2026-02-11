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

if [[ -z "$CMD" ]]; then
  usage
  exit 1
fi

if [[ -z "$BASE" ]]; then
  echo "BASE is required (use --base or set BASE=...)." >&2
  exit 1
fi

BASE="${BASE%/}"

get_isolate() {
  curl -s "${BASE}/getVM" \
    | python3 -c "import sys,json; vm=json.load(sys.stdin); iso=[i for i in vm['result']['isolates'] if i['name']=='main'][0]; print(iso['id'])"
}

ISOLATE="$(get_isolate)"

call_ext() {
  local name="$1"
  curl -s "${BASE}/ext.nothingness.${name}?isolateId=${ISOLATE}"
}

case "$CMD" in
  state)
    call_ext "getPlaybackState" \
      | python3 -c "import sys,json; s=json.load(sys.stdin)['result']; print({'isPlaying': s['isPlaying'], 'currentIndex': s['currentIndex'], 'queueLength': s['queueLength'], 'spectrumNonZero': s['spectrumNonZero']})"
    ;;
  settings)
    call_ext "getSettings" \
      | python3 -c "import sys,json; s=json.load(sys.stdin)['result']; print({'androidSoloudDecoder': s.get('androidSoloudDecoder'), 'fullScreen': s.get('fullScreen'), 'debugLayout': s.get('debugLayout')})"
    ;;
  play|pause|next|prev)
    call_ext "$CMD" | python3 -c "import sys,json; print(json.load(sys.stdin))"
    ;;
  set-queue)
    if [[ -z "$PATHS" ]]; then
      echo "set-queue requires --paths." >&2
      exit 1
    fi
    curl -G -s "${BASE}/ext.nothingness.setQueue" \
      --data-urlencode "isolateId=${ISOLATE}" \
      --data-urlencode "paths=${PATHS}" \
      --data-urlencode "startIndex=${START_INDEX}" \
      | python3 -c "import sys,json; print(json.load(sys.stdin))"
    ;;
  set-setting)
    if [[ -z "$SETTING_NAME" || -z "$SETTING_VALUE" ]]; then
      echo "set-setting requires --name and --value." >&2
      exit 1
    fi
    curl -G -s "${BASE}/ext.nothingness.setSetting" \
      --data-urlencode "isolateId=${ISOLATE}" \
      --data-urlencode "name=${SETTING_NAME}" \
      --data-urlencode "value=${SETTING_VALUE}" \
      | python3 -c "import sys,json; print(json.load(sys.stdin))"
    ;;
  widget-tree)
    curl -G -s "${BASE}/ext.nothingness.getWidgetTree" \
      --data-urlencode "isolateId=${ISOLATE}" \
      --data-urlencode "depth=${DEPTH}" \
      | python3 -c "import sys,json; t=json.load(sys.stdin)['result']['tree']; print(t)"
    ;;
  *)
    echo "Unknown command: ${CMD}" >&2
    usage
    exit 1
    ;;
esac
