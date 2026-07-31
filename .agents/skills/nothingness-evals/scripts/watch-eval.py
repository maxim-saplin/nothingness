from __future__ import annotations

import argparse
import json
import subprocess
import time
from datetime import UTC, datetime
from pathlib import Path
from typing import Any

from common import RUNS_ROOT, command, fail, read_json, validate_run_id

ACTIVE_PHASES = {"starting", "running", "retrying", "awaiting_judge"}
CAMPAIGNS_ROOT = RUNS_ROOT / "campaigns"


def duration(seconds: float | int | None) -> str:
    value = max(0, int(seconds or 0))
    hours, remainder = divmod(value, 3600)
    minutes, seconds = divmod(remainder, 60)
    return f"{hours:02d}:{minutes:02d}:{seconds:02d}"


def money(value: object) -> str:
    return "unknown" if not isinstance(value, (int, float)) else f"${value:.4f}"


def integer(value: object) -> str:
    return f"{int(value):,}" if isinstance(value, (int, float)) else "unknown"


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


def age(value: object) -> str:
    if not isinstance(value, str):
        return "unknown"
    try:
        moment = datetime.fromisoformat(value.replace("Z", "+00:00"))
    except ValueError:
        return "unknown"
    seconds = max(0, int((datetime.now(UTC) - moment).total_seconds()))
    return f"{seconds}s ago" if seconds < 60 else f"{seconds // 60}m ago"


def attempts(suite_id: str) -> list[dict[str, Any]]:
    """Every run directory sharing suite_id, one row per attempt, in directory order.

    This scans the whole runs root rather than trusting any single campaign's
    bookkeeping, so live progress (including a docker exec into a still-running
    container) is always read straight from disk/the container, never inferred.
    """
    values = []
    if not RUNS_ROOT.is_dir():
        return values
    for directory in sorted(RUNS_ROOT.iterdir()):
        metadata_path = directory / "run.json"
        if not metadata_path.is_file():
            continue
        metadata = read_json(metadata_path)
        if metadata.get("suite_id") != suite_id:
            continue
        progress = progress_for(directory, metadata)
        result = read_json(directory / "result.json") if (directory / "result.json").is_file() else None
        summary = read_json(directory / "summary.json") if (directory / "summary.json").is_file() else None
        state = "RUNNING" if progress.get("phase") in ACTIVE_PHASES else "PENDING"
        if isinstance(result, dict):
            state = result.get("outcome") if result.get("validity") == "valid" else result.get("validity", "DONE")
        candidate_cost = progress.get("cost_usd")
        candidate_tokens = progress.get("tokens", {}).get("totalTokens") if isinstance(progress.get("tokens"), dict) else None
        if isinstance(summary, dict):
            candidate_cost = summary.get("cost_usd", {}).get("candidate")
            candidate_tokens = summary.get("candidate", {}).get("usage", {}).get("aggregate", {}).get("tokens", {}).get("total")
        admission = read_json(directory / "admission.json") if (directory / "admission.json").is_file() else None
        admission_cost = admission.get("normalized_usage", {}).get("cost_usd", {}).get("total") if isinstance(admission, dict) else None
        admission_tokens = admission.get("normalized_usage", {}).get("tokens", {}).get("total") if isinstance(admission, dict) else None
        finished = (directory / "result.json").is_file() or (directory / "cleanup.json").is_file()
        values.append(
            {
                "run_id": metadata["run_id"],
                "task_id": metadata["task_id"],
                "trial": metadata.get("trial"),
                "calibration": metadata.get("calibration", False),
                "state": state,
                "phase": progress.get("phase"),
                "elapsed": progress.get("elapsed_seconds"),
                "timeout_seconds": progress.get("timeout_seconds"),
                "tools": progress.get("tool_calls"),
                "tokens": candidate_tokens + admission_tokens if isinstance(candidate_tokens, (int, float)) and isinstance(admission_tokens, (int, float)) else None,
                "cost": candidate_cost + admission_cost if isinstance(candidate_cost, (int, float)) and isinstance(admission_cost, (int, float)) else None,
                "activity": progress.get("last_activity"),
                "activity_at": progress.get("last_activity_at"),
                "valid": isinstance(result, dict) and result.get("validity") == "valid",
                "finished": finished,
            }
        )
    return values


def campaign_path(campaign_id: str) -> Path:
    return CAMPAIGNS_ROOT / campaign_id / "campaign.json"


def load_campaign(campaign_id: str) -> dict[str, Any]:
    path = campaign_path(campaign_id)
    if not path.is_file():
        fail(3, "campaign_not_found")
    campaign = read_json(path)
    if (
        not isinstance(campaign, dict)
        or not isinstance(campaign.get("suite_id"), str)
        or not isinstance(campaign.get("model"), dict)
        or not isinstance(campaign.get("tasks"), list)
        or not isinstance(campaign.get("runs"), dict)
    ):
        fail(3, "invalid_campaign_state")
    return campaign


def task_rows_by_id(campaign: dict[str, Any]) -> dict[str, list[dict[str, Any]]]:
    """Map each campaign task to its own attempts, in the order campaign.py recorded them.

    attempts() is suite-wide (it has no notion of "campaign"), so a second suite
    run against the same task ids would otherwise bleed into this one. Filtering
    down to the run ids campaign.json actually recorded keeps this campaign's
    dashboard scoped to this campaign, while still reading live state the same
    scanning way attempts() always has.
    """
    by_run_id = {row["run_id"]: row for row in attempts(campaign["suite_id"])}
    grouped: dict[str, list[dict[str, Any]]] = {}
    for task_id in campaign["tasks"]:
        run_ids = campaign["runs"].get(task_id, [])
        grouped[task_id] = [by_run_id[run_id] for run_id in run_ids if run_id in by_run_id]
    return grouped


TASK_COLUMN = 42
STATE_COLUMN = 19


def task_line(task_id: str, state: str, attempt_count: str, elapsed: str, tools: str, tokens: str, cost: str, last_activity: str) -> str:
    return f"{task_id:<{TASK_COLUMN}} {state:<{STATE_COLUMN}} {attempt_count:>8} {elapsed:>8} {tools:>8} {tokens:>11} {cost:>10}  {last_activity}"


def render(campaign_id: str) -> tuple[str, bool]:
    campaign = load_campaign(campaign_id)
    grouped = task_rows_by_id(campaign)
    model = campaign["model"]
    lines = [
        "NOTHINGNESS EVALUATION CAMPAIGN",
        f"Campaign  {campaign_id}",
        f"Model     {model.get('provider')} / {model.get('model')} / {model.get('thinking')}",
        f"Suite     {campaign['suite_id']}   {len(campaign['tasks'])} tasks",
    ]

    pending = 0
    in_progress = 0
    finished_count = 0
    active_row: dict[str, Any] | None = None
    # (task_id, state, attempt_count, elapsed, tools, tokens, cost, last_activity, started).
    # attempt_count/elapsed/tools/tokens/cost stay real numbers here (0 for a task with zero
    # attempts is a true zero) so campaign-wide totals below sum correctly; `started` decides
    # whether the table renders those numbers or "-" for "nothing to report yet".
    task_totals: list[tuple[str, str, int, float, object, object, object, str, bool]] = []

    for task_id in campaign["tasks"]:
        rows = grouped[task_id]
        if not rows:
            pending += 1
            task_totals.append((task_id, "not started", 0, 0, 0, 0, 0.0, "-", False))
            continue
        latest = rows[-1]
        state = str(latest["state"])
        elapsed = sum((row["elapsed"] or 0) for row in rows)
        tools = sum((row["tools"] or 0) for row in rows if isinstance(row["tools"], (int, float)))
        tokens_values = [row["tokens"] for row in rows]
        tokens = sum(tokens_values) if all(isinstance(value, (int, float)) for value in tokens_values) else None
        costs = [row["cost"] for row in rows]
        cost = sum(costs) if all(isinstance(value, (int, float)) for value in costs) else None
        last_activity = f"{age(latest['activity_at'])}: {latest['activity']}"
        if latest["finished"]:
            finished_count += 1
        else:
            in_progress += 1
            if latest["state"] == "RUNNING":
                active_row = latest
        task_totals.append((task_id, state, len(rows), elapsed, tools, tokens, cost, last_activity, True))

    campaign_tokens_values = [entry[5] for entry in task_totals]
    campaign_tokens = sum(campaign_tokens_values) if all(isinstance(value, (int, float)) for value in campaign_tokens_values) else None
    campaign_costs = [entry[6] for entry in task_totals]
    campaign_cost = sum(campaign_costs) if all(isinstance(value, (int, float)) for value in campaign_costs) else None

    lines.append(f"Progress  {finished_count}/{len(campaign['tasks'])} finished   {in_progress} in progress   {pending} not started")
    lines.append(f"Totals    {integer(campaign_tokens)} tokens   {money(campaign_cost)}")
    lines.append("")
    lines.append(f"{'TASK':<{TASK_COLUMN}} {'STATE':<{STATE_COLUMN}} {'ATTEMPTS':>8} {'ELAPSED':>8} {'TOOLS':>8} {'TOKENS':>11} {'COST':>10}  LAST ACTIVITY")
    for task_id, state, attempt_count, elapsed, tools, tokens, cost, last_activity, started in task_totals:
        if started:
            lines.append(task_line(task_id, state, integer(attempt_count), duration(elapsed), integer(tools), integer(tokens), money(cost), last_activity))
        else:
            lines.append(task_line(task_id, state, "-", "-", "-", "-", "-", last_activity))

    lines.append("")
    if active_row is not None:
        lines.append(f"Current task phase: {active_row.get('phase')}  timeout {duration(active_row.get('elapsed'))} / {duration(active_row.get('timeout_seconds'))}")
    else:
        lines.append("Current task phase: none active")
    lines.append("Candidate completion is judge-evaluated; active timeout is not presented as candidate percent done.")

    finished = pending == 0 and in_progress == 0
    return "\n".join(lines), finished


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("campaign_id")
    parser.add_argument("--once", action="store_true")
    parser.add_argument("--refresh", type=float, default=1.0)
    arguments = parser.parse_args()
    validate_run_id(arguments.campaign_id)
    if not campaign_path(arguments.campaign_id).is_file():
        fail(3, "campaign_not_found")
    while True:
        display, finished = render(arguments.campaign_id)
        if not arguments.once:
            print("\033[2J\033[H", end="")
        print(display, flush=True)
        if arguments.once or finished:
            return
        time.sleep(max(0.2, arguments.refresh))


if __name__ == "__main__":
    main()
