from __future__ import annotations

import argparse
import subprocess
import sys
from pathlib import Path

from common import ROOT, SCRIPT_DIR, command, emit_json, fail, load_suite, read_json, run_dir, utc_now, validate_run_id, write_json


def invoke(name: str, *arguments: str) -> dict[str, object]:
    result = command([sys.executable, str(SCRIPT_DIR / name), *arguments], stdout=subprocess.PIPE, stderr=subprocess.PIPE)
    if result.returncode:
        detail = result.stderr.strip().splitlines()[-1] if result.stderr.strip() else "unknown"
        fail(result.returncode, f"{name}_failed:{detail}")
    try:
        return __import__("json").loads(result.stdout)
    except __import__("json").JSONDecodeError:
        fail(3, f"{name}_invalid_output")
    raise AssertionError("unreachable")


def start(arguments: argparse.Namespace) -> None:
    suite_path = arguments.suite.resolve()
    suite = load_suite(suite_path)
    trial_tag = "calibration" if arguments.calibration else f"trial-{arguments.trial:02d}"
    prefix = f"{suite['id']}-{arguments.task_id}-{trial_tag}-attempt-"
    existing = [path.name for path in (ROOT / ".tmp" / "evals").glob(f"{prefix}*") if path.is_dir()]
    attempts = []
    for name in existing:
        try:
            attempts.append(int(name.removeprefix(prefix)))
        except ValueError:
            continue
    run_id = f"{prefix}{max(attempts, default=0) + 1:02d}"
    validate_run_id(run_id)
    prepare_arguments = [arguments.task_id, run_id, "--suite", str(suite_path), "--trial", str(arguments.trial)]
    if arguments.calibration:
        prepare_arguments.append("--calibration")
    prepared = invoke("prepare-run.py", *prepare_arguments)
    try:
        preflight = invoke("preflight.py", run_id)
        launch = invoke("launch-candidate.py", run_id)
    except BaseException:
        invoke("cleanup.py", run_id)
        raise
    result = {"ok": True, "action": "start", "run_id": run_id, "suite_id": suite["id"], "task_id": arguments.task_id, "trial": arguments.trial, "calibration": arguments.calibration, "requested_model": prepared["requested_model"], "selected_model": prepared["selected_model"], "identity_verified": prepared["requested_model"] == prepared["selected_model"], "novnc_url": prepared["novnc_url"], "preflight": preflight["ok"], "launch": launch["ok"], "judge_events_command": f"uv run python {SCRIPT_DIR.relative_to(ROOT)}/judge-events.py {run_id}", "dashboard_command": f"uv run python {SCRIPT_DIR.relative_to(ROOT)}/watch-eval.py {run_id}", "started_at": utc_now()}
    write_json(run_dir(run_id) / "judge-start.json", result)
    emit_json(result)


def collect(arguments: argparse.Namespace) -> None:
    run = run_dir(arguments.run_id)
    if not (run / "run.json").is_file():
        fail(3, "run_not_prepared")
    completion = command(["docker", "exec", read_json(run / "run.json")["container"], "cat", "/run/nothingness/candidate-completion.json"], stdout=subprocess.PIPE, stderr=subprocess.DEVNULL)
    if completion.returncode:
        fail(4, "judge_must_finish_or_abort_candidate_before_collection")
    collected = invoke("collect.py", arguments.run_id)
    summary = invoke("summarize-run.py", arguments.run_id)
    emit_json({"ok": True, "action": "collect", "run_id": arguments.run_id, "collected": collected["ok"], "summary": summary})


def decide(arguments: argparse.Namespace) -> None:
    classify = [arguments.run_id, "--validity", arguments.validity, "--outcome", arguments.outcome]
    if arguments.score is not None:
        classify.extend(("--score", str(arguments.score)))
    if arguments.notes:
        classify.extend(("--notes", arguments.notes))
    for observation_id in arguments.observation_id:
        classify.extend(("--observation-id", observation_id))
    invoke("classify-run.py", *classify)
    result = read_json(run_dir(arguments.run_id) / "result.json")
    emit_json({"ok": True, "action": "decide", "run_id": arguments.run_id, "result": result})


def cleanup(arguments: argparse.Namespace) -> None:
    run = run_dir(arguments.run_id)
    if not (run / "result.json").is_file() and not arguments.force:
        fail(2, "judge_decision_required_before_cleanup")
    result = invoke("cleanup.py", arguments.run_id)
    emit_json({"ok": True, "action": "cleanup", "run_id": arguments.run_id, "cleanup": result})


def main() -> None:
    parser = argparse.ArgumentParser()
    subparsers = parser.add_subparsers(dest="action", required=True)
    start_parser = subparsers.add_parser("start")
    start_parser.add_argument("suite", type=Path)
    start_parser.add_argument("task_id")
    start_parser.add_argument("--trial", required=True, type=int)
    start_parser.add_argument("--calibration", action="store_true")
    collect_parser = subparsers.add_parser("collect")
    collect_parser.add_argument("run_id")
    decide_parser = subparsers.add_parser("decide")
    decide_parser.add_argument("run_id")
    decide_parser.add_argument("--validity", required=True, choices=("valid", "invalid_infrastructure", "unassigned"))
    decide_parser.add_argument("--outcome", required=True, choices=("unassisted_pass", "assisted_pass", "candidate_fail", "unassigned"))
    decide_parser.add_argument("--score", type=int)
    decide_parser.add_argument("--notes", required=True)
    decide_parser.add_argument("--observation-id", action="append", default=[])
    cleanup_parser = subparsers.add_parser("cleanup")
    cleanup_parser.add_argument("run_id")
    cleanup_parser.add_argument("--force", action="store_true")
    arguments = parser.parse_args()
    if hasattr(arguments, "run_id"):
        validate_run_id(arguments.run_id)
    {"start": start, "collect": collect, "decide": decide, "cleanup": cleanup}[arguments.action](arguments)


if __name__ == "__main__":
    main()