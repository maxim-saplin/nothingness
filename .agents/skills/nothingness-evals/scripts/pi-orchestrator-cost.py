#!/usr/bin/env python3
"""Record Pi orchestrator and subagent cost for one evaluation campaign."""

from __future__ import annotations

import argparse
import json
import os
import tempfile
from pathlib import Path
from typing import Any

from common import ROOT, emit_json, fail, write_json


ORCHESTRATOR_FILE = "orchestrator.json"


def number(value: object) -> float | None:
    return value if isinstance(value, (int, float)) and not isinstance(value, bool) else None


def session_cost(path: Path) -> float:
    total = 0.0
    try:
        lines = path.read_text(encoding="utf-8").splitlines()
    except OSError as error:
        fail(3, f"pi_session_file_unreadable:{error}")
    for line in lines:
        try:
            entry = json.loads(line)
        except json.JSONDecodeError:
            continue
        message = entry.get("message") if isinstance(entry, dict) else None
        if not isinstance(message, dict) or message.get("role") != "assistant":
            continue
        usage = message.get("usage")
        cost = usage.get("cost") if isinstance(usage, dict) else None
        value = cost.get("total") if isinstance(cost, dict) else None
        if number(value) is not None:
            total += float(value)
    return total


def same_path(left: object, right: Path) -> bool:
    if not isinstance(left, str) or not left:
        return False
    try:
        return Path(left).expanduser().resolve() == right
    except OSError:
        return False


def subagent_cost(async_root: Path, session_file: Path) -> tuple[float, int]:
    if not async_root.is_dir():
        return 0.0, 0

    total = 0.0
    runs = 0
    seen: set[str] = set()
    for status_path in sorted(async_root.glob("*/status.json")):
        try:
            status = json.loads(status_path.read_text(encoding="utf-8"))
        except (OSError, json.JSONDecodeError):
            continue
        if not isinstance(status, dict) or not same_path(status.get("sessionId"), session_file):
            continue
        run_id = status.get("runId")
        key = run_id if isinstance(run_id, str) and run_id else str(status_path)
        if key in seen:
            continue
        seen.add(key)
        cost = status.get("totalCost")
        value = cost.get("costUsd") if isinstance(cost, dict) else None
        if number(value) is None:
            continue
        total += float(value)
        runs += 1
    return total, runs


def default_async_root() -> Path:
    configured = os.environ.get("PI_SUBAGENT_ASYNC_ROOT")
    if configured:
        return Path(configured).expanduser().resolve()
    return (Path(tempfile.gettempdir()) / f"pi-subagents-uid-{os.getuid()}" / "async-subagent-runs").resolve()


def orchestrator_name(arguments: argparse.Namespace) -> str:
    if arguments.orchestrator:
        return arguments.orchestrator
    model = arguments.model or os.environ.get("PI_MODEL")
    level = arguments.reasoning_level or os.environ.get("PI_REASONING_LEVEL") or os.environ.get("PI_THINKING_LEVEL")
    if not model or not level:
        fail(2, "pi_orchestrator_name_missing -- pass --orchestrator <model>-<reasoning_level>/pi or set PI_MODEL and PI_REASONING_LEVEL")
    model = model.rsplit("/", 1)[-1]
    return f"{model}-{level}/pi"


def parse_cost(value: str) -> float | str:
    if value.upper() == "N/A":
        return "N/A"
    try:
        cost = float(value.lstrip("$"))
    except ValueError:
        fail(2, f"orchestrator_cost_not_a_number:{value}")
    if cost < 0:
        fail(2, "orchestrator_cost_negative")
    return cost


def main() -> None:
    parser = argparse.ArgumentParser(description="Write orchestrator.json from Pi session and subagent usage.")
    parser.add_argument("result_dir", help="campaign result directory, relative to the repository root or absolute")
    parser.add_argument("--orchestrator", help="display name, e.g. gpt-5.6-luna-high/pi")
    parser.add_argument("--model", help="Pi model used by the orchestrator; defaults to PI_MODEL")
    parser.add_argument("--reasoning-level", help="Pi reasoning level; defaults to PI_REASONING_LEVEL")
    parser.add_argument("--session-file", help="parent Pi session JSONL; defaults to PI_SESSION_FILE")
    parser.add_argument("--async-root", help="pi-subagents async run root; defaults to PI_SUBAGENT_ASYNC_ROOT or Pi's uid-scoped temp root")
    parser.add_argument("--cost-usd", help="write an explicit numeric cost or N/A instead of discovering Pi usage")
    parser.add_argument("--dry-run", action="store_true", help="report the value without writing orchestrator.json")
    arguments = parser.parse_args()

    result_dir = Path(arguments.result_dir).expanduser()
    if not result_dir.is_absolute():
        result_dir = ROOT / result_dir
    result_dir = result_dir.resolve()
    if not result_dir.is_dir():
        fail(2, f"result_directory_not_found:{result_dir}")

    name = orchestrator_name(arguments)
    if arguments.cost_usd is not None:
        cost: float | str = parse_cost(arguments.cost_usd)
        parent_cost = None
        child_cost = None
        child_runs = None
    else:
        session_value = arguments.session_file or os.environ.get("PI_SESSION_FILE")
        if not session_value:
            fail(2, "pi_session_file_missing -- pass --session-file or set PI_SESSION_FILE")
        session_file = Path(session_value).expanduser().resolve()
        if not session_file.is_file():
            fail(2, f"pi_session_file_not_found:{session_file}")
        parent_cost = session_cost(session_file)
        child_cost, child_runs = subagent_cost(
            Path(arguments.async_root).expanduser().resolve() if arguments.async_root else default_async_root(),
            session_file,
        )
        cost = round(parent_cost + child_cost, 8)

    payload: dict[str, Any] = {"orchestrator": name, "cost_usd": cost}
    if not arguments.dry_run:
        write_json(result_dir / ORCHESTRATOR_FILE, payload)

    emit_json({
        "ok": True,
        "action": "dry-run" if arguments.dry_run else "write",
        "path": str(result_dir / ORCHESTRATOR_FILE),
        "orchestrator": name,
        "cost_usd": cost,
        **({"orchestrator_cost_usd": parent_cost, "subagent_cost_usd": child_cost, "subagent_runs": child_runs} if parent_cost is not None else {}),
    })


if __name__ == "__main__":
    main()
