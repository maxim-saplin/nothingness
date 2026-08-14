from __future__ import annotations

import argparse
import json
import subprocess
import uuid

from common import command, emit_json, exclusive_lock, fail, read_host_pi_config, read_json, redact_text, redact_value, run_dir, secret_values, utc_now, validate_run_id, write_json


INTERVENTION_CLASSES = ("clarification", "recovery", "verification_request", "correction", "implementation_guidance")
MAX_DELIVERED_INTERVENTIONS = 3


def send(container: str, payload: dict[str, object]) -> dict[str, object]:
    result = command(["docker", "exec", "-i", container, "python3", "/usr/local/bin/nothingness-eval-candidate", "--control"], input=json.dumps(payload), stdout=subprocess.PIPE, stderr=subprocess.PIPE)
    try:
        response = json.loads(result.stdout)
    except json.JSONDecodeError:
        fail(4, "judge_control_unavailable")
    if result.returncode or not response.get("ok"):
        fail(4, f"judge_control_failed:{response.get('reason', 'unknown')}")
    return response


def main(argv: list[str] | None = None) -> None:
    parser = argparse.ArgumentParser(allow_abbrev=False)
    parser.add_argument("run_id")
    subparsers = parser.add_subparsers(dest="action", required=True)
    for name in ("steer", "follow-up"):
        child = subparsers.add_parser(name, allow_abbrev=False)
        child.add_argument("--class", dest="classification", required=True, choices=INTERVENTION_CLASSES)
        child.add_argument("--message", required=True)
        child.add_argument("--reason", required=True)
    request = subparsers.add_parser("request", allow_abbrev=False)
    request.add_argument("kind", choices=("get_state", "get_messages", "get_entries", "get_session_stats"))
    finish = subparsers.add_parser("finish", allow_abbrev=False)
    finish.add_argument("--reason", required=True)
    abort = subparsers.add_parser("abort", allow_abbrev=False)
    abort.add_argument("--reason", required=True)
    arguments = parser.parse_args(argv)
    validate_run_id(arguments.run_id)
    run = run_dir(arguments.run_id)
    metadata = read_json(run / "run.json")
    pi_config = read_host_pi_config(provider=metadata["selected_model"]["provider"])
    if pi_config["config_fingerprints"] != metadata["pi"]["config_fingerprints"]:
        fail(4, "pi_config_changed_during_judge_control")
    secrets = secret_values(pi_config["pi_config"], pi_config["provider_env"])
    command_id = f"judge-{uuid.uuid4().hex[:12]}"
    if arguments.action in {"steer", "follow-up"}:
        rpc_type = "steer" if arguments.action == "steer" else "follow_up"
        interventions_path = run / "interventions.json"
        # The cap check and the append that records this delivery must be
        # atomic across concurrent `judge-control.py` processes, not just
        # within this one: an unlocked read-check-append-write here let two
        # concurrent `steer` calls both read a delivered count of 2, both pass
        # the `>= 3` check, and both actually reach the candidate (D5). Holding
        # this lock for the whole read-through-delivered-write sequence closes
        # that window; a second invocation blocks until the first has fully
        # recorded its own delivery outcome.
        with exclusive_lock(run / "interventions.lock"):
            interventions = read_json(interventions_path)
            if not isinstance(interventions, list):
                fail(3, "invalid_intervention_log")
            delivered_count = sum(1 for item in interventions if isinstance(item, dict) and item.get("delivery") == "delivered")
            if delivered_count >= MAX_DELIVERED_INTERVENTIONS:
                fail(6, "intervention_cap_exceeded")
            message = redact_text(arguments.message, secrets)
            reason = redact_text(arguments.reason, secrets)
            intervention = {"id": command_id, "timestamp": utc_now(), "classification": arguments.classification, "mode": rpc_type, "message": message, "reason": reason}
            interventions.append({**intervention, "delivery": "pending"})
            write_json(interventions_path, interventions)
            payload = {"control": "intervention", "intervention": intervention, "command": {"id": command_id, "type": rpc_type, "message": arguments.message}}
            try:
                response = send(metadata["container"], payload)
            except BaseException:
                interventions[-1]["delivery"] = "unknown"
                write_json(interventions_path, interventions)
                raise
            interventions[-1]["delivery"] = "delivered"
            write_json(interventions_path, interventions)
    elif arguments.action == "request":
        response = send(metadata["container"], {"control": "rpc", "command": {"id": command_id, "type": arguments.kind}})
    else:
        response = send(metadata["container"], {"control": arguments.action, "reason": redact_text(arguments.reason, secrets)})
    emit_json(redact_value({"ok": True, "run_id": arguments.run_id, "action": arguments.action, "command_id": command_id, "response": response}, secrets))


if __name__ == "__main__":
    main()