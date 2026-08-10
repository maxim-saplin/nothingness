from __future__ import annotations

import argparse
import hashlib
import json
import os
import shutil
import subprocess
import sys
from pathlib import Path

from common import IMAGE_NAME, ROOT, command, command_or_fail, command_or_fail_chained, container_name, derive_provider_egress_host, emit_json, fail, load_suite, network_name, proxy_name, read_host_pi_config, read_json, resolve_pi, run_dir, require_command, sha256, task_scoring, utc_now, validate_image_matches_sources, validate_pi_model, validate_run_id, write_json


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("task_id")
    parser.add_argument("run_id")
    parser.add_argument("--suite", required=True, type=Path)
    parser.add_argument("--trial", required=True, type=int)
    parser.add_argument("--calibration", action="store_true")
    parser.add_argument("--judge", default="", help="who is scoring this run (model/agent id); recorded so two judges of the same candidate stay distinguishable")
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
    # F1: freeze the rubric's hash now, before the candidate ever sees the
    # prompt, mirroring task_contract.manifest_sha256 below. A task that
    # cannot be scored must not be launched — T3-T7 have no rubric yet
    # (WP7 writes them before the full campaign), so preparing a run for
    # those tasks correctly fails here rather than launching an unscoreable
    # trial.
    rubric_path = ROOT / "evals" / "tasks" / "rubrics" / f"{task_id}.md"
    if not rubric_path.is_file():
        fail(2, f"rubric_not_found:{task_id}")
    rubric_sha256 = sha256(rubric_path)
    pi = resolve_pi()
    requested_model = dict(suite["requested_model"])
    # `selected_model` (the model identity pi actually served) is not knowable
    # yet: nothing has called pi. It is only genuinely discoverable once
    # preflight's admission probe gets a real response back with pi's own
    # provider/model fields on it — preflight.py fills this in and persists it
    # here. A run classified before preflight ever ran (invalid_infrastructure)
    # correctly carries no selected_model at all: no evidence, no claim.
    selected_model = None
    validate_pi_model(pi, requested_model)
    pi_config = read_host_pi_config(provider=requested_model["provider"])
    egress_host = derive_provider_egress_host(pi_config["pi_config"]["models"], requested_model["provider"], pi_config["provider_env"])
    command_or_fail(["git", "cat-file", "-e", f"{fixture}^{{commit}}"], 3, "fixture_commit_unavailable")
    command_or_fail_chained([sys.executable, str(Path(__file__).with_name("validate-opus-fixtures.py"))], 3, "opus_fixture_validation_failed", stdout=os.devnull)
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
    image_inspect = command_or_fail(["docker", "image", "inspect", IMAGE_NAME], 3, "image_not_available", stdout=subprocess.PIPE).stdout
    try:
        image_info = json.loads(image_inspect)[0]
    except (ValueError, IndexError, TypeError):
        fail(3, "image_not_available")
    image_id = image_info.get("Id")
    if not image_id:
        fail(3, "image_id_missing")
    image_labels = image_info.get("Config", {}).get("Labels") or {}
    # The fix for "nothing detects a stale image": before this run touches a
    # single docker container or spends an admission token, refuse to proceed
    # if the image's baked-in source hash (set by `build-image.py`) no longer
    # matches `evals/image/` on disk right now. This is deliberately the
    # earliest possible gate -- prepare-run.py creates no containers yet and
    # preflight.py's admission probe hasn't run -- so a stale image fails
    # loudly for free, instead of silently running old candidate.py code and
    # surfacing as a confusing admission failure three steps later.
    image_source_sha256 = validate_image_matches_sources(image_labels)
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
        "rubric_contract": {"manifest_sha256": rubric_sha256},
        "fixture_commit": fixture,
        "container": container,
        "proxy": proxy,
        "network": network,
        "image": {"name": IMAGE_NAME, "immutable_id": image_id, "source_sha256": image_source_sha256},
        "pi": {"version": pi["version"], "config_fingerprints": pi_config["config_fingerprints"]},
        "judge": arguments.judge,
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
    while command(["curl", "--silent", "--connect-timeout", "2", "--max-time", "2", "--output", os.devnull, f"http://127.0.0.1:{port}/"]).returncode == 0:
        port += 1
    command_or_fail(["docker", "network", "create", "--internal", "--label", "nothingness.eval=true", "--label", f"nothingness.eval.run_id={run_id}", network], 3, "network_create_failed", stdout=os.devnull)
    # Attach order is load-bearing, not stylistic. Docker wires a published port's
    # DNAT at creation time, to the address the container has on the network it is
    # created on -- an `--internal` network's address is not routable from the host,
    # and connecting `bridge` afterwards does not rewire the mapping. Creating the
    # proxy on the internal network first therefore publishes a port that accepts
    # connections and never answers, failing every run at preflight's noVNC probe.
    # The end state is identical either way (proxy on both networks, candidate on
    # the internal one only), so this costs no isolation.
    proxy_args = ["docker", "run", "-d", "--name", proxy, "--label", "nothingness.eval=true", "--label", f"nothingness.eval.run_id={run_id}", "--cap-drop", "ALL", "--security-opt", "no-new-privileges=true", "--network", "bridge", "-p", f"127.0.0.1:{port}:6080", "--entrypoint", "python3", IMAGE_NAME, "/usr/local/bin/nothingness-eval-proxy", "--novnc-host", container]
    proxy_args.extend(["--allow-host", egress_host])
    command_or_fail(proxy_args, 3, "proxy_start_failed", stdout=os.devnull)
    command_or_fail(["docker", "network", "connect", network, proxy], 3, "proxy_internal_attach_failed")
    docker_args = ["docker", "run", "-d", "--name", container, "--label", "nothingness.eval=true", "--label", f"nothingness.eval.run_id={run_id}", "--cap-drop", "ALL", "--security-opt", "no-new-privileges=true", "--network", network, "--cpus", str(task["limits"]["cpus"]), "--memory", task["limits"]["memory"], "--pids-limit", str(task["limits"]["pids_limit"]), "-e", f"HTTP_PROXY=http://{proxy}:3128", "-e", f"HTTPS_PROXY=http://{proxy}:3128", "-e", "NO_PROXY=localhost,127.0.0.1"]
    command_or_fail([*docker_args, IMAGE_NAME], 3, "container_start_failed", stdout=os.devnull)
    command_or_fail(["docker", "cp", f"{seed}/.", f"{container}:/workspace"], 3, "workspace_copy_failed")
    command_or_fail(["docker", "exec", container, "git", "config", "--global", "--add", "safe.directory", "/workspace"], 3, "workspace_git_trust_failed")
    # Resolve dependencies before the candidate ever sees the workspace. The
    # container is offline by design, `drive.py preflight` hands out a launch
    # recipe ending in a bare `flutter run`, and that command cannot work here --
    # it resolves against pub.dev and dies on the egress allowlist. Leaving that
    # in place tests whether a model can guess `--offline`, not whether it can
    # drive the app. `.dart_tool/`, `build/` and `pubspec.lock` are all
    # gitignored in the fixture, so priming leaves the candidate's diff clean.
    command_or_fail(["docker", "exec", container, "sh", "-c", "cd /workspace && flutter pub get --offline >/tmp/prepare-pub.log 2>&1"], 3, "workspace_pub_get_failed")
    # Fold what pub get regenerated into the baseline, so the candidate starts from
    # a clean tree. Flutter rewrites tracked files here (the linux plugin registrant
    # and cmake, and the macos registrant), and leaving them uncommitted would both
    # trip preflight's cleanliness check and charge the candidate for a diff it did
    # not make -- which is exactly the exception the T1 rubric has had to carve out.
    command_or_fail(["docker", "exec", container, "sh", "-c", "cd /workspace && git add -A && git commit -qm 'primed dependencies' --allow-empty"], 3, "workspace_baseline_commit_failed")
    setup = "from pathlib import Path; Path('/run/nothingness/sessions').mkdir()"
    command_or_fail(["docker", "exec", container, "python3", "-c", setup], 3, "container_setup_failed")
    command_or_fail(["docker", "exec", container, "git", "-C", "/workspace", "status", "--porcelain"], 3, "container_setup_failed", stdout=os.devnull)
    result["novnc_url"] = f"http://127.0.0.1:{port}/vnc.html?autoconnect=true&resize=scale"
    write_json(run / "run.json", result)
    emit_json(result)


if __name__ == "__main__":
    main()