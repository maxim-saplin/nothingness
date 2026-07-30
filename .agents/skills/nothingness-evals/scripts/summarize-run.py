from __future__ import annotations

import json
import sys
from collections import Counter
from pathlib import Path
from typing import Any

from common import emit_json, fail, read_json, run_dir, validate_run_id, write_json
from usage import normalized_usage

MAX_FINAL_TEXT_CHARS = 8_000


def scalar(value: Any, *names: str) -> Any:
    if isinstance(value, dict):
        for name in names:
            if name in value and not isinstance(value[name], (dict, list)):
                return value[name]
        for nested in value.values():
            found = scalar(nested, *names)
            if found is not None:
                return found
    return None


def assistant_text(event: dict[str, Any]) -> str | None:
    message = event.get("message")
    if not isinstance(message, dict) or message.get("role") != "assistant":
        return None
    content = message.get("content")
    if not isinstance(content, list):
        return None
    texts = [item.get("text") for item in content if isinstance(item, dict) and item.get("type") == "text" and isinstance(item.get("text"), str)]
    if not texts:
        return None
    text = "\n".join(texts)
    return text[:MAX_FINAL_TEXT_CHARS]


def usage_for(event: dict[str, Any]) -> dict[str, Any] | None:
    message = event.get("message")
    if isinstance(message, dict) and isinstance(message.get("usage"), dict):
        return message["usage"]
    return event.get("usage") if isinstance(event.get("usage"), dict) else None


def add_usage(target: Counter[str], usage: dict[str, Any], prefix: str = "") -> None:
    for name, value in usage.items():
        key = f"{prefix}.{name}" if prefix else name
        if isinstance(value, (int, float)):
            target[key] += value
        elif isinstance(value, dict):
            add_usage(target, value, key)


def summarize_jsonl(path: Path) -> dict[str, Any]:
    event_counts: Counter[str] = Counter()
    tool_executions = 0
    final_text = None
    final_stop_reason = None
    final_error = None
    final_usage = None
    aggregate_usage: Counter[str] = Counter()
    invalid_lines = 0

    with path.open(encoding="utf-8", errors="replace") as source:
        for raw in source:
            try:
                event = json.loads(raw)
            except json.JSONDecodeError:
                invalid_lines += 1
                continue
            if not isinstance(event, dict):
                invalid_lines += 1
                continue
            event_type = event.get("type")
            if isinstance(event_type, str):
                event_counts[event_type] += 1
            if event_type == "tool_execution_start":
                tool_executions += 1
            if event_type == "message_end":
                final_text = assistant_text(event) or final_text
            if event_type in {"turn_end", "agent_end"}:
                final_stop_reason = scalar(event, "stop_reason", "stopReason", "reason") or final_stop_reason
                final_error = scalar(event, "error") or final_error
            usage = usage_for(event)
            if usage is not None:
                final_usage = usage
            if event_type == "turn_end" and usage is not None:
                add_usage(aggregate_usage, usage)

    return {
        "canonical_jsonl_bytes": path.stat().st_size,
        "event_counts": dict(sorted(event_counts.items())),
        "tool_executions": tool_executions,
        "invalid_jsonl_lines": invalid_lines,
        "final_assistant_text": final_text,
        "final_stop_reason": final_stop_reason,
        "final_error": final_error,
        "usage": {"aggregate": normalized_usage(dict(aggregate_usage)), "final": normalized_usage(final_usage)},
    }


def main() -> None:
    if len(sys.argv) != 2:
        fail(2, "usage:summarize-run_run_id")
    run_id = sys.argv[1]
    validate_run_id(run_id)
    run = run_dir(run_id)
    if not (run / "run.json").is_file():
        fail(3, "run_not_prepared")
    artifacts = run / "artifacts"
    transcript = artifacts / "candidate.jsonl"
    if not transcript.is_file():
        fail(3, "candidate_output_missing")
    completion_path = artifacts / "candidate-completion.json"
    completion = read_json(completion_path) if completion_path.is_file() else None
    untracked_path = artifacts / "untracked.txt"
    untracked = untracked_path.read_text(encoding="utf-8", errors="replace").splitlines() if untracked_path.is_file() else []
    flutter_evidence = (artifacts / "flutter_run.log").is_file()
    interventions = read_json(run / "interventions.json") if (run / "interventions.json").is_file() else None
    admission = read_json(run / "admission.json") if (run / "admission.json").is_file() else None
    candidate = summarize_jsonl(transcript)
    admission_usage = normalized_usage(admission.get("usage") if isinstance(admission, dict) else None)
    candidate_cost = candidate["usage"]["aggregate"]["cost_usd"]["total"]
    admission_cost = admission_usage["cost_usd"]["total"]
    combined_cost = admission_cost + candidate_cost if isinstance(admission_cost, (int, float)) and isinstance(candidate_cost, (int, float)) else None
    summary = {
        "ok": True,
        "run_id": run_id,
        "requested_model": read_json(run / "run.json").get("requested_model"),
        "selected_model": read_json(run / "run.json").get("selected_model"),
        "model_identity_verified": read_json(run / "run.json").get("requested_model") == read_json(run / "run.json").get("selected_model"),
        "candidate_completion": completion,
        "git_status": (artifacts / "git-status.txt").read_text(encoding="utf-8", errors="replace") if (artifacts / "git-status.txt").is_file() else None,
        "untracked": untracked,
        "flutter_evidence_exists": flutter_evidence,
        "admission": {"result": admission, "usage": admission_usage},
        "candidate": candidate,
        "cost_usd": {"admission": admission_cost, "candidate": candidate_cost, "combined": combined_cost},
        "interventions": {"count": len(interventions) if isinstance(interventions, list) else None, "classifications": dict(Counter(item.get("classification", "unclassified") for item in interventions if isinstance(item, dict))) if isinstance(interventions, list) else None, "unassisted": interventions == []},
        "timing": {
            "prepared_at": read_json(run / "run.json").get("prepared_at"),
            "launched_at": read_json(run / "launch.json").get("launched_at") if (run / "launch.json").is_file() else None,
            "started_at_unix": completion.get("started_at_unix") if isinstance(completion, dict) else None,
            "finished_at_unix": completion.get("finished_at_unix") if isinstance(completion, dict) else None,
            "elapsed_seconds": completion.get("finished_at_unix") - completion.get("started_at_unix") if isinstance(completion, dict) and isinstance(completion.get("started_at_unix"), (int, float)) and isinstance(completion.get("finished_at_unix"), (int, float)) else None,
        },
    }
    write_json(run / "summary.json", summary)
    emit_json(summary)


if __name__ == "__main__":
    main()