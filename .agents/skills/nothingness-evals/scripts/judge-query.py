"""Ask questions about a run's event stream instead of streaming it.

`judge-events.py` is the *evidence* interface: it pages sequentially, returns
whole payloads, and appends to the observation ledger, because a decision has to
cite a hash-verified, contiguous chain. That makes it a bad tool for looking
around -- a long session is tens of thousands of events, sequence windows are
the only axis it offers, and every exploratory read pollutes the ledger with an
observation nobody intends to cite.

This is the read-only counterpart: filter by type, tool, source, error or
regex, aggregate with --group-by, and bound the output. It writes nothing, so
a judge can interrogate a session freely and still cite a clean evidence chain.

The log outlives the container by design -- `collect.py` archives
lifecycle.jsonl into artifacts/ -- so a finished or fully cleaned-up run stays
queryable with no session, terminal or multiplexer kept alive for it.
"""

from __future__ import annotations

import argparse
import json
import re
import subprocess
from collections import Counter
from pathlib import Path
from typing import Any

from common import command, emit_json, fail, read_host_pi_config, read_json, redact_value, run_dir, secret_values, validate_run_id

EXCERPT_CHARS = 220


def parse(text: str) -> list[dict[str, Any]]:
    records = []
    for line in text.splitlines():
        try:
            record = json.loads(line)
        except json.JSONDecodeError:
            continue
        if isinstance(record, dict) and isinstance(record.get("sequence"), int):
            records.append(record)
    return records


def load_records(run: Path, metadata: dict[str, Any]) -> tuple[list[dict[str, Any]], str]:
    live = command(["docker", "exec", metadata["container"], "cat", "/run/nothingness/lifecycle.jsonl"], stdout=subprocess.PIPE, stderr=subprocess.DEVNULL)
    if live.returncode == 0:
        return parse(live.stdout), "container"
    archived = run / "artifacts" / "lifecycle.jsonl"
    if archived.is_file():
        return parse(archived.read_text(encoding="utf-8", errors="replace")), "artifacts"
    fail(4, "lifecycle_unavailable -- container is gone and collect.py has not archived artifacts/lifecycle.jsonl")
    raise AssertionError("unreachable")


def event_of(record: dict[str, Any]) -> dict[str, Any]:
    event = record.get("event")
    return event if isinstance(event, dict) else {}


def tool_of(record: dict[str, Any]) -> str:
    event = event_of(record)
    return str(event.get("toolName") or event.get("name") or "")


def is_error(record: dict[str, Any]) -> bool:
    event = event_of(record)
    return bool(event.get("isError")) or event.get("success") is False or str(event.get("type") or "") in ("error", "retrying") or bool(event.get("error"))


def excerpt(record: dict[str, Any]) -> str:
    event = event_of(record)
    message = event.get("message") if isinstance(event.get("message"), dict) else None
    if message:
        for block in message.get("content", []) if isinstance(message.get("content"), list) else []:
            if isinstance(block, dict) and block.get("type") == "text" and block.get("text"):
                return " ".join(str(block["text"]).split())[:EXCERPT_CHARS]
    for name in ("args", "result", "error", "command"):
        if event.get(name):
            return " ".join(json.dumps(event[name], default=str).split())[:EXCERPT_CHARS]
    return ""


def main() -> None:
    parser = argparse.ArgumentParser(allow_abbrev=False, description="Read-only query over a run's event stream. Writes nothing; never appends to the observation ledger.")
    parser.add_argument("run_id")
    parser.add_argument("--type", action="append", default=[], help="event type, repeatable (e.g. tool_execution_start)")
    parser.add_argument("--tool", action="append", default=[], help="tool name, repeatable")
    parser.add_argument("--source", action="append", default=[], help="event source, repeatable (pi, judge_control, supervisor)")
    parser.add_argument("--grep", help="regex matched against the whole serialized event")
    parser.add_argument("--ignore-case", action="store_true")
    parser.add_argument("--errors", action="store_true", help="only failures, retries and error events")
    parser.add_argument("--after", type=int, default=0, help="exclusive lower sequence bound")
    parser.add_argument("--before", type=int, help="exclusive upper sequence bound")
    parser.add_argument("--group-by", choices=("type", "tool", "source"), help="aggregate counts instead of listing events")
    parser.add_argument("--format", choices=("lines", "json", "count"), default="lines")
    parser.add_argument("--limit", type=int, default=50, help="max events returned; use --tail to take the last ones instead of the first")
    parser.add_argument("--tail", action="store_true")
    arguments = parser.parse_args()
    validate_run_id(arguments.run_id)
    run = run_dir(arguments.run_id)
    if not (run / "run.json").is_file():
        fail(3, "run_not_prepared")
    metadata = read_json(run / "run.json")
    selected = metadata.get("selected_model") or metadata.get("requested_model") or {}
    pi_config = read_host_pi_config(provider=selected["provider"])
    secrets = secret_values(pi_config["pi_config"], pi_config["provider_env"])
    records, origin = load_records(run, metadata)
    total = len(records)

    pattern = re.compile(arguments.grep, re.IGNORECASE if arguments.ignore_case else 0) if arguments.grep else None
    matched = []
    for record in records:
        sequence = record["sequence"]
        if sequence <= arguments.after or (arguments.before is not None and sequence >= arguments.before):
            continue
        event = event_of(record)
        if arguments.type and str(event.get("type") or "") not in arguments.type:
            continue
        if arguments.tool and tool_of(record) not in arguments.tool:
            continue
        if arguments.source and str(record.get("source") or "") not in arguments.source:
            continue
        if arguments.errors and not is_error(record):
            continue
        if pattern and not pattern.search(json.dumps(record, default=str)):
            continue
        matched.append(record)

    if arguments.group_by:
        key = {"type": lambda item: str(event_of(item).get("type") or ""), "tool": tool_of, "source": lambda item: str(item.get("source") or "")}[arguments.group_by]
        counts = Counter(key(record) for record in matched if key(record))
        emit_json({"ok": True, "run_id": arguments.run_id, "origin": origin, "total_events": total, "matched": len(matched), "group_by": arguments.group_by, "counts": dict(counts.most_common())})
        return
    if arguments.format == "count":
        emit_json({"ok": True, "run_id": arguments.run_id, "origin": origin, "total_events": total, "matched": len(matched)})
        return

    window = matched[-arguments.limit:] if arguments.tail else matched[:arguments.limit]
    if arguments.format == "json":
        emit_json({"ok": True, "run_id": arguments.run_id, "origin": origin, "total_events": total, "matched": len(matched), "returned": len(window), "events": redact_value(window, secrets)})
        return
    lines = []
    for record in window:
        event = event_of(record)
        tool = tool_of(record)
        text = redact_value(excerpt(record), secrets)
        lines.append(f"[{record['sequence']}] {record.get('elapsed_seconds')}s {record.get('source')} {event.get('type')}{' ' + tool if tool else ''}{' | ' + text if text else ''}")
    emit_json({"ok": True, "run_id": arguments.run_id, "origin": origin, "total_events": total, "matched": len(matched), "returned": len(window), "lines": lines})


if __name__ == "__main__":
    main()
