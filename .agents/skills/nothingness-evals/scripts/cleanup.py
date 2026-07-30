from __future__ import annotations

import os
import subprocess
import sys
import time
from pathlib import Path

from common import SCRIPT_DIR, append_jsonl, command, emit_json, fail, read_json, run_dir, require_command, utc_now, validate_run_id, write_json


def remove_container(name: str) -> bool:
    present = command(["docker", "container", "inspect", name], stdout=os.devnull, stderr=os.devnull).returncode == 0
    if present and command(["docker", "rm", "-f", name], stdout=os.devnull, stderr=os.devnull).returncode:
        fail(4, "container_cleanup_failed")
    return present


def termination_event(run: Path, event: str, **values: object) -> None:
    append_jsonl(run / "termination.jsonl", {"timestamp": utc_now(), "event": event, **values})


def terminate_candidate(run: Path, name: str) -> tuple[bool, bool]:
    present = command(["docker", "container", "inspect", name], stdout=os.devnull, stderr=os.devnull).returncode == 0
    termination_event(run, "termination_requested", container=name, present=present)
    if not present:
        return False, False
    termination_event(run, "supervisor_abort_requested", container=name)
    abort = command(
        ["docker", "exec", "-i", name, "python3", "/usr/local/bin/nothingness-eval-candidate", "--control"],
        input='{"control":"abort","reason":"cleanup_requested"}',
        stdout=subprocess.PIPE,
        stderr=subprocess.DEVNULL,
    )
    termination_event(run, "supervisor_abort_result", container=name, delivered=abort.returncode == 0, returncode=abort.returncode)
    completion = False
    for _ in range(50):
        completion = command(["docker", "exec", name, "test", "-f", "/run/nothingness/candidate-completion.json"], stdout=os.devnull, stderr=os.devnull).returncode == 0
        if completion:
            break
        time.sleep(0.1)
    termination_event(run, "completion_check", container=name, completion_recorded=completion)
    termination_event(run, "artifact_collection_requested", container=name)
    collection = command([sys.executable, str(SCRIPT_DIR / "collect.py"), run.name], stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
    termination_event(run, "artifact_collection_result", container=name, collected=collection.returncode == 0, returncode=collection.returncode)
    termination_event(run, "force_removal_requested", container=name)
    removal = command(["docker", "rm", "-f", name], stdout=os.devnull, stderr=os.devnull)
    termination_event(run, "force_removal_result", container=name, removed=removal.returncode == 0, returncode=removal.returncode)
    absent = command(["docker", "container", "inspect", name], stdout=os.devnull, stderr=os.devnull).returncode != 0
    termination_event(run, "termination_verified", container=name, absent=absent)
    if removal.returncode or not absent:
        fail(4, "container_cleanup_failed")
    return True, completion


def remove_network(name: str) -> bool:
    present = command(["docker", "network", "inspect", name], stdout=os.devnull, stderr=os.devnull).returncode == 0
    if present and command(["docker", "network", "rm", name], stdout=os.devnull, stderr=os.devnull).returncode:
        fail(4, "network_cleanup_failed")
    return present


def main() -> None:
    require_command("docker")
    if len(sys.argv) != 2:
        fail(2, "usage:cleanup_run_id")
    run_id = sys.argv[1]
    validate_run_id(run_id)
    run = run_dir(run_id)
    if not (run / "run.json").is_file():
        fail(3, "run_not_prepared")
    metadata = read_json(run / "run.json")
    candidate_removed, completion_recorded = terminate_candidate(run, metadata["container"]) if "container" in metadata else (False, False)
    proxy_removed = remove_container(metadata["proxy"]) if "proxy" in metadata else False
    network_removed = remove_network(metadata["network"]) if "network" in metadata else False
    result = {"ok": True, "run_id": run_id, "container_removed": candidate_removed, "candidate_completion_recorded": completion_recorded, "proxy_removed": proxy_removed, "network_removed": network_removed, "termination_journal": str(run / "termination.jsonl"), "staging": str(run)}
    write_json(run / "cleanup.json", result)
    emit_json(result)


if __name__ == "__main__":
    main()