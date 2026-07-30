from __future__ import annotations

import argparse
import hashlib
import os
import shutil
import subprocess
import sys
from pathlib import Path

from common import IMAGE_NAME, ROOT, command, command_or_fail, container_name, derive_provider_egress_host, emit_json, fail, load_suite, network_name, proxy_name, read_host_pi_config, read_json, resolve_pi, run_dir, require_command, sha256, task_scoring, utc_now, validate_model_identity, validate_pi_model, validate_run_id, write_json


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("task_id")
    parser.add_argument("run_id")
    parser.add_argument("--suite", required=True, type=Path)
    parser.add_argument("--trial", required=True, type=int)
    parser.add_argument("--calibration", action="store_true")
    arguments = parser.parse_args()
    for executable in ("docker", "git", "curl"):
        require_command(executable)
    task_id, run_id = arguments.task_id, arguments.run_id
    validate_run_id(run_id)
    suite_path = arguments.suite.resolve()
    suite = load_suite(suite_path)
    suite_task = next((item for item in suite["tasks"] if item["id"] == task_id), None)
    if suite_task is None or arguments.trial < 1 or (not arguments.calibration and arguments.trial > suite_task["valid_trials"]):
        fail(2, "invalid_suite_trial")
    if not run_id.startswith(f"{suite['id']}-"):
        fail(2, "run_id_suite_mismatch")
    task_path = ROOT / "evals" / "tasks" / f"{task_id}.json"
    if not task_path.is_file():
        fail(2, f"task_not_found:{task_id}")
    task = read_json(task_path)
    fixture = task["fixture_commit"]
    scoring = task_scoring(task)
    if fixture != "5fc7e04":
        fail(2, "unexpected_fixture_commit")
    pi = resolve_pi()
    requested_model = dict(suite["requested_model"])
    selected_model = requested_model.copy()
    validate_model_identity(requested_model, selected_model)
    validate_pi_model(pi["payload"], requested_model)
    pi_config = read_host_pi_config(provider=requested_model["provider"])
    egress_host = derive_provider_egress_host(pi_config["pi_config"]["models"], requested_model["provider"], pi_config["provider_env"])
    command_or_fail(["git", "cat-file", "-e", f"{fixture}^{{commit}}"], 3, "fixture_commit_unavailable")
    command_or_fail([sys.executable, str(Path(__file__).with_name("validate-opus-fixtures.py"))], 3, "opus_fixture_validation_failed", stdout=os.devnull)
    run = run_dir(run_id)
    container = container_name(run_id)
    proxy = proxy_name(run_id)
    network = network_name(run_id)
    if run.exists():
        fail(2, f"run_already_exists:{run}")
    if command(["docker", "container", "inspect", container], stdout=os.devnull, stderr=os.devnull).returncode == 0:
        fail(2, f"container_already_exists:{container}")
    if command(["docker", "container", "inspect", proxy], stdout=os.devnull, stderr=os.devnull).returncode == 0:
        fail(2, f"proxy_already_exists:{proxy}")
    image_id = command_or_fail(["docker", "image", "inspect", "--format", "{{.Id}}", IMAGE_NAME], 3, "image_not_available", stdout=subprocess.PIPE).stdout.strip()
    if not image_id:
        fail(3, "image_id_missing")
    (run / "seed").mkdir(parents=True)
    write_json(run / "interventions.json", [])
    result = {
        "schema_version": 2,
        "run_id": run_id,
        "suite_id": suite["id"],
        "suite_manifest_sha256": sha256(suite_path),
        "trial": arguments.trial,
        "calibration": arguments.calibration,
        "planned_valid_trials": suite_task["valid_trials"],
        "task_id": task_id,
        "task_contract": {"id": task["id"], "manifest_sha256": hashlib.sha256(task_path.read_bytes()).hexdigest(), "prompt": task["prompt"], "limits": task["limits"], "platform_variant": task["platform_variant"]},
        "fixture_commit": fixture,
        "container": container,
        "proxy": proxy,
        "network": network,
        "image": {"name": IMAGE_NAME, "immutable_id": image_id},
        "pi": {"version": pi["version"], "config_fingerprints": pi_config["config_fingerprints"]},
        "requested_model": requested_model,
        "selected_model": selected_model,
        "egress_host": egress_host,
        "network_policy": task["network"],
        "scoring": scoring,
        "prepared_at": utc_now(),
    }
    write_json(run / "run.json", result)
    archive = command_or_fail(["git", "archive", fixture], 3, "fixture_archive_failed", stdout=subprocess.PIPE, text=False).stdout
    command_or_fail(["tar", "-x", "-C", str(run / "seed")], 3, "fixture_extract_failed", input=archive, text=False)
    seed = run / "seed"
    for arguments in (("init", "-q"), ("config", "user.name", "Nothingness Evaluator"), ("config", "user.email", "evaluator@invalid"), ("add", "-A"), ("commit", "-qm", "fixture baseline")):
        command_or_fail(["git", *arguments], 3, "fixture_baseline_failed", cwd=seed)
    command_or_fail(["chmod", "-R", "a+rwX", str(seed)], 3, "fixture_permissions_failed")
    checksum = command_or_fail(["cksum"], 3, "checksum_failed", input=run_id, stdout=subprocess.PIPE).stdout.split()[0]
    port = 20000 + int(checksum) % 20000
    while command(["curl", "--silent", "--output", os.devnull, f"http://127.0.0.1:{port}/"]).returncode == 0:
        port += 1
    command_or_fail(["docker", "network", "create", "--internal", "--label", "nothingness.eval=true", "--label", f"nothingness.eval.run_id={run_id}", network], 3, "network_create_failed", stdout=os.devnull)
    proxy_args = ["docker", "run", "-d", "--name", proxy, "--label", "nothingness.eval=true", "--label", f"nothingness.eval.run_id={run_id}", "--cap-drop", "ALL", "--security-opt", "no-new-privileges=true", "--network", network, "-p", f"127.0.0.1:{port}:6080", "--entrypoint", "python3", IMAGE_NAME, "/usr/local/bin/nothingness-eval-proxy", "--novnc-host", container]
    proxy_args.extend(["--allow-host", egress_host])
    command_or_fail(proxy_args, 3, "proxy_start_failed", stdout=os.devnull)
    command_or_fail(["docker", "network", "connect", "bridge", proxy], 3, "proxy_bridge_attach_failed")
    docker_args = ["docker", "run", "-d", "--name", container, "--label", "nothingness.eval=true", "--label", f"nothingness.eval.run_id={run_id}", "--cap-drop", "ALL", "--security-opt", "no-new-privileges=true", "--network", network, "--cpus", str(task["limits"]["cpus"]), "--memory", task["limits"]["memory"], "--pids-limit", str(task["limits"]["pids_limit"]), "-e", f"HTTP_PROXY=http://{proxy}:3128", "-e", f"HTTPS_PROXY=http://{proxy}:3128", "-e", "NO_PROXY=localhost,127.0.0.1"]
    command_or_fail([*docker_args, IMAGE_NAME], 3, "container_start_failed", stdout=os.devnull)
    command_or_fail(["docker", "cp", f"{seed}/.", f"{container}:/workspace"], 3, "workspace_copy_failed")
    command_or_fail(["docker", "exec", container, "git", "config", "--global", "--add", "safe.directory", "/workspace"], 3, "workspace_git_trust_failed")
    setup = "from pathlib import Path; Path('/run/nothingness/sessions').mkdir()"
    command_or_fail(["docker", "exec", container, "python3", "-c", setup], 3, "container_setup_failed")
    command_or_fail(["docker", "exec", container, "git", "-C", "/workspace", "status", "--porcelain"], 3, "container_setup_failed", stdout=os.devnull)
    result["novnc_url"] = f"http://127.0.0.1:{port}/vnc.html?autoconnect=true&resize=scale"
    write_json(run / "run.json", result)
    emit_json(result)


if __name__ == "__main__":
    main()