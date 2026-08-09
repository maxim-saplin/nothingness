from __future__ import annotations

import argparse
import hashlib
import json
import subprocess
import uuid
from typing import Any

from common import append_jsonl, command, emit_json, fail, read_host_pi_config, read_json, redact_value, run_dir, secret_values, utc_now, validate_run_id, write_json


def bounded(value: Any, limit: int = 8_000) -> Any:
    if isinstance(value, str):
        return value[:limit]
    if isinstance(value, list):
        return [bounded(item, limit) for item in value]
    if isinstance(value, dict):
        return {key: bounded(item, limit) for key, item in value.items()}
    return value


def relevant(event: dict[str, Any]) -> dict[str, Any]:
    event_type = event.get("type")
    fields = {"type": event_type}
    for name in ("id", "command", "success", "toolName", "toolCallId", "args", "result", "isError", "message", "usage", "stopReason", "error", "data"):
        if name in event:
            fields[name] = bounded(event[name])
    return fields


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("run_id")
    parser.add_argument("--after", type=int, default=0)
    # 100 forced every real supervision session into needless paging (the skill
    # had to tell judges to pass --limit 2500 every time); default to the value
    # the documented workflow actually wants.
    parser.add_argument("--limit", type=int, default=2500)
    arguments = parser.parse_args()
    validate_run_id(arguments.run_id)
    run = run_dir(arguments.run_id)
    metadata = read_json(run / "run.json")
    pi_config = read_host_pi_config(provider=metadata["selected_model"]["provider"])
    if pi_config["config_fingerprints"] != metadata["pi"]["config_fingerprints"]:
        fail(4, "pi_config_changed_during_judge_review")
    secrets = secret_values(pi_config["pi_config"], pi_config["provider_env"])
    result = command(["docker", "exec", metadata["container"], "cat", "/run/nothingness/lifecycle.jsonl"], stdout=subprocess.PIPE, stderr=subprocess.DEVNULL)
    if result.returncode:
        fail(4, "candidate_lifecycle_unavailable")
    events = []
    last_sequence = arguments.after
    expected_sequence = arguments.after + 1
    for raw in result.stdout.splitlines():
        try:
            record = json.loads(raw)
        except json.JSONDecodeError:
            continue
        sequence = record.get("sequence")
        if not isinstance(sequence, int) or sequence <= arguments.after:
            continue
        if sequence != expected_sequence:
            fail(4, "candidate_lifecycle_sequence_gap")
        last_sequence = sequence
        expected_sequence += 1
        events.append(redact_value({"sequence": sequence, "timestamp": record.get("timestamp"), "elapsed_seconds": record.get("elapsed_seconds"), "source": record.get("source"), "event": relevant(record.get("event", {}))}, secrets))
        if len(events) >= arguments.limit:
            break
    observation_id = f"events-{uuid.uuid4().hex}"
    batch = {"schema_version": 1, "observation_id": observation_id, "run_id": arguments.run_id, "after": arguments.after, "next_sequence": last_sequence, "events": events}
    batch_path = run / "judge-event-reads" / f"{observation_id}.json"
    write_json(batch_path, batch)
    digest = hashlib.sha256(batch_path.read_bytes()).hexdigest()
    append_jsonl(run / "judge-observations.jsonl", {"observation_id": observation_id, "timestamp": utc_now(), "kind": "events", "after": arguments.after, "next_sequence": last_sequence, "event_count": len(events), "event_types": [item["event"].get("type") for item in events], "evidence": str(batch_path.relative_to(run)), "sha256": digest})
    # Echo the observation id: `decide` requires it, and withholding it here
    # forced every judge to go re-read judge-observations.jsonl to recover an
    # value that was in scope all along.
    emit_json({"ok": True, "run_id": arguments.run_id, "observation_id": observation_id, "after": arguments.after, "next_sequence": last_sequence, "events": events})


if __name__ == "__main__":
    main()