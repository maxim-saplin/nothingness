from __future__ import annotations

import argparse
from pathlib import Path
from typing import Any

from common import ROOT, RUNS_ROOT, SCRIPT_DIR, emit_json, fail, load_suite, read_json, sha256, utc_now, validate_run_id, write_json

CAMPAIGNS_ROOT = RUNS_ROOT / "campaigns"


def campaign_dir(campaign_id: str) -> Path:
    return CAMPAIGNS_ROOT / campaign_id


def campaign_path(campaign_id: str) -> Path:
    return campaign_dir(campaign_id) / "campaign.json"


def dashboard_command(campaign_id: str) -> str:
    return f"uv run python {SCRIPT_DIR.relative_to(ROOT)}/watch-eval.py {campaign_id}"


def load_campaign(campaign_id: str) -> dict[str, Any]:
    path = campaign_path(campaign_id)
    if not path.is_file():
        fail(3, "campaign_not_found")
    campaign = read_json(path)
    if (
        not isinstance(campaign, dict)
        or not isinstance(campaign.get("campaign_id"), str)
        or not isinstance(campaign.get("suite_id"), str)
        or not isinstance(campaign.get("model"), dict)
        or not isinstance(campaign.get("tasks"), list)
        or not all(isinstance(item, str) for item in campaign["tasks"])
        or not isinstance(campaign.get("runs"), dict)
    ):
        fail(3, "invalid_campaign_state")
    return campaign


def new_campaign(arguments: argparse.Namespace) -> None:
    validate_run_id(arguments.campaign_id)
    path = campaign_path(arguments.campaign_id)
    if path.exists():
        fail(2, "campaign_already_exists")
    suite_path = arguments.suite.resolve()
    suite = load_suite(suite_path)
    task_ids = [task["id"] for task in suite["tasks"]]
    now = utc_now()
    campaign = {
        "schema_version": 1,
        "campaign_id": arguments.campaign_id,
        "suite_id": suite["id"],
        "suite_manifest_sha256": sha256(suite_path),
        "model": suite["requested_model"],
        "tasks": task_ids,
        "runs": {task_id: [] for task_id in task_ids},
        "created_at": now,
        "updated_at": now,
    }
    write_json(path, campaign)
    emit_json(
        {
            "ok": True,
            "action": "new",
            "campaign_id": arguments.campaign_id,
            "campaign_dir": str(campaign_dir(arguments.campaign_id)),
            "suite_id": suite["id"],
            "model": suite["requested_model"],
            "tasks": task_ids,
            "dashboard_command": dashboard_command(arguments.campaign_id),
        }
    )


def add_run(arguments: argparse.Namespace) -> None:
    validate_run_id(arguments.campaign_id)
    validate_run_id(arguments.run_id)
    campaign = load_campaign(arguments.campaign_id)
    if arguments.task_id not in campaign["tasks"]:
        fail(2, "unknown_task_id")
    task_runs = campaign["runs"].setdefault(arguments.task_id, [])
    if arguments.run_id in task_runs:
        fail(2, "duplicate_run_id")
    task_runs.append(arguments.run_id)
    campaign["updated_at"] = utc_now()
    write_json(campaign_path(arguments.campaign_id), campaign)
    emit_json(
        {
            "ok": True,
            "action": "add-run",
            "campaign_id": arguments.campaign_id,
            "task_id": arguments.task_id,
            "run_id": arguments.run_id,
            "task_runs": task_runs,
        }
    )


def status(arguments: argparse.Namespace) -> None:
    validate_run_id(arguments.campaign_id)
    campaign = load_campaign(arguments.campaign_id)
    emit_json(
        {
            "ok": True,
            "action": "status",
            "campaign_id": arguments.campaign_id,
            "campaign": campaign,
            "dashboard_command": dashboard_command(arguments.campaign_id),
        }
    )


def main() -> None:
    parser = argparse.ArgumentParser()
    subparsers = parser.add_subparsers(dest="action", required=True)

    new_parser = subparsers.add_parser("new")
    new_parser.add_argument("suite", type=Path)
    new_parser.add_argument("--campaign-id", required=True, dest="campaign_id")

    add_run_parser = subparsers.add_parser("add-run")
    add_run_parser.add_argument("campaign_id")
    add_run_parser.add_argument("task_id")
    add_run_parser.add_argument("run_id")

    status_parser = subparsers.add_parser("status")
    status_parser.add_argument("campaign_id")

    arguments = parser.parse_args()
    {"new": new_campaign, "add-run": add_run, "status": status}[arguments.action](arguments)


if __name__ == "__main__":
    main()
