from __future__ import annotations

import json
import os
import sys
import time

from common import ROOT, command, command_or_fail, emit_json, fail, read_host_pi_config, read_json, run_dir, require_command, utc_now, validate_frozen_rubric, validate_frozen_task, validate_model_identity, validate_run_id, write_json


def main() -> None:
    require_command("docker")
    if len(sys.argv) != 2:
        fail(2, "usage:launch-candidate_run_id")
    run_id = sys.argv[1]
    validate_run_id(run_id)
    run = run_dir(run_id)
    if not (run / "preflight.json").is_file():
        fail(4, "preflight_required")
    metadata = read_json(run / "run.json")
    # By this point `selected_model` in run.json is no longer a copy of
    # `requested_model`: preflight.py persisted it there only after pi's own
    # admission probe echoed back the provider/model it actually served, and
    # only when that matched what was requested (a mismatch fails preflight
    # outright, never reaching here). This comparison is therefore a genuine
    # check that run.json was not tampered with between preflight and launch,
    # not the tautology it was before.
    validate_model_identity(metadata["requested_model"], metadata["selected_model"])
    admission_path = run / "admission.json"
    if not admission_path.is_file():
        fail(4, "admission_required")
    admission = read_json(admission_path)
    if not admission.get("ok") or not admission.get("identity_verified") or admission.get("requested_model") != metadata["requested_model"] or admission.get("selected_model") != metadata["selected_model"] or admission.get("config_fingerprints") != metadata["pi"]["config_fingerprints"]:
        fail(4, "admission_mismatch")
    task_path = ROOT / "evals" / "tasks" / f"{metadata['task_id']}.json"
    validate_frozen_task(metadata, task_path)
    validate_frozen_rubric(metadata, ROOT / "evals" / "tasks" / "rubrics" / f"{metadata['task_id']}.md")
    model = metadata["selected_model"]
    pi_config = read_host_pi_config(provider=model["provider"])
    if pi_config["config_fingerprints"] != metadata["pi"]["config_fingerprints"]:
        fail(4, "pi_config_changed_since_admission")
    task = metadata["task_contract"]
    command_or_fail(
        [
            "docker", "exec", "-i", metadata["container"],
            "python3", "/usr/local/bin/nothingness-eval-candidate",
            "--detach",
            "--provider", model["provider"],
            "--model", model["model"],
            "--thinking", model["thinking"],
            "--prompt", task["prompt"],
            "--timeout-seconds", str(task["limits"]["timeout_seconds"]),
            "--run-id", run_id,
        ],
        5,
        "candidate_launch_failed",
        input=json.dumps({"pi_config": pi_config["pi_config"], "provider_env": pi_config["provider_env"]}),
    )
    ready = False
    for _ in range(100):
        check = command(["docker", "exec", metadata["container"], "python3", "-c", "from pathlib import Path; import stat; p=Path('/run/nothingness/judge-control.sock'); assert p.exists() and stat.S_ISSOCK(p.stat().st_mode); assert Path('/run/nothingness/progress.json').is_file()"], stdout=os.devnull, stderr=os.devnull)
        if check.returncode == 0:
            ready = True
            break
        time.sleep(0.1)
    if not ready:
        fail(5, "candidate_control_not_ready")
    result = {"ok": True, "run_id": run_id, "requested_model": metadata["requested_model"], "selected_model": model, "identity_verified": admission["identity_verified"], "timeout_seconds": task["limits"]["timeout_seconds"], "output_mode": "rpc-jsonl", "canonical_output": "/run/nothingness/candidate.jsonl", "lifecycle_output": "/run/nothingness/lifecycle.jsonl", "progress_output": "/run/nothingness/progress.json", "launched_at": utc_now()}
    write_json(run / "launch.json", result)
    emit_json(result)


if __name__ == "__main__":
    main()