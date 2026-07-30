from __future__ import annotations

import argparse
import hashlib
import json
import subprocess
import uuid

from common import append_jsonl, command, emit_json, fail, read_host_pi_config, read_json, redact_value, run_dir, secret_values, utc_now, validate_run_id, write_json


def decoded(result: subprocess.CompletedProcess[str]) -> object:
    if result.returncode:
        return {"available": False}
    try:
        return json.loads(result.stdout)
    except json.JSONDecodeError:
        return {"available": True, "output": result.stdout[:16_000]}


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("run_id")
    parser.add_argument("--runtime", action="store_true")
    parser.add_argument("--git", action="store_true")
    parser.add_argument("--processes", action="store_true")
    arguments = parser.parse_args()
    validate_run_id(arguments.run_id)
    run = run_dir(arguments.run_id)
    metadata = read_json(run / "run.json")
    pi_config = read_host_pi_config(provider=metadata["selected_model"]["provider"])
    if pi_config["config_fingerprints"] != metadata["pi"]["config_fingerprints"]:
        fail(4, "pi_config_changed_during_judge_review")
    secrets = secret_values(pi_config["pi_config"], pi_config["provider_env"])
    container = metadata["container"]
    result: dict[str, object] = {"ok": True, "run_id": arguments.run_id, "novnc_url": metadata.get("novnc_url")}
    if arguments.runtime:
        inspection = command(["docker", "exec", container, "python3", "/workspace/.agents/skills/agent-emulator-debugging/scripts/drive.py", "inspect"], stdout=subprocess.PIPE, stderr=subprocess.DEVNULL)
        result["runtime"] = decoded(inspection)
    if arguments.git:
        status = command(["docker", "exec", container, "git", "-C", "/workspace", "status", "--short"], stdout=subprocess.PIPE, stderr=subprocess.DEVNULL)
        diff = command(["docker", "exec", container, "git", "-C", "/workspace", "diff", "--stat"], stdout=subprocess.PIPE, stderr=subprocess.DEVNULL)
        result["git"] = {"available": status.returncode == 0 and diff.returncode == 0, "status": status.stdout.splitlines()[:200], "diff_stat": diff.stdout.splitlines()[:200]}
    if arguments.processes:
        processes = command(["docker", "top", container, "-eo", "pid,ppid,stat,etime,comm"], stdout=subprocess.PIPE, stderr=subprocess.DEVNULL)
        result["processes"] = {"available": processes.returncode == 0, "snapshot": processes.stdout.splitlines()[:200]}
    if not any((arguments.runtime, arguments.git, arguments.processes)):
        fail(2, "inspection_scope_required")
    result = redact_value(result, secrets)
    observation_id = f"inspection-{uuid.uuid4().hex}"
    result["observation_id"] = observation_id
    snapshot_path = run / "judge-inspections" / f"{observation_id}.json"
    write_json(snapshot_path, result)
    digest = hashlib.sha256(snapshot_path.read_bytes()).hexdigest()
    append_jsonl(run / "judge-observations.jsonl", {"observation_id": observation_id, "timestamp": utc_now(), "kind": "inspection", "runtime": arguments.runtime, "git": arguments.git, "processes": arguments.processes, "availability": {name: value.get("available") if isinstance(value, dict) else None for name, value in result.items() if name in {"runtime", "git", "processes"}}, "evidence": str(snapshot_path.relative_to(run)), "sha256": digest})
    emit_json(result)


if __name__ == "__main__":
    main()