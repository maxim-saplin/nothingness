from __future__ import annotations

import json
import os
import sys

from common import command, emit_json, fail, read_json, run_dir, require_command, validate_run_id, write_json


def main() -> None:
    for executable in ("docker", "curl"):
        require_command(executable)
    if len(sys.argv) != 2:
        fail(2, "usage:observe_run_id")
    run_id = sys.argv[1]
    validate_run_id(run_id)
    run = run_dir(run_id)
    if not (run / "run.json").is_file():
        fail(3, "run_not_prepared")
    metadata = read_json(run / "run.json")
    health = command(["docker", "exec", metadata["container"], "cat", "/run/nothingness/health.json"], stdout=-1)
    if health.returncode:
        fail(4, "health_unavailable")
    if command(["curl", "--fail", "--silent", "--output", os.devnull, metadata["novnc_url"]]).returncode:
        fail(4, "novnc_unreachable")
    running = command(["docker", "exec", metadata["container"], "pgrep", "-f", "nothingness-eval-candidate"], stdout=os.devnull, stderr=os.devnull).returncode == 0
    completion = command(["docker", "exec", metadata["container"], "cat", "/run/nothingness/candidate-completion.json"], stdout=-1, stderr=os.devnull)
    result = {"run_id": run_id, "novnc_url": metadata["novnc_url"], "health": json.loads(health.stdout), "candidate_running": running, "candidate_completion": json.loads(completion.stdout) if completion.returncode == 0 else None}
    write_json(run / "observe.json", result)
    emit_json(result)


if __name__ == "__main__":
    main()