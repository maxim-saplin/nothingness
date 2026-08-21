#!/usr/bin/env bash
set -Eeuo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT_DIR"
COPILOT_HOME_DIR="${COPILOT_HOME:-$HOME/.copilot}"
BASE_RUNS_ROOT="${NOTHINGNESS_EVAL_RUNS_ROOT:-$ROOT_DIR/.tmp/evals}"
COPILOT_TASK_WAIT_SECONDS="${COPILOT_TASK_WAIT_TIMEOUT_SECONDS:-86400}"

usage() {
  printf 'Usage: %s COUNT PROMPT\n' "$0"
  printf '       %s --dry-run\n' "$0"
}

if [[ $# -eq 1 && "$1" == "--dry-run" ]]; then
  DRY_RUN=true
  COUNT=1
  PROMPT="how are you"
elif [[ $# -eq 2 && "$1" =~ ^[1-9][0-9]*$ ]]; then
  DRY_RUN=false
  COUNT="$1"
  PROMPT="$2"
else
  usage >&2
  exit 2
fi

if ! command -v copilot >/dev/null 2>&1; then
  printf 'copilot is required\n' >&2
  exit 2
fi

if ! command -v python3 >/dev/null 2>&1; then
  printf 'python3 is required\n' >&2
  exit 2
fi

run_copilot() {
  local session_id="$1"
  local runs_root="$2"
  local log_file="$3"

  mkdir -p "$(dirname "$log_file")"
  NOTHINGNESS_EVAL_RUNS_ROOT="$runs_root" \
    COPILOT_TASK_WAIT_TIMEOUT_SECONDS="$COPILOT_TASK_WAIT_SECONDS" \
    copilot --session-id "$session_id" --yolo -p "$PROMPT" 2>&1 | tee "$log_file"
}

result_dir_from_log() {
  local log_file="$1"

  python3 - "$log_file" <<'PY'
import pathlib
import re
import sys

path = pathlib.Path(sys.argv[1])
text = path.read_text(encoding="utf-8", errors="replace")
matches = re.findall(r"(?<![A-Za-z0-9_.-])evals/results/([A-Za-z0-9_.-]+)(?=[/` )]|$)", text)
if not matches:
    raise SystemExit(f"result_directory_not_reported:{path}")

result_dir = pathlib.Path("evals/results") / matches[-1]
if not result_dir.is_dir():
    raise SystemExit(f"result_directory_not_found:{result_dir}")
print(result_dir)
PY
}

write_orchestrator() {
  local events_file="$1"
  local output_file="$2"
  local campaign_id="$3"

  python3 - "$events_file" "$output_file" "$campaign_id" <<'PY'
import json
import pathlib
import sys

events_path = pathlib.Path(sys.argv[1])
output_path = pathlib.Path(sys.argv[2])
campaign_id = sys.argv[3]

if not events_path.is_file():
    raise SystemExit(f"session_events_not_found:{events_path}")

session_start = {}
session_shutdown = {}
for line in events_path.read_text(encoding="utf-8").splitlines():
    try:
        event = json.loads(line)
    except json.JSONDecodeError:
        continue
    data = event.get("data")
    if not isinstance(data, dict):
        continue
    if event.get("type") == "session.start":
        session_start = data
    elif event.get("type") == "session.shutdown":
        session_shutdown = data

model = session_start.get("selectedModel") or session_shutdown.get("currentModel")
effort = session_start.get("reasoningEffort")
total_nano_aiu = session_shutdown.get("totalNanoAiu")
if not isinstance(model, str) or not model:
    raise SystemExit("copilot_model_not_found")
if not isinstance(total_nano_aiu, (int, float)) or isinstance(total_nano_aiu, bool):
    raise SystemExit("copilot_total_nano_aiu_not_found")

display_model = f"{model}-{effort}" if isinstance(effort, str) and effort else model
session_id = session_start.get("sessionId") or events_path.parent.name
payload = {
    "orchestrator": f"{display_model}/copilot-cli",
    "cost_usd": round(float(total_nano_aiu) / 100_000_000_000, 8),
    "copilot_session_id": session_id,
    "model": model,
    "reasoning_effort": effort,
    "total_nano_aiu": int(total_nano_aiu),
    "ai_credits": round(float(total_nano_aiu) / 1_000_000_000, 8),
    "cost_source": "copilot_session_state",
}
if campaign_id:
    payload["campaign_id"] = campaign_id

output_path.parent.mkdir(parents=True, exist_ok=True)
output_path.write_text(json.dumps(payload, separators=(",", ":")) + "\n", encoding="utf-8")
print(output_path)
PY
}

validate_orchestrator() {
  local path="$1"

  python3 - "$path" <<'PY'
import json
import pathlib
import sys

path = pathlib.Path(sys.argv[1])
payload = json.loads(path.read_text(encoding="utf-8"))
if not isinstance(payload.get("orchestrator"), str) or not payload["orchestrator"]:
    raise SystemExit("orchestrator_name_missing")
if not isinstance(payload.get("cost_usd"), (int, float)) or isinstance(payload["cost_usd"], bool):
    raise SystemExit("orchestrator_cost_missing")
print(f"validated {path}")
PY
}

run_dry() {
  local session_id events_file output_dir output_file log_file runs_root
  session_id="$(python3 -c 'import uuid; print(uuid.uuid4())')"
  events_file="$COPILOT_HOME_DIR/session-state/$session_id/events.jsonl"
  output_dir="$ROOT_DIR/.tmp/copilot-dry-run-$session_id"
  output_file="$output_dir/orchestrator.json"
  log_file="$output_dir/copilot.log"
  runs_root="$BASE_RUNS_ROOT/dry-run-$session_id"

  run_copilot "$session_id" "$runs_root" "$log_file"
  write_orchestrator "$events_file" "$output_file" "dry-run"
  validate_orchestrator "$output_file"
}

run_campaign() {
  local iteration="$1"
  local session_id events_file log_file runs_root result_dir campaign_id

  session_id="$(python3 -c 'import uuid; print(uuid.uuid4())')"
  events_file="$COPILOT_HOME_DIR/session-state/$session_id/events.jsonl"
  log_file="$ROOT_DIR/.tmp/copilot-evals/$session_id/copilot.log"
  runs_root="$BASE_RUNS_ROOT/$session_id"

  printf '[copilot] repeat %s/%s\n' "$iteration" "$COUNT"
  run_copilot "$session_id" "$runs_root" "$log_file"

  result_dir="$(result_dir_from_log "$log_file")"
  campaign_id="${result_dir##*/}"
  write_orchestrator "$events_file" "$ROOT_DIR/$result_dir/orchestrator.json" "$campaign_id"
  validate_orchestrator "$ROOT_DIR/$result_dir/orchestrator.json"
}

if [[ "$DRY_RUN" == true ]]; then
  run_dry
else
  for ((iteration = 1; iteration <= COUNT; iteration++)); do
    run_campaign "$iteration"
  done
fi