#!/usr/bin/env bash
set -Eeuo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT_DIR"
COPILOT_HOME_DIR="${COPILOT_HOME:-$HOME/.copilot}"
RUNS_ROOT="${NOTHINGNESS_EVAL_RUNS_ROOT:-$ROOT_DIR/.tmp/evals}"
CAMPAIGNS_ROOT="$RUNS_ROOT/campaigns"

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

list_campaigns() {
  if [[ -d "$CAMPAIGNS_ROOT" ]]; then
    find "$CAMPAIGNS_ROOT" -mindepth 2 -maxdepth 2 -type f -name campaign.json -printf '%h\n' | sort
  fi
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
  local session_id events_file output_dir output_file
  session_id="$(python3 -c 'import uuid; print(uuid.uuid4())')"
  events_file="$COPILOT_HOME_DIR/session-state/$session_id/events.jsonl"
  output_dir="$ROOT_DIR/.tmp/copilot-dry-run-$session_id"
  output_file="$output_dir/orchestrator.json"

  copilot --session-id "$session_id" --yolo -p "$PROMPT"
  write_orchestrator "$events_file" "$output_file" "dry-run"
  validate_orchestrator "$output_file"
}

run_campaign() {
  local iteration="$1"
  local session_id events_file prompt
  local -a before_campaigns after_campaigns new_campaigns
  local path campaign_path campaign_id result_dir
  declare -A before_set=()

  mapfile -t before_campaigns < <(list_campaigns)
  for path in "${before_campaigns[@]}"; do
    [[ -n "$path" ]] && before_set["$path"]=1
  done

  session_id="$(python3 -c 'import uuid; print(uuid.uuid4())')"
  events_file="$COPILOT_HOME_DIR/session-state/$session_id/events.jsonl"
  prompt="$PROMPT"$'\n\n'"This is intentional repeat $iteration of $COUNT. Create a fresh campaign and use --allow-repeat when creating it."

  printf '[copilot] repeat %s/%s\n' "$iteration" "$COUNT"
  copilot --session-id "$session_id" --yolo -p "$prompt"

  mapfile -t after_campaigns < <(list_campaigns)
  new_campaigns=()
  for path in "${after_campaigns[@]}"; do
    if [[ -n "$path" && -z "${before_set[$path]+present}" ]]; then
      new_campaigns+=("$path")
    fi
  done
  if [[ ${#new_campaigns[@]} -ne 1 ]]; then
    printf 'expected one new campaign, found %s\n' "${#new_campaigns[@]}" >&2
    exit 1
  fi

  campaign_path="${new_campaigns[0]}"
  campaign_id="$(basename "$campaign_path")"
  result_dir="$ROOT_DIR/evals/results/$campaign_id"
  write_orchestrator "$events_file" "$result_dir/orchestrator.json" "$campaign_id"
  validate_orchestrator "$result_dir/orchestrator.json"
}

if [[ "$DRY_RUN" == true ]]; then
  run_dry
else
  for ((iteration = 1; iteration <= COUNT; iteration++)); do
    run_campaign "$iteration"
  done
fi