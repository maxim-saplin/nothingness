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
        # Recorded so `next` can hand a judge everything it needs to start its
        # own trial, rather than the caller having to carry the suite path along
        # by hand for seven tasks in a row.
        "suite_path": str(suite_path.relative_to(ROOT)) if suite_path.is_relative_to(ROOT) else str(suite_path),
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
    # Idempotent. `judge-run.py start --campaign` registers the run itself, but
    # the skill also told people to call this after every start -- so the second
    # call failed with `duplicate_run_id` on a run that was correctly recorded,
    # which reads as a real error. Registering a fact that is already true is
    # not a failure.
    if arguments.run_id not in task_runs:
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


def next_task(arguments: argparse.Namespace) -> None:
    """The next task with no scored run, and the brief to hand a judge for it.

    The per-task loop used to live only as a numbered list in the manager's
    skill, so "run all seven tasks" depended on an agent working through prose
    without losing its place -- and it did lose its place. Driving the loop off
    campaign state instead makes stopping early visible (`remaining` is not
    zero) and makes resuming exact: a campaign interrupted after task 3 comes
    back at task 4 with no bookkeeping.

    A task counts as done when one of its runs has a `result.json` -- the file
    `decide` writes. Attempts that died before scoring leave no result, so they
    are correctly retried rather than silently counted."""
    validate_run_id(arguments.campaign_id)
    campaign = load_campaign(arguments.campaign_id)
    pending = []
    for task_id in campaign["tasks"]:
        runs = campaign["runs"].get(task_id) or []
        if not any((RUNS_ROOT / run_id / "result.json").is_file() for run_id in runs):
            pending.append((task_id, runs))
    if not pending:
        emit_json({"ok": True, "action": "next", "campaign_id": arguments.campaign_id, "done": True, "remaining": 0, "next_step": "judge-run.py finalize --from-sandbox <each judge sandbox>"})
        return
    task_id, previous = pending[0]
    sandbox = f".tmp/judge-{arguments.campaign_id}-{task_id}"
    suite = campaign.get("suite_path") or ""
    scripts = SCRIPT_DIR.relative_to(ROOT)
    emit_json(
        {
            "ok": True,
            "action": "next",
            "campaign_id": arguments.campaign_id,
            "done": False,
            "task_id": task_id,
            "trial": 1,
            "previous_attempts": previous,
            "remaining": len(pending),
            "suite_path": suite,
            "rubric_path": f"evals/tasks/rubrics/{task_id}.md",
            "sandbox": sandbox,
            # Everything the manager needs to stand up one judge, in order.
            "create_sandbox_command": f"uv run python {scripts}/judge-sandbox.py create {sandbox}",
            "judge_working_directory": sandbox,
            "judge_environment": {"NOTHINGNESS_EVAL_RUNS_ROOT": str(RUNS_ROOT)},
            "judge_start_command": f"uv run python {scripts}/judge-run.py start {suite} {task_id} --trial 1 --campaign {arguments.campaign_id} --judge <who-you-are>",
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

    next_parser = subparsers.add_parser("next")
    next_parser.add_argument("campaign_id")

    status_parser = subparsers.add_parser("status")
    status_parser.add_argument("campaign_id")

    arguments = parser.parse_args()
    {"new": new_campaign, "add-run": add_run, "next": next_task, "status": status}[arguments.action](arguments)


if __name__ == "__main__":
    main()
