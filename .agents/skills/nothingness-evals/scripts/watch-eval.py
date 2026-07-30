from __future__ import annotations

import argparse
import json
import os
import subprocess
import time
from datetime import UTC, datetime
from pathlib import Path
from typing import Any

from common import RUNS_ROOT, command, fail, read_json, run_dir, validate_run_id


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
        if progress.get("phase") in {"starting", "running", "retrying", "awaiting_judge"} and isinstance(progress.get("started_at_unix"), (int, float)):
            progress["elapsed_seconds"] = time.time() - progress["started_at_unix"]
        return progress
    result = command(["docker", "exec", metadata["container"], "cat", "/run/nothingness/progress.json"], stdout=subprocess.PIPE, stderr=subprocess.DEVNULL)
    if result.returncode == 0:
        try:
            progress = json.loads(result.stdout)
            if progress.get("phase") in {"starting", "running", "retrying", "awaiting_judge"} and isinstance(progress.get("started_at_unix"), (int, float)):
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


def attempts(suite_id: str, current_run: Path, current_progress: dict[str, Any]) -> list[dict[str, Any]]:
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
        progress = current_progress if directory == current_run else progress_for(directory, metadata)
        result = read_json(directory / "result.json") if (directory / "result.json").is_file() else None
        summary = read_json(directory / "summary.json") if (directory / "summary.json").is_file() else None
        state = "RUNNING" if progress.get("phase") in {"starting", "running", "retrying", "awaiting_judge"} else "PENDING"
        if isinstance(result, dict):
            state = result.get("outcome") if result.get("validity") == "valid" else result.get("validity", "DONE")
        candidate_cost = progress.get("cost_usd")
        candidate_tokens = progress.get("tokens", {}).get("totalTokens") if isinstance(progress.get("tokens"), dict) else None
        if isinstance(summary, dict):
            candidate_cost = summary.get("cost_usd", {}).get("candidate")
            candidate_tokens = summary.get("candidate", {}).get("usage", {}).get("aggregate", {}).get("tokens", {}).get("total")
        admission = read_json(directory / "admission.json") if (directory / "admission.json").is_file() else None
        admission_cost = admission.get("normalized_usage", {}).get("cost_usd", {}).get("total") if isinstance(admission, dict) else None
        admission_tokens = admission.get("normalized_usage", {}).get("tokens", {}).get("total") if isinstance(admission, dict) else 0
        values.append({"run_id": metadata["run_id"], "task_id": metadata["task_id"], "trial": metadata.get("trial"), "calibration": metadata.get("calibration", False), "state": state, "elapsed": progress.get("elapsed_seconds"), "tools": progress.get("tool_calls"), "tokens": (candidate_tokens or 0) + (admission_tokens or 0), "cost": candidate_cost + admission_cost if isinstance(candidate_cost, (int, float)) and isinstance(admission_cost, (int, float)) else None, "activity": progress.get("last_activity"), "activity_at": progress.get("last_activity_at"), "valid": isinstance(result, dict) and result.get("validity") == "valid"})
    return values


def render(run_id: str) -> tuple[str, bool]:
    run = run_dir(run_id)
    metadata = read_json(run / "run.json")
    if not isinstance(metadata.get("suite_id"), str) or not isinstance(metadata.get("requested_model"), dict):
        fail(3, "legacy_run_not_dashboard_compatible")
    progress = progress_for(run, metadata)
    rows = attempts(metadata["suite_id"], run, progress)
    planned = metadata.get("planned_valid_trials", 3)
    valid = sum(1 for row in rows if row["valid"] and not row["calibration"])
    percent = round(valid / planned * 100)
    total_tokens = sum(row["tokens"] for row in rows if isinstance(row["tokens"], (int, float)))
    costs = [row["cost"] for row in rows]
    total_cost = sum(costs) if all(isinstance(value, (int, float)) for value in costs) else None
    model = metadata["requested_model"]
    lines = [
        "NOTHINGNESS EVALUATION",
        f"Model     {model['provider']} / {model['model']} / {model['thinking']}",
        f"Task      {metadata['task_id']}",
        f"Suite     {valid}/{planned} valid trials  {percent}%    attempts {len(rows)}",
        f"Totals    {integer(total_tokens)} tokens   {money(total_cost)}",
        f"noVNC     {metadata.get('novnc_url', 'not ready')}",
        "",
        "TASK TOTALS",
        f"{metadata['task_id']:<34} valid {valid}/{planned}   attempts {len(rows)}   elapsed {duration(sum((row['elapsed'] or 0) for row in rows))}   tokens {integer(total_tokens)}   cost {money(total_cost)}",
        "",
        "TRIAL / ATTEMPT                    STATE               ELAPSED    TOOLS      TOKENS       COST  LAST ACTIVITY",
    ]
    for row in rows:
        label = "calibration" if row["calibration"] else f"trial {row['trial']}"
        lines.append(f"{label:<34} {str(row['state']):<19} {duration(row['elapsed']):>8} {integer(row['tools']):>8} {integer(row['tokens']):>11} {money(row['cost']):>10}  {age(row['activity_at'])}: {row['activity']}")
    lines.extend(("", f"Current phase: {progress.get('phase')}  timeout {duration(progress.get('elapsed_seconds'))} / {duration(progress.get('timeout_seconds'))}", "Candidate completion is judge-evaluated; active timeout is not presented as candidate percent done."))
    finished = (run / "result.json").is_file() or (run / "cleanup.json").is_file()
    return "\n".join(lines), finished


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("run_id")
    parser.add_argument("--once", action="store_true")
    parser.add_argument("--refresh", type=float, default=1.0)
    arguments = parser.parse_args()
    validate_run_id(arguments.run_id)
    if not (run_dir(arguments.run_id) / "run.json").is_file():
        fail(3, "run_not_prepared")
    while True:
        display, finished = render(arguments.run_id)
        if not arguments.once:
            print("\033[2J\033[H", end="")
        print(display, flush=True)
        if arguments.once or finished:
            return
        time.sleep(max(0.2, arguments.refresh))


if __name__ == "__main__":
    main()