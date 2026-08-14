from __future__ import annotations

import argparse
import json
import shutil
import subprocess
import sys
import time
from datetime import UTC, datetime
from pathlib import Path
from typing import Any

from common import RUNS_ROOT, command, fail, read_json, validate_run_id

ACTIVE_PHASES = {"starting", "running", "retrying", "awaiting_judge"}
CAMPAIGNS_ROOT = RUNS_ROOT / "campaigns"
TASK_COLUMN = 42
STATE_COLUMN = 19


def duration(seconds: float | int | None) -> str:
    value = max(0, int(seconds or 0))
    hours, remainder = divmod(value, 3600)
    minutes, seconds = divmod(remainder, 60)
    return f"{hours:02d}:{minutes:02d}:{seconds:02d}"


def money(value: object) -> str:
    return "unknown" if not isinstance(value, (int, float)) else f"${value:.4f}"


def integer(value: object) -> str:
    return f"{int(value):,}" if isinstance(value, (int, float)) else "unknown"


def age(value: object) -> str:
    if not isinstance(value, str):
        return "unknown"
    try:
        moment = datetime.fromisoformat(value.replace("Z", "+00:00"))
    except ValueError:
        return "unknown"
    seconds = max(0, int((datetime.now(UTC) - moment).total_seconds()))
    return f"{seconds}s ago" if seconds < 60 else f"{seconds // 60}m ago"


def progress_for(run: Path, metadata: dict[str, Any]) -> dict[str, Any]:
    artifact = run / "artifacts" / "progress.json"
    if artifact.is_file():
        progress = read_json(artifact)
        if progress.get("phase") in ACTIVE_PHASES and isinstance(progress.get("started_at_unix"), (int, float)):
            progress["elapsed_seconds"] = time.time() - progress["started_at_unix"]
        return progress
    result = command(["docker", "exec", metadata["container"], "cat", "/run/nothingness/progress.json"], stdout=subprocess.PIPE, stderr=subprocess.DEVNULL)
    if result.returncode == 0:
        try:
            progress = json.loads(result.stdout)
            if progress.get("phase") in ACTIVE_PHASES and isinstance(progress.get("started_at_unix"), (int, float)):
                progress["elapsed_seconds"] = time.time() - progress["started_at_unix"]
            return progress
        except json.JSONDecodeError:
            pass
    return {"phase": "not_started", "elapsed_seconds": 0, "tool_calls": 0, "tokens": {}, "cost_usd": None, "last_activity": "waiting for candidate", "last_activity_at": metadata.get("prepared_at")}


def run_row(run_id: str) -> dict[str, Any] | None:
    run = RUNS_ROOT / run_id
    metadata_path = run / "run.json"
    if not metadata_path.is_file():
        return None
    metadata = read_json(metadata_path)
    progress = progress_for(run, metadata)
    result = read_json(run / "result.json") if (run / "result.json").is_file() else None
    summary = read_json(run / "summary.json") if (run / "summary.json").is_file() else None
    candidate_cost = progress.get("cost_usd")
    candidate_tokens = progress.get("tokens", {}).get("totalTokens") if isinstance(progress.get("tokens"), dict) else None
    if isinstance(summary, dict):
        candidate_cost = summary.get("cost_usd", {}).get("candidate")
        candidate_tokens = summary.get("candidate", {}).get("usage", {}).get("aggregate", {}).get("tokens", {}).get("total")
    admission = read_json(run / "admission.json") if (run / "admission.json").is_file() else None
    admission_cost = admission.get("normalized_usage", {}).get("cost_usd", {}).get("total") if isinstance(admission, dict) else None
    admission_tokens = admission.get("normalized_usage", {}).get("tokens", {}).get("total") if isinstance(admission, dict) else None
    total_cost = candidate_cost + admission_cost if isinstance(candidate_cost, (int, float)) and isinstance(admission_cost, (int, float)) else None
    total_tokens = candidate_tokens + admission_tokens if isinstance(candidate_tokens, (int, float)) and isinstance(admission_tokens, (int, float)) else None
    if isinstance(result, dict):
        state = result.get("outcome") if result.get("validity") == "valid" else result.get("validity", "DONE")
    elif progress.get("phase") in ACTIVE_PHASES:
        state = "RUNNING"
    else:
        state = "PENDING"
    return {
        "run_id": run_id,
        "retry": metadata.get("retry", 0),
        "state": state,
        "phase": progress.get("phase"),
        "elapsed": progress.get("elapsed_seconds"),
        "timeout_seconds": progress.get("timeout_seconds"),
        "tools": progress.get("tool_calls"),
        "tokens": total_tokens,
        "cost": total_cost,
        "activity": progress.get("last_activity"),
        "activity_at": progress.get("last_activity_at"),
        "valid": isinstance(result, dict) and result.get("validity") == "valid",
        "finished": isinstance(result, dict) or (run / "cleanup.json").is_file(),
    }


def campaign_path(campaign_id: str) -> Path:
    return CAMPAIGNS_ROOT / campaign_id / "campaign.json"


def load_campaign(campaign_id: str) -> dict[str, Any]:
    path = campaign_path(campaign_id)
    if not path.is_file():
        fail(3, "campaign_not_found")
    campaign = read_json(path)
    if not isinstance(campaign, dict) or not isinstance(campaign.get("suite_id"), str) or not isinstance(campaign.get("model"), dict) or not isinstance(campaign.get("tasks"), list) or not isinstance(campaign.get("runs"), dict):
        fail(3, "invalid_campaign_state")
    return campaign


def task_rows(campaign: dict[str, Any], task_id: str) -> list[dict[str, Any]]:
    rows = []
    for run_id in campaign["runs"].get(task_id, []):
        if isinstance(run_id, str):
            row = run_row(run_id)
            if row is not None:
                rows.append(row)
    return rows


def retry_count(campaign: dict[str, Any], task_id: str, rows: list[dict[str, Any]]) -> int:
    values = [row.get("retry", 0) for row in rows if isinstance(row.get("retry"), int)]
    run_retries = campaign.get("run_retries") or {}
    values.extend(run_retries.get(run_id, 0) for run_id in campaign["runs"].get(task_id, []) if isinstance(run_retries.get(run_id, 0), int))
    return max(values, default=0)


def accepted_row(rows: list[dict[str, Any]]) -> dict[str, Any] | None:
    return next((row for row in reversed(rows) if row.get("valid")), None)


def known_retry_cost(campaign: dict[str, Any], task_id: str) -> float | None:
    values = [item.get("cost_usd") for item in (campaign.get("retry_log") or {}).get(task_id, [])]
    if any(value is None for value in values):
        return None
    return sum(value for value in values if isinstance(value, (int, float)))


def task_line(task_id: str, state: str, retries: str, elapsed: str, tools: str, tokens: str, cost: str, last_activity: str) -> str:
    return f"{task_id:<{TASK_COLUMN}} {state:<{STATE_COLUMN}} {retries:>8} {elapsed:>8} {tools:>8} {tokens:>11} {cost:>10}  {last_activity}"


def render(campaign_id: str) -> tuple[str, bool]:
    campaign = load_campaign(campaign_id)
    model = campaign["model"]
    lines = [
        "NOTHINGNESS EVALUATION CAMPAIGN",
        f"Campaign  {campaign_id}  [{campaign.get('status', 'unknown')}]",
        f"Model     {model.get('provider')} / {model.get('model')} / {model.get('thinking')}",
        f"Suite     {campaign['suite_id']}   {len(campaign['tasks'])} tasks",
    ]
    pending = 0
    in_progress = 0
    finished_count = 0
    accepted_costs: list[float] = []
    accepted_tokens: list[float] = []
    task_totals: list[tuple[str, str, int, float, object, object, object, str, bool]] = []
    for task_id in campaign["tasks"]:
        rows = task_rows(campaign, task_id)
        accepted = accepted_row(rows)
        retries = retry_count(campaign, task_id, rows)
        latest = rows[-1] if rows else None
        if accepted is not None:
            finished_count += 1
            state = str(accepted["state"])
            elapsed, tools, tokens, cost = accepted.get("elapsed"), accepted.get("tools"), accepted.get("tokens"), accepted.get("cost")
            if isinstance(cost, (int, float)):
                accepted_costs.append(cost)
            if isinstance(tokens, (int, float)):
                accepted_tokens.append(tokens)
            last_activity = f"{age(accepted.get('activity_at'))}: accepted run"
            task_totals.append((task_id, state, retries, elapsed or 0, tools or 0, tokens, cost, last_activity, True))
            continue
        if latest is None:
            pending += 1
            task_totals.append((task_id, "not started", retries, 0, 0, 0, 0.0, "-", False))
            continue
        if latest["state"] == "RUNNING":
            in_progress += 1
            state = "RUNNING"
        else:
            pending += 1
            state = "RETRYING"
        task_totals.append((task_id, state, retries, latest.get("elapsed") or 0, latest.get("tools") or 0, latest.get("tokens"), latest.get("cost"), f"{age(latest.get('activity_at'))}: {latest.get('activity')}", True))

    accepted_total = sum(accepted_costs) if len(accepted_costs) == finished_count else None
    accepted_tokens_total = sum(accepted_tokens) if len(accepted_tokens) == finished_count else None
    recorded_campaign_cost = (campaign.get("costs") or {}).get("campaign_usd")
    if isinstance(recorded_campaign_cost, (int, float)):
        campaign_cost = recorded_campaign_cost
    else:
        retry_costs = [known_retry_cost(campaign, task_id) for task_id in campaign["tasks"]]
        campaign_cost = accepted_total + sum(value for value in retry_costs if isinstance(value, (int, float))) if isinstance(accepted_total, (int, float)) and all(value is not None for value in retry_costs) else None
    lines.append(f"Progress  {finished_count}/{len(campaign['tasks'])} finished   {in_progress} in progress   {pending} pending")
    lines.append(f"Costs     campaign {money(campaign_cost)} incl. retries   accepted tasks {money(accepted_total)}")
    lines.append(f"Accepted  {integer(accepted_tokens_total)} tokens")
    lines.append("")
    lines.append(f"{'TASK':<{TASK_COLUMN}} {'STATE':<{STATE_COLUMN}} {'RETRIES':>8} {'ELAPSED':>8} {'TOOLS':>8} {'TOKENS':>11} {'TASK COST':>10}  LAST ACTIVITY")
    for task_id, state, retries, elapsed, tools, tokens, cost, last_activity, started in task_totals:
        if started:
            lines.append(task_line(task_id, state, str(retries), duration(elapsed), integer(tools), integer(tokens), money(cost), last_activity))
        else:
            lines.append(task_line(task_id, state, str(retries), "-", "-", "-", "-", last_activity))
    lines.append("")
    active = next((row for task_id in campaign["tasks"] for row in task_rows(campaign, task_id) if row.get("state") == "RUNNING"), None)
    if active is not None:
        lines.append(f"Current task phase: {active.get('phase')}  timeout {duration(active.get('elapsed'))} / {duration(active.get('timeout_seconds'))}")
    else:
        lines.append("Current task phase: none active")
    lines.append("Retries are fresh task restarts; discarded runs are not included in task cost or accepted totals.")
    finished = campaign.get("status") == "complete"
    return "\n".join(lines), finished


def fit(line: str, width: int) -> str:
    if width <= 1 or len(line) <= width:
        return line
    return line[: width - 1] + "…"


def frame(display: str, width: int, height: int) -> str:
    rows = [fit(line, width) for line in display.split("\n")[: max(1, height - 1)]]
    return "\033[H" + "\033[K\n".join(rows) + "\033[K\033[J"


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("campaign_id")
    parser.add_argument("--once", action="store_true")
    parser.add_argument("--refresh", type=float, default=1.0)
    arguments = parser.parse_args()
    validate_run_id(arguments.campaign_id)
    if not campaign_path(arguments.campaign_id).is_file():
        fail(3, "campaign_not_found")
    if arguments.once or not sys.stdout.isatty():
        while True:
            display, finished = render(arguments.campaign_id)
            print(display, flush=True)
            if arguments.once or finished:
                return
            time.sleep(max(0.2, arguments.refresh))
    sys.stdout.write("\033[?1049h\033[?25l")
    latest = ""
    try:
        while True:
            latest, finished = render(arguments.campaign_id)
            size = shutil.get_terminal_size((100, 40))
            sys.stdout.write(frame(latest, size.columns, size.lines))
            sys.stdout.flush()
            if finished:
                break
            time.sleep(max(0.2, arguments.refresh))
    except KeyboardInterrupt:
        pass
    finally:
        sys.stdout.write("\033[?25h\033[?1049l")
        sys.stdout.flush()
    if latest:
        print(latest, flush=True)


if __name__ == "__main__":
    main()
