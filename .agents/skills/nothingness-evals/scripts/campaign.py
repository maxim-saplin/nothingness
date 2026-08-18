from __future__ import annotations

import argparse
from pathlib import Path
from typing import Any

from common import ROOT, RUNS_ROOT, SCRIPT_DIR, emit_json, fail, load_suite, read_json, sha256, utc_now, validate_run_id, write_json

CAMPAIGNS_ROOT = RUNS_ROOT / "campaigns"
MAX_RETRIES = 2
PROTOCOL_MODE = "single-campaign-retry-1.5"
# Judge wall clock: prepare/start + the candidate's own budget + evidence/score.
# A parent that times the judge at or below the candidate budget will kill it
# mid-observe and force a billed retry — gpt-5.4-nano-medium-20260815-0548.
JUDGE_PREPARE_SECONDS = 600
JUDGE_SCORE_SECONDS = 1200


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
        or not isinstance(campaign.get("retry_log"), dict)
    ):
        fail(3, "invalid_campaign_state")
    return campaign


def task_runs(campaign: dict[str, Any], task_id: str) -> list[str]:
    runs = campaign["runs"].get(task_id) or []
    return [item for item in runs if isinstance(item, str)]


def task_failures(campaign: dict[str, Any], task_id: str) -> list[dict[str, Any]]:
    failures = campaign["retry_log"].get(task_id) or []
    return [item for item in failures if isinstance(item, dict)]


def run_has_result(run_id: str, validity: str | None = None) -> bool:
    path = RUNS_ROOT / run_id / "result.json"
    if not path.is_file():
        return False
    if validity is None:
        return True
    try:
        return read_json(path).get("validity") == validity
    except SystemExit:
        return False


def run_retry(campaign: dict[str, Any], run_id: str) -> int:
    retries = campaign.get("run_retries") or {}
    value = retries.get(run_id, 0)
    return value if isinstance(value, int) else 0


def task_timeout_seconds(task_id: str) -> int:
    path = ROOT / "evals" / "tasks" / f"{task_id}.json"
    if not path.is_file():
        fail(2, f"task_manifest_not_found:{task_id}")
    limits = read_json(path).get("limits")
    value = limits.get("timeout_seconds") if isinstance(limits, dict) else None
    if not isinstance(value, int) or value <= 0:
        fail(2, f"task_timeout_missing:{task_id}")
    return value


def judge_wall_seconds(timeout_seconds: int) -> int:
    if not isinstance(timeout_seconds, int) or timeout_seconds <= 0:
        fail(2, "task_timeout_invalid")
    return JUDGE_PREPARE_SECONDS + timeout_seconds + JUDGE_SCORE_SECONDS


def new_campaign(arguments: argparse.Namespace) -> None:
    validate_run_id(arguments.campaign_id)
    path = campaign_path(arguments.campaign_id)
    if path.exists():
        fail(2, "campaign_already_exists")
    suite_path = arguments.suite.resolve()
    suite = load_suite(suite_path)
    if not arguments.allow_repeat:
        for existing in CAMPAIGNS_ROOT.glob("*/campaign.json"):
            try:
                other = read_json(existing)
            except SystemExit:
                continue
            if other.get("protocol_mode") == PROTOCOL_MODE and other.get("suite_id") == suite["id"]:
                fail(2, f"campaign_already_exists_for_model:{suite['id']} -- pass --allow-repeat for an intentional variability attempt")
    task_ids = [task["id"] for task in suite["tasks"]]
    now = utc_now()
    campaign = {
        "schema_version": 2,
        "protocol_mode": PROTOCOL_MODE,
        "campaign_id": arguments.campaign_id,
        "suite_id": suite["id"],
        "suite_path": str(suite_path.relative_to(ROOT)) if suite_path.is_relative_to(ROOT) else str(suite_path),
        "suite_manifest_sha256": sha256(suite_path),
        "model": suite["requested_model"],
        "status": "running",
        "max_retries_per_task": MAX_RETRIES,
        "tasks": task_ids,
        "runs": {task_id: [] for task_id in task_ids},
        "run_retries": {},
        "retry_log": {task_id: [] for task_id in task_ids},
        "costs": {"accepted_tasks_usd": None, "campaign_usd": None},
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
            "max_retries_per_task": MAX_RETRIES,
            "dashboard_command": dashboard_command(arguments.campaign_id),
        }
    )


def add_run(arguments: argparse.Namespace) -> None:
    validate_run_id(arguments.campaign_id)
    validate_run_id(arguments.run_id)
    campaign = load_campaign(arguments.campaign_id)
    if campaign.get("status") != "running":
        fail(2, f"campaign_not_running:{campaign.get('status')}")
    if arguments.task_id not in campaign["tasks"]:
        fail(2, "unknown_task_id")
    runs = task_runs(campaign, arguments.task_id)
    failures = task_failures(campaign, arguments.task_id)
    if any(run_has_result(run_id, "valid") for run_id in runs):
        fail(2, "task_already_complete")
    if runs:
        latest = runs[-1]
        if not any(item.get("run_id") == latest for item in failures):
            fail(2, f"run_unresolved:{latest} -- reconcile or record its retry before starting a fresh run")
    retry = max((run_retry(campaign, run_id) for run_id in runs), default=-1) + 1
    if retry > MAX_RETRIES:
        fail(2, "retry_budget_exhausted")
    campaign["runs"].setdefault(arguments.task_id, []).append(arguments.run_id)
    campaign.setdefault("run_retries", {})[arguments.run_id] = retry
    campaign["updated_at"] = utc_now()
    write_json(campaign_path(arguments.campaign_id), campaign)
    emit_json(
        {
            "ok": True,
            "action": "add-run",
            "campaign_id": arguments.campaign_id,
            "task_id": arguments.task_id,
            "run_id": arguments.run_id,
            "retry": retry,
            "task_runs": campaign["runs"][arguments.task_id],
        }
    )


def record_retry(arguments: argparse.Namespace) -> None:
    validate_run_id(arguments.campaign_id)
    validate_run_id(arguments.run_id)
    campaign = load_campaign(arguments.campaign_id)
    if arguments.task_id not in campaign["tasks"]:
        fail(2, "unknown_task_id")
    runs = task_runs(campaign, arguments.task_id)
    if arguments.run_id not in runs:
        fail(2, "run_not_registered")
    if run_has_result(arguments.run_id, "valid"):
        fail(2, "cannot_retry_completed_task")
    failures = task_failures(campaign, arguments.task_id)
    if any(item.get("run_id") == arguments.run_id for item in failures):
        fail(2, "retry_already_recorded")
    retry = run_retry(campaign, arguments.run_id)
    cost: float | None
    try:
        cost = float(arguments.cost_usd) if arguments.cost_usd is not None else None
    except ValueError:
        fail(2, f"retry_cost_not_a_number:{arguments.cost_usd}")
    failures.append({"run_id": arguments.run_id, "retry": retry, "reason": arguments.reason, "cost_usd": cost, "recorded_at": utc_now()})
    campaign["retry_log"][arguments.task_id] = failures
    if retry >= MAX_RETRIES:
        campaign["status"] = "aborted"
        campaign["abort_reason"] = f"retry_exhausted:{arguments.task_id}"
    campaign["updated_at"] = utc_now()
    write_json(campaign_path(arguments.campaign_id), campaign)
    emit_json({"ok": True, "action": "retry", "campaign_id": arguments.campaign_id, "task_id": arguments.task_id, "run_id": arguments.run_id, "retry": retry, "status": campaign["status"]})


def next_task(arguments: argparse.Namespace) -> None:
    validate_run_id(arguments.campaign_id)
    campaign = load_campaign(arguments.campaign_id)
    if campaign.get("status") == "aborted":
        fail(2, f"campaign_aborted:{campaign.get('abort_reason', 'unspecified')}")
    pending = []
    for task_id in campaign["tasks"]:
        runs = task_runs(campaign, task_id)
        if any(run_has_result(run_id, "valid") for run_id in runs):
            continue
        failures = task_failures(campaign, task_id)
        if runs and not any(item.get("run_id") == runs[-1] for item in failures) and not run_has_result(runs[-1]):
            fail(2, f"run_unresolved:{runs[-1]} -- do not attach a judge; reconcile it before continuing")
        retry = max((run_retry(campaign, run_id) for run_id in runs), default=-1) + 1
        if retry > MAX_RETRIES:
            campaign["status"] = "aborted"
            campaign["abort_reason"] = f"retry_exhausted:{task_id}"
            campaign["updated_at"] = utc_now()
            write_json(campaign_path(arguments.campaign_id), campaign)
            fail(2, f"campaign_aborted:{campaign['abort_reason']}")
        pending.append((task_id, retry))
    if not pending:
        emit_json({"ok": True, "action": "next", "campaign_id": arguments.campaign_id, "done": True, "remaining": 0, "next_step": "judge-run.py finalize --campaign <id> --from-sandbox <each judge sandbox>"})
        return
    task_id, retry = pending[0]
    sandbox = f".tmp/judge-{arguments.campaign_id}-{task_id}-retry-{retry}"
    suite = campaign.get("suite_path") or ""
    scripts = SCRIPT_DIR.relative_to(ROOT)
    timeout = task_timeout_seconds(task_id)
    wall = judge_wall_seconds(timeout)
    emit_json(
        {
            "ok": True,
            "action": "next",
            "campaign_id": arguments.campaign_id,
            "done": False,
            "task_id": task_id,
            "retry": retry,
            "remaining": len(pending),
            "suite_path": suite,
            "rubric_path": f"evals/tasks/rubrics/{task_id}.md",
            "timeout_seconds": timeout,
            "judge_wall_seconds": wall,
            "sandbox": sandbox,
            "create_sandbox_command": f"uv run python {scripts}/judge-sandbox.py create {sandbox}",
            "judge_working_directory": sandbox,
            "judge_environment": {"NOTHINGNESS_EVAL_RUNS_ROOT": str(RUNS_ROOT)},
            "judge_start_command": f"uv run python {scripts}/judge-run.py start {suite} {task_id} --campaign {arguments.campaign_id} --judge <who-you-are>",
        }
    )


def complete(arguments: argparse.Namespace) -> None:
    campaign = load_campaign(arguments.campaign_id)
    if campaign.get("status") == "aborted":
        fail(2, f"campaign_aborted:{campaign.get('abort_reason', 'unspecified')}")
    accepted_costs: list[float] = []
    retry_costs: list[float] = []
    for task_id in campaign["tasks"]:
        runs = task_runs(campaign, task_id)
        accepted = next((read_json(RUNS_ROOT / run_id / "result.json") for run_id in runs if run_has_result(run_id, "valid")), None)
        if not isinstance(accepted, dict):
            fail(2, f"task_not_complete:{task_id}")
        value = (accepted.get("cost_usd") or {}).get("combined")
        if not isinstance(value, (int, float)):
            fail(2, f"task_cost_unknown:{task_id}")
        accepted_costs.append(float(value))
        for failure in task_failures(campaign, task_id):
            value = failure.get("cost_usd")
            if value is None:
                retry_costs.append(None)
            elif isinstance(value, (int, float)):
                retry_costs.append(float(value))
            else:
                fail(2, f"retry_cost_invalid:{task_id}")
    accepted_total = sum(accepted_costs)
    campaign_total = accepted_total + sum(value for value in retry_costs if isinstance(value, (int, float))) if all(value is not None for value in retry_costs) else None
    campaign["status"] = "complete"
    campaign["costs"] = {"accepted_tasks_usd": accepted_total, "campaign_usd": campaign_total}
    campaign["completed_at"] = utc_now()
    campaign["updated_at"] = campaign["completed_at"]
    write_json(campaign_path(arguments.campaign_id), campaign)
    emit_json({"ok": True, "action": "complete", "campaign_id": arguments.campaign_id, "status": "complete", "costs": campaign["costs"]})


def status(arguments: argparse.Namespace) -> None:
    validate_run_id(arguments.campaign_id)
    campaign = load_campaign(arguments.campaign_id)
    emit_json({"ok": True, "action": "status", "campaign_id": arguments.campaign_id, "campaign": campaign, "dashboard_command": dashboard_command(arguments.campaign_id)})


def main() -> None:
    parser = argparse.ArgumentParser()
    subparsers = parser.add_subparsers(dest="action", required=True)

    new_parser = subparsers.add_parser("new")
    new_parser.add_argument("suite", type=Path)
    new_parser.add_argument("--campaign-id", required=True, dest="campaign_id")
    new_parser.add_argument("--allow-repeat", action="store_true", help="create another campaign for the same suite for an intentional variability attempt")

    add_run_parser = subparsers.add_parser("add-run")
    add_run_parser.add_argument("campaign_id")
    add_run_parser.add_argument("task_id")
    add_run_parser.add_argument("run_id")

    retry_parser = subparsers.add_parser("retry")
    retry_parser.add_argument("campaign_id")
    retry_parser.add_argument("task_id")
    retry_parser.add_argument("--run-id", required=True)
    retry_parser.add_argument("--reason", required=True)
    retry_parser.add_argument("--cost-usd")

    next_parser = subparsers.add_parser("next")
    next_parser.add_argument("campaign_id")

    complete_parser = subparsers.add_parser("complete")
    complete_parser.add_argument("campaign_id")

    status_parser = subparsers.add_parser("status")
    status_parser.add_argument("campaign_id")

    arguments = parser.parse_args()
    handlers = {"new": new_campaign, "add-run": add_run, "retry": record_retry, "next": next_task, "complete": complete, "status": status}
    handlers[arguments.action](arguments)


if __name__ == "__main__":
    main()
