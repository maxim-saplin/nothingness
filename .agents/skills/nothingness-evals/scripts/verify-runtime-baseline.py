from __future__ import annotations

import argparse
import json
import os
import subprocess
import tempfile
import time
import uuid
from pathlib import Path

from common import IMAGE_NAME, ROOT, command, command_or_fail, emit_json, fail, gate_fingerprint, passed_gate, record_gate_pass, require_command, write_json


FIXTURE = "5fc7e04"
# 300s, not 120s. The comment below has always said this budget exists for the
# cold first launch after an image build -- but 120s was not enough for one, so
# the gate failed on exactly the run it was written to survive, and the fix for
# a too-short wait was re-running the whole ten-minute gate. Polling stops the
# moment the desktop reports ready, so a warm launch pays none of this.
DESKTOP_READY_POLLS = 1200
DESKTOP_READY_INTERVAL = 0.25
DRIVER = "/workspace/.agents/skills/agent-emulator-debugging/scripts/drive.py"
TRACKS = tuple(f"/opt/nothingness/media/0{index}-undercover-{48 + index}.opus" for index in range(1, 4))


def container_run_command(name: str) -> list[str]:
    return [
        "docker", "run", "-d", "--rm", "--name", name,
        "--label", "nothingness.eval.runtime-baseline=true",
        "--cap-drop", "ALL", "--security-opt", "no-new-privileges=true",
        "--network", "none", IMAGE_NAME,
    ]


def drive_command(name: str, *arguments: str) -> list[str]:
    return ["docker", "exec", name, DRIVER, *arguments]


def drive(name: str, *arguments: str) -> dict[str, object]:
    result = command_or_fail(drive_command(name, *arguments), 4, f"runtime_drive_failed:{arguments[0]}", stdout=subprocess.PIPE, stderr=subprocess.PIPE)
    try:
        value = json.loads(result.stdout)
    except json.JSONDecodeError:
        fail(4, f"runtime_drive_invalid_json:{arguments[0]}")
    if not isinstance(value, dict):
        fail(4, f"runtime_drive_invalid_result:{arguments[0]}")
    return value


def wait_for_state(name: str, label: str, predicate: object, timeout: float = 30) -> dict[str, object]:
    deadline = time.monotonic() + timeout
    while time.monotonic() < deadline:
        result = command(drive_command(name, "inspect"), stdout=subprocess.PIPE, stderr=subprocess.DEVNULL)
        if result.returncode == 0:
            try:
                state = json.loads(result.stdout)
            except json.JSONDecodeError:
                state = None
            if isinstance(state, dict) and predicate(state):
                return state
        time.sleep(0.25)
    fail(4, f"runtime_state_timeout:{label}")
    raise AssertionError("unreachable")


def main() -> None:
    parser = argparse.ArgumentParser(description="Prove the real Linux app plays, seeks and renders, with no credentials and no network.")
    parser.add_argument("--force", action="store_true", help="re-verify even if this exact image/fixture/gate already passed")
    arguments = parser.parse_args()
    for executable in ("docker", "git", "tar"):
        require_command(executable)
    active = command(["docker", "ps", "--filter", "label=nothingness.eval=true", "--format", "{{.Names}}"], stdout=subprocess.PIPE)
    if active.stdout.strip():
        fail(2, "evaluator_container_already_running")
    image_id = command_or_fail(["docker", "image", "inspect", "--format", "{{.Id}}", IMAGE_NAME], 3, "image_not_available", stdout=subprocess.PIPE).stdout.strip()
    fingerprint = gate_fingerprint(image_id, FIXTURE, Path(__file__))
    if not arguments.force:
        previous = passed_gate("runtime-baseline", fingerprint)
        if previous is not None:
            emit_json({**previous["result"], "skipped": "unchanged_since_last_pass", "previously_passed_at": previous["passed_at"], "reverify_with": "--force"})
            return
    name = f"nothingness-eval-runtime-{uuid.uuid4().hex[:12]}"
    artifacts = ROOT / ".tmp" / "evals" / name
    artifacts.mkdir(parents=True)
    states: dict[str, object] = {}
    try:
        with tempfile.TemporaryDirectory(prefix="nothingness-eval-runtime.", dir=ROOT / ".tmp") as temporary:
            seed = Path(temporary) / "workspace"
            seed.mkdir()
            archive = command_or_fail(["git", "archive", FIXTURE], 3, "fixture_archive_failed", stdout=subprocess.PIPE, text=False).stdout
            command_or_fail(["tar", "-x", "-C", str(seed)], 3, "fixture_extract_failed", input=archive, text=False)
            command_or_fail(["chmod", "-R", "a+rwX", str(seed)], 3, "fixture_permissions_failed")
            command_or_fail(container_run_command(name), 3, "runtime_container_start_failed", stdout=os.devnull)
            command_or_fail(["docker", "cp", f"{seed}/.", f"{name}:/workspace"], 3, "runtime_workspace_copy_failed", stdout=os.devnull)
            ready = False
            # Warm, the desktop is up in well under 10s; the very first launch
            # after an image build, against a cold page cache, takes far longer
            # -- budget for the slow machine rather than fail the run that
            # follows every rebuild. A partially-written health.json is a normal
            # race here, not a failure: keep polling instead of dying on it.
            #
            # Every failed poll is recorded rather than discarded. Swallowing
            # stderr made "the container died" and "the desktop is slow" produce
            # the same bare timeout, which sent the last two investigations
            # after a nonexistent race -- the budget was raised twice for a
            # symptom nobody had evidence of.
            last_error = ""
            for _ in range(DESKTOP_READY_POLLS):
                health = command(["docker", "exec", name, "cat", "/run/nothingness/health.json"], stdout=subprocess.PIPE, stderr=subprocess.PIPE)
                if health.returncode == 0:
                    try:
                        status = json.loads(health.stdout).get("status")
                    except json.JSONDecodeError:
                        last_error = f"unparsable_health_json:{health.stdout.strip()[:80]}"
                    else:
                        ready = status == "ready"
                        if not ready:
                            last_error = f"status={status}"
                else:
                    last_error = (health.stderr or "").strip().splitlines()[-1][:120] if (health.stderr or "").strip() else f"exec_exit={health.returncode}"
                if ready:
                    break
                time.sleep(DESKTOP_READY_INTERVAL)
            if not ready:
                state = command(["docker", "inspect", "--format", "{{.State.Status}} exit={{.State.ExitCode}} oom={{.State.OOMKilled}}", name], stdout=subprocess.PIPE, stderr=subprocess.DEVNULL)
                container = state.stdout.strip() if state.returncode == 0 else "gone (removed by --rm after exiting)"
                waited = round(DESKTOP_READY_POLLS * DESKTOP_READY_INTERVAL)
                fail(4, f"runtime_desktop_not_ready:waited_{waited}s container={container} last={last_error or 'no probe ever answered'} -- if the container is gone or OOM-killed the desktop never started, so raising the wait will not help; check host memory and `docker logs`")
            command_or_fail(["docker", "exec", name, "sh", "-c", "cd /workspace && flutter pub get --offline >/tmp/runtime-pub.log"], 4, "runtime_pub_failed")
            launch = """set -eu
home=/tmp/nothingness-runtime-baseline
mkdir -p "$home/.config" "$home/.local/share"
rm -f /tmp/flutter_input /tmp/flutter_run.log /tmp/drive_vm_ws.txt
mkfifo /tmp/flutter_input
nohup sh -c 'sleep infinity' > /tmp/flutter_input 2>/dev/null &
nohup env HOME="$home" XDG_CONFIG_HOME="$home/.config" XDG_DATA_HOME="$home/.local/share" flutter run -d linux --no-pub --debug -t dev/main_debug.dart < /tmp/flutter_input > /tmp/flutter_run.log 2>&1 &
echo $! > /tmp/flutter_pid
"""
            command_or_fail(["docker", "exec", name, "sh", "-c", launch], 4, "runtime_flutter_launch_failed")
            states["ready"] = wait_for_state(name, "ready", lambda state: "playback" in state, timeout=180)
            drive(name, "call", "ext.nothingness.setQueue", f"paths={','.join(TRACKS)}", "startIndex=0")
            drive(name, "resume")
            states["play"] = wait_for_state(name, "play", lambda state: state["playback"]["isPlaying"] and state["playback"]["currentIndex"] == 0)
            drive(name, "pause")
            states["pause"] = wait_for_state(name, "pause", lambda state: not state["playback"]["isPlaying"] and state["playback"]["currentIndex"] == 0)
            drive(name, "next")
            states["skip"] = wait_for_state(name, "skip", lambda state: state["playback"]["isPlaying"] and state["playback"]["currentIndex"] == 1)
            drive(name, "seek", "0:30")
            states["seek"] = wait_for_state(name, "seek", lambda state: 30_000 <= state["playback"]["songInfo"]["position"] < 40_000)
            drive(name, "next")
            states["final"] = wait_for_state(name, "final", lambda state: state["playback"]["isPlaying"] and state["playback"]["currentIndex"] == 2 and state["playback"]["spectrumNonZero"])
            playback = states["final"]["playback"]
            if tuple(track["path"] for track in playback["queue"]) != TRACKS or any(track["isNotFound"] for track in playback["queue"]):
                fail(4, "runtime_immutable_queue_mismatch")
            if states["final"]["overflows"]["count"] != 0:
                fail(4, "runtime_layout_overflow")
            drive(name, "shoot", "runtime_baseline")
            command_or_fail(["docker", "cp", f"{name}:/workspace/.tmp/agent_shots/runtime_baseline.png", str(artifacts / "runtime_baseline.png")], 4, "runtime_screenshot_copy_failed", stdout=os.devnull)
    finally:
        command(["docker", "cp", f"{name}:/tmp/flutter_run.log", str(artifacts / "flutter_run.log")], stdout=os.devnull, stderr=os.devnull)
        command(["docker", "rm", "-f", name], stdout=os.devnull, stderr=os.devnull)
    if command(["docker", "container", "inspect", name], stdout=os.devnull, stderr=os.devnull).returncode == 0:
        fail(4, "runtime_container_cleanup_failed")
    result = {"ok": True, "network": "none", "credentials": "not_loaded", "candidate": "not_launched", "fixture_commit": FIXTURE, "image": {"name": IMAGE_NAME, "immutable_id": image_id}, "tracks": TRACKS, "states": states, "artifacts": str(artifacts.relative_to(ROOT)), "cleanup": "passed"}
    write_json(artifacts / "result.json", result)
    record_gate_pass("runtime-baseline", fingerprint, result)
    emit_json(result)


if __name__ == "__main__":
    main()