#!/usr/bin/env bash
set -Eeuo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT_DIR"
COPILOT_HOME_DIR="${COPILOT_HOME:-$HOME/.copilot}"
RUNS_ROOT="${NOTHINGNESS_EVAL_RUNS_ROOT:-$ROOT_DIR/.tmp/evals}"
CAMPAIGNS_ROOT="$RUNS_ROOT/campaigns"
RESULTS_ROOT="$ROOT_DIR/evals/results"
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

latest_campaign_result() {
  python3 - "$CAMPAIGNS_ROOT" "$RESULTS_ROOT" "$1" <<'PY'
import json
import pathlib
import sys
from datetime import datetime

campaigns_root = pathlib.Path(sys.argv[1])
results_root = pathlib.Path(sys.argv[2])
started_at = datetime.fromisoformat(sys.argv[3].replace("Z", "+00:00"))


def read_payload(path):
    try:
        payload = json.loads(path.read_text(encoding="utf-8"))
    except (OSError, json.JSONDecodeError):
        return None
    return payload if isinstance(payload, dict) else None


def sort_key(path, payload):
    created_at = payload.get("created_at")
    if isinstance(created_at, str) and created_at:
        return 1, created_at, path.stat().st_mtime_ns, path.parent.name
    return 0, "", path.stat().st_mtime_ns, path.parent.name


campaigns = []
for path in campaigns_root.glob("*/campaign.json"):
    payload = read_payload(path)
    created_at = payload.get("created_at") if payload is not None else None
    if not isinstance(created_at, str):
        continue
    try:
        created = datetime.fromisoformat(created_at.replace("Z", "+00:00"))
    except ValueError:
        continue
    if created > started_at:
        campaigns.append((sort_key(path, payload), path.parent.name, payload))
if not campaigns:
    raise SystemExit("campaign_not_created_after_invocation")

_, campaign_id, campaign = max(campaigns)
status = campaign.get("status")
if status != "complete":
    raise SystemExit(f"campaign_not_complete:{campaign_id}:{status or 'unknown'}")

results = []
for path in results_root.glob("*/campaign.json"):
    payload = read_payload(path)
    if payload is not None and payload.get("campaign_id") == campaign_id:
        results.append((sort_key(path, payload), path.parent))
if not results:
    raise SystemExit(f"result_not_found_for_campaign:{campaign_id}")

print(campaign_id)
print(max(results)[1])
PY
}

run_copilot() {
  local session_id="$1"
  local log_file="$2"

  mkdir -p "$(dirname "$log_file")"
  NOTHINGNESS_EVAL_RUNS_ROOT="$RUNS_ROOT" \
    COPILOT_TASK_WAIT_TIMEOUT_SECONDS="$COPILOT_TASK_WAIT_SECONDS" \
    copilot --session-id "$session_id" --yolo -p "$PROMPT" 2>&1 | tee "$log_file"
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
print("orchestrator metadata written")
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
print("orchestrator metadata validated")
PY
}

run_dry() {
  local session_id events_file output_dir output_file log_file
  session_id="$(python3 -c 'import uuid; print(uuid.uuid4())')"
  events_file="$COPILOT_HOME_DIR/session-state/$session_id/events.jsonl"
  output_dir="$ROOT_DIR/.tmp/copilot-dry-run-$session_id"
  output_file="$output_dir/orchestrator.json"
  log_file="$output_dir/copilot.log"

  run_copilot "$session_id" "$log_file"
  write_orchestrator "$events_file" "$output_file" "dry-run"
  validate_orchestrator "$output_file"
}

run_campaign() {
  local iteration="$1"
  local session_id events_file log_file campaign_id result_dir invocation_started latest_output
  local -a latest=()

  invocation_started="$(python3 -c 'from datetime import UTC, datetime; print(datetime.now(UTC).isoformat())')"
  session_id="$(python3 -c 'import uuid; print(uuid.uuid4())')"
  events_file="$COPILOT_HOME_DIR/session-state/$session_id/events.jsonl"
  log_file="$ROOT_DIR/.tmp/copilot-evals/$session_id/copilot.log"

  printf '[copilot] repeat %s/%s\n' "$iteration" "$COUNT"
  run_copilot "$session_id" "$log_file"

  if ! latest_output="$(latest_campaign_result "$invocation_started")"; then
    printf 'repeat %s stopped: Copilot did not create a completed campaign; see its output above\n' "$iteration" >&2
    exit 1
  fi
  mapfile -t latest <<< "$latest_output"
  if [[ ${#latest[@]} -ne 2 ]]; then
    printf 'repeat %s stopped: campaign metadata was incomplete\n' "$iteration" >&2
    exit 1
  fi

  campaign_id="${latest[0]}"
  result_dir="${latest[1]}"
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