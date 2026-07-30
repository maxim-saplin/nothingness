from __future__ import annotations

import argparse
import shutil
import subprocess
import sys
from pathlib import Path
from typing import Any

from campaign_common import (
    CAMPAIGNS_ROOT,
    MAX_ATTEMPTS_PER_TASK,
    RESUMABLE_STATUSES,
    TERMINAL_STATUSES,
    active_run_resources_absent,
    append_event,
    apply_result_costs,
    attempt_storage,
    budget_exceeded,
    build_initial_state,
    campaign_dir,
    campaign_lock,
    campaign_state_path,
    cleanup_verified,
    current_task,
    load_campaign_state,
    published_trial_dir,
    run_id_for,
    save_campaign_state,
    stage_attempt_publication,
    stage_invalid_archive,
    transition_status,
    usage_from_result,
    validate_campaign_id,
    validate_suite_for_campaign,
    verify_resume_fingerprints,
)
from campaign_report import attempt_report_markdown, campaign_report_markdown, index_campaign_results, write_campaign_report
from common import ROOT, SCRIPT_DIR, emit_json, fail, read_json, run_dir, utc_now, write_json


def invoke(name: str, *arguments: str) -> dict[str, object]:
    result = subprocess.run(
        [sys.executable, str(SCRIPT_DIR / name), *arguments],
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        text=True,
    )
    if result.returncode:
        detail = result.stderr.strip().splitlines()[-1] if result.stderr.strip() else "unknown"
        fail(result.returncode, f"{name}_failed:{detail}")
    try:
        import json

        return json.loads(result.stdout)
    except json.JSONDecodeError:
        fail(3, f"{name}_invalid_output")
    raise AssertionError("unreachable")


def cmd_validate(arguments: argparse.Namespace) -> None:
    suite = validate_suite_for_campaign(arguments.suite.resolve())
    emit_json({"ok": True, "suite_id": suite["id"], "task_count": len(suite["tasks"])})


def launch_task(state: dict[str, Any], suite_path: Path) -> str:
    task = current_task(state)
    launched = invoke(
        "judge-run.py",
        "start",
        str(suite_path),
        task["id"],
        "--trial",
        "1",
    )
    run_id = str(launched["run_id"])
    state["current"]["run_id"] = run_id
    state["current"]["phase"] = "running"
    state["current"]["started_at"] = utc_now()
    task["status"] = "running"
    transition_status(state, "running", actor="controller", reason="task_launched", run_id=run_id)
    return run_id


def register_attempt_from_run(state: dict[str, Any], run: Path, *, synthetic: bool = False) -> dict[str, Any]:
    result_path = run / "result.json"
    if not result_path.is_file():
        fail(4, "attempt_result_missing")
    if not synthetic and not cleanup_verified(run):
        fail(4, "cleanup_not_verified")
    result = read_json(result_path)
    task = current_task(state)
    attempt_number = state["current"]["attempt"]
    record = {
        "attempt": attempt_number,
        "run_id": result.get("run_id"),
        "validity": result.get("validity"),
        "outcome": result.get("outcome"),
        "score": result.get("score"),
        "published_path": None,
        "archive_path": None,
        "cleanup_verified": cleanup_verified(run),
    }
    candidate, admission, combined, tokens, unknown = usage_from_result(result)
    record["cost_usd"] = {"candidate": candidate, "admission": admission, "combined": combined}
    record["tokens"] = tokens
    task["attempts"].append(record)
    apply_result_costs(state, result)
    storage = attempt_storage(state["campaign_id"], task["id"], attempt_number)
    storage.mkdir(parents=True, exist_ok=True)
    write_json(storage / "result.json", result)
    if (run / "cleanup.json").is_file():
        shutil.copy2(run / "cleanup.json", storage / "cleanup.json")
    return result


def publish_valid_attempt(state: dict[str, Any], result: dict[str, Any], run: Path) -> Path:
    task = current_task(state)
    attempt = state["current"]["attempt"]
    report = attempt_report_markdown(
        result=result,
        campaign_id=state["campaign_id"],
        task_id=task["id"],
        attempt=attempt,
    )
    destination = stage_attempt_publication(
        run=run,
        result=result,
        campaign_id=state["campaign_id"],
        model_id=state["model"]["path_id"],
        task_id=task["id"],
        report_markdown=report,
    )
    task["attempts"][-1]["published_path"] = str(destination)
    task["published_path"] = str(destination)
    task["status"] = "published"
    return destination


def archive_invalid_attempt(state: dict[str, Any], result: dict[str, Any], run: Path) -> Path:
    task = current_task(state)
    attempt = state["current"]["attempt"]
    report = attempt_report_markdown(
        result=result,
        campaign_id=state["campaign_id"],
        task_id=task["id"],
        attempt=attempt,
    )
    destination = stage_invalid_archive(
        run=run,
        result=result,
        campaign_id=state["campaign_id"],
        task_id=task["id"],
        attempt=attempt,
        report_markdown=report,
    )
    task["attempts"][-1]["archive_path"] = str(destination)
    task["status"] = "invalid_archived"
    state["invalid_attempt_count"] = int(state.get("invalid_attempt_count", 0)) + 1
    return destination


def complete_task_barrier(state: dict[str, Any], result: dict[str, Any], run: Path) -> None:
    validity = result.get("validity")
    if validity == "valid":
        publish_valid_attempt(state, result, run)
        append_event(state, actor="controller", reason="valid_published", prior=state["status"], new=state["status"], task_id=current_task(state)["id"])
    else:
        archive_invalid_attempt(state, result, run)
        append_event(state, actor="controller", reason="invalid_archived", prior=state["status"], new=state["status"], task_id=current_task(state)["id"])


def should_stop_campaign(state: dict[str, Any], result: dict[str, Any]) -> str | None:
    if state.get("abort_requested"):
        return "aborted_operator"
    task = current_task(state)
    if result.get("validity") != "valid":
        if len(task["attempts"]) >= MAX_ATTEMPTS_PER_TASK:
            return "blocked_infrastructure"
        return None
    if state["current"]["task_index"] >= len(state["tasks"]) - 1:
        return "completed"
    if budget_exceeded(state):
        return "paused_budget"
    return None


def advance_after_attempt(state: dict[str, Any], result: dict[str, Any]) -> None:
    terminal = should_stop_campaign(state, result)
    if terminal:
        transition_status(state, terminal, actor="controller", reason="campaign_terminal", task_id=current_task(state)["id"])
        state["current"]["phase"] = "terminal"
        write_campaign_report(state)
        return
    if result.get("validity") != "valid":
        state["current"]["attempt"] += 1
        state["current"]["run_id"] = None
        state["current"]["phase"] = "prepared"
        state["status"] = "prepared"
        append_event(state, actor="controller", reason="retry_scheduled", prior="running", new="prepared", attempt=state["current"]["attempt"])
        return
    next_index = state["current"]["task_index"] + 1
    state["current"]["task_index"] = next_index
    state["current"]["task_id"] = state["tasks"][next_index]["id"]
    state["current"]["attempt"] = 1
    state["current"]["run_id"] = None
    state["current"]["phase"] = "prepared"
    state["status"] = "prepared"
    append_event(
        state,
        actor="controller",
        reason="next_task_prepared",
        prior="running",
        new="prepared",
        task_id=state["current"]["task_id"],
    )


def cmd_start(arguments: argparse.Namespace) -> None:
    validate_campaign_id(arguments.campaign_id)
    suite_path = arguments.suite.resolve()
    if campaign_state_path(arguments.campaign_id).is_file():
        fail(2, "campaign_already_exists")
    state = build_initial_state(
        campaign_id=arguments.campaign_id,
        suite_path=suite_path,
        cost_ceiling_usd=arguments.candidate_admission_cost_ceiling_usd,
        token_ceiling=arguments.token_ceiling,
    )
    with campaign_lock(arguments.campaign_id):
        save_campaign_state(state)
        if arguments.dry_run:
            emit_json({"ok": True, "action": "start", "campaign_id": arguments.campaign_id, "dry_run": True})
            return
        run_id = launch_task(state, suite_path)
        save_campaign_state(state)
    emit_json(
        {
            "ok": True,
            "action": "start",
            "campaign_id": arguments.campaign_id,
            "run_id": run_id,
            "task_id": state["current"]["task_id"],
            "dashboard_command": f"uv run python {SCRIPT_DIR.relative_to(ROOT)}/watch-campaign.py --campaign {arguments.campaign_id} --once",
        }
    )


def cmd_sync(arguments: argparse.Namespace) -> None:
    with campaign_lock(arguments.campaign):
        state = load_campaign_state(arguments.campaign)
        if state["status"] in TERMINAL_STATUSES:
            emit_json({"ok": True, "action": "sync", "status": state["status"], "terminal": True})
            return
        run_id = state["current"].get("run_id")
        if not run_id:
            fail(4, "no_active_run")
        run = run_dir(run_id)
        if not (run / "result.json").is_file():
            emit_json({"ok": True, "action": "sync", "status": state["status"], "awaiting": "result"})
            return
        if not cleanup_verified(run):
            emit_json({"ok": True, "action": "sync", "status": state["status"], "awaiting": "cleanup"})
            return
        result = register_attempt_from_run(state, run)
        complete_task_barrier(state, result, run)
        advance_after_attempt(state, result)
        write_campaign_report(state)
        save_campaign_state(state)
        launched = None
        if state["status"] == "prepared" and state["current"]["phase"] == "prepared":
            suite_path = ROOT / state["suite"]["path"]
            launched = launch_task(state, suite_path)
            save_campaign_state(state)
    emit_json({"ok": True, "action": "sync", "status": state["status"], "launched": launched})


def prepare_next_task_if_needed(state: dict[str, Any]) -> None:
    task = current_task(state)
    if task.get("status") != "published":
        return
    if state["current"]["task_index"] >= len(state["tasks"]) - 1:
        return
    next_index = state["current"]["task_index"] + 1
    state["current"]["task_index"] = next_index
    state["current"]["task_id"] = state["tasks"][next_index]["id"]
    state["current"]["attempt"] = 1
    state["current"]["run_id"] = None
    state["current"]["phase"] = "prepared"
    append_event(
        state,
        actor="controller",
        reason="next_task_prepared",
        prior=state["status"],
        new=state["status"],
        task_id=state["current"]["task_id"],
    )


def cmd_resume(arguments: argparse.Namespace) -> None:
    with campaign_lock(arguments.campaign):
        state = load_campaign_state(arguments.campaign)
        if state["status"] in TERMINAL_STATUSES:
            fail(4, "campaign_already_terminal")
        suite_path = (ROOT / state["suite"]["path"]).resolve()
        verify_resume_fingerprints(state, suite_path)
        budget = state["budget"]
        if arguments.candidate_admission_cost_ceiling_usd is not None:
            budget["candidate_admission_cost_ceiling_usd"] = arguments.candidate_admission_cost_ceiling_usd
            budget["overrides"].append(
                {"timestamp": utc_now(), "field": "candidate_admission_cost_ceiling_usd", "value": arguments.candidate_admission_cost_ceiling_usd}
            )
        if arguments.token_ceiling is not None:
            budget["token_ceiling"] = arguments.token_ceiling
            budget["overrides"].append({"timestamp": utc_now(), "field": "token_ceiling", "value": arguments.token_ceiling})
        if arguments.allow_unknown_cost:
            budget["allow_unknown_cost"] = True
            budget["overrides"].append({"timestamp": utc_now(), "field": "allow_unknown_cost", "value": True})
        if state["status"] == "cleanup_retrying":
            if not active_run_resources_absent(state["current"].get("run_id")):
                fail(4, "cleanup_retry_resources_present")
            transition_status(state, "prepared", actor="operator", reason="cleanup_verified")
        elif state["status"] == "paused_budget":
            if budget_exceeded(state):
                fail(4, "budget_still_exceeded")
            transition_status(state, "prepared", actor="operator", reason="budget_resumed")
            prepare_next_task_if_needed(state)
        elif state["status"] not in {"prepared", "running"}:
            fail(4, f"cannot_resume_from:{state['status']}")
        run_id = state["current"].get("run_id")
        if run_id and (run_dir(run_id) / "result.json").is_file() and not cleanup_verified(run_dir(run_id)):
            emit_json({"ok": True, "action": "resume", "status": state["status"], "awaiting": "cleanup"})
            save_campaign_state(state)
            return
        if run_id and (run_dir(run_id) / "result.json").is_file() and cleanup_verified(run_dir(run_id)):
            result = register_attempt_from_run(state, run_dir(run_id))
            complete_task_barrier(state, result, run_dir(run_id))
            advance_after_attempt(state, result)
        launched = None
        if state["status"] == "prepared" and not state["current"].get("run_id"):
            launched = launch_task(state, suite_path)
        write_campaign_report(state)
        save_campaign_state(state)
    emit_json({"ok": True, "action": "resume", "status": state["status"], "launched": launched})


def cmd_abort(arguments: argparse.Namespace) -> None:
    with campaign_lock(arguments.campaign):
        state = load_campaign_state(arguments.campaign)
        if state["status"] in TERMINAL_STATUSES:
            fail(4, "campaign_already_terminal")
        state["abort_requested"] = True
        append_event(state, actor="operator", reason="abort_requested", prior=state["status"], new=state["status"])
        save_campaign_state(state)
    emit_json({"ok": True, "action": "abort", "abort_requested": True})


def cmd_report(arguments: argparse.Namespace) -> None:
    if arguments.reindex:
        campaign_path, evals_path, model_path = index_campaign_results(arguments.campaign)
        emit_json(
            {
                "ok": True,
                "action": "index",
                "campaign_report": str(campaign_path),
                "evals_readme": str(evals_path),
                "model_readme": str(model_path),
            }
        )
        return
    state = load_campaign_state(arguments.campaign)
    path = write_campaign_report(state)
    emit_json({"ok": True, "action": "report", "path": str(path), "markdown": campaign_report_markdown(state)})


def cmd_status(arguments: argparse.Namespace) -> None:
    state = load_campaign_state(arguments.campaign)
    emit_json(
        {
            "ok": True,
            "campaign_id": state["campaign_id"],
            "status": state["status"],
            "current": state["current"],
            "budget": state["budget"],
            "invalid_attempt_count": state.get("invalid_attempt_count", 0),
        }
    )


def apply_synthetic_attempt(
    state: dict[str, Any],
    *,
    validity: str,
    outcome: str,
    score: int | None,
    combined_cost: float | None = None,
    tokens: int = 0,
    unknown_cost: bool = False,
) -> None:
    task = current_task(state)
    attempt = state["current"]["attempt"]
    run_id = run_id_for(state, task["id"], attempt)
    run = run_dir(run_id)
    run.mkdir(parents=True, exist_ok=True)
    result = {
        "schema_version": 2,
        "run_id": run_id,
        "validity": validity,
        "outcome": outcome,
        "score": score,
        "notes": f"Synthetic {validity} {outcome}",
        "task_id": task["id"],
        "cost_usd": {"candidate": combined_cost, "admission": 0.0, "combined": combined_cost},
        "intervention_count": 0,
        "unassisted": outcome == "unassisted_pass",
    }
    write_json(run / "result.json", result)
    write_json(run / "cleanup.json", {"ok": True, "container_removed": True})
    if unknown_cost:
        result["cost_usd"] = {"candidate": None, "admission": None, "combined": None}
        write_json(run / "result.json", result)
    register_attempt_from_run(state, run, synthetic=True)
    if unknown_cost:
        state["budget"]["unknown_cost"] = True
    else:
        state["budget"]["tokens"] = int(state["budget"]["tokens"]) + tokens
        if combined_cost is not None:
            state["budget"]["combined_cost_usd"] = round(float(state["budget"]["combined_cost_usd"]) + combined_cost, 8)
    complete_task_barrier(state, read_json(run / "result.json"), run)
    advance_after_attempt(state, read_json(run / "result.json"))


def cmd_synthetic(arguments: argparse.Namespace) -> None:
    with campaign_lock(arguments.campaign):
        state = load_campaign_state(arguments.campaign)
        if state["status"] in TERMINAL_STATUSES:
            fail(4, "campaign_already_terminal")
        apply_synthetic_attempt(
            state,
            validity=arguments.validity,
            outcome=arguments.outcome,
            score=arguments.score,
            combined_cost=arguments.combined_cost,
            tokens=arguments.tokens,
            unknown_cost=arguments.unknown_cost,
        )
        write_campaign_report(state)
        save_campaign_state(state)
    emit_json({"ok": True, "action": "synthetic", "status": state["status"]})


def main() -> None:
    parser = argparse.ArgumentParser()
    subparsers = parser.add_subparsers(dest="action", required=True)

    validate_parser = subparsers.add_parser("validate")
    validate_parser.add_argument("--suite", required=True, type=Path)

    start_parser = subparsers.add_parser("start")
    start_parser.add_argument("--suite", required=True, type=Path)
    start_parser.add_argument("--campaign-id", required=True)
    start_parser.add_argument("--candidate-admission-cost-ceiling-usd", type=float, default=1.0)
    start_parser.add_argument("--token-ceiling", type=int, default=5_000_000)
    start_parser.add_argument("--dry-run", action="store_true")

    sync_parser = subparsers.add_parser("sync")
    sync_parser.add_argument("--campaign", required=True)

    resume_parser = subparsers.add_parser("resume")
    resume_parser.add_argument("--campaign", required=True)
    resume_parser.add_argument("--candidate-admission-cost-ceiling-usd", type=float)
    resume_parser.add_argument("--token-ceiling", type=int)
    resume_parser.add_argument("--allow-unknown-cost", action="store_true")

    abort_parser = subparsers.add_parser("abort")
    abort_parser.add_argument("--campaign", required=True)

    report_parser = subparsers.add_parser("report")
    report_parser.add_argument("--campaign", required=True)
    report_parser.add_argument("--reindex", action="store_true", help="Rebuild campaign.md and README indexes from published results.")

    status_parser = subparsers.add_parser("status")
    status_parser.add_argument("--campaign", required=True)

    synthetic_parser = subparsers.add_parser("synthetic")
    synthetic_parser.add_argument("--campaign", required=True)
    synthetic_parser.add_argument("--validity", required=True, choices=("valid", "invalid_infrastructure"))
    synthetic_parser.add_argument("--outcome", required=True)
    synthetic_parser.add_argument("--score", type=int)
    synthetic_parser.add_argument("--combined-cost", type=float, default=0.0)
    synthetic_parser.add_argument("--tokens", type=int, default=0)
    synthetic_parser.add_argument("--unknown-cost", action="store_true")

    arguments = parser.parse_args()
    handlers = {
        "validate": cmd_validate,
        "start": cmd_start,
        "sync": cmd_sync,
        "resume": cmd_resume,
        "abort": cmd_abort,
        "report": cmd_report,
        "status": cmd_status,
        "synthetic": cmd_synthetic,
    }
    handlers[arguments.action](arguments)


if __name__ == "__main__":
    main()
