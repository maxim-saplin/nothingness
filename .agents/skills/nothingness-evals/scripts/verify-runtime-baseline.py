from __future__ import annotations

import argparse
import json
import os
import subprocess
import time
import uuid
from pathlib import Path

from common import IMAGE_NAME, ROOT, command, command_or_fail, copy_git_archive_into_container, emit_json, fail, gate_fingerprint, passed_gate, record_gate_pass, require_command, wait_for_desktop_ready, write_json


FIXTURE = "5fc7e04"
DRIVER = "/workspace/.agents/skills/agent-emulator-debugging/scripts/drive.py"
TRACKS = tuple(f"/opt/nothingness/media/0{index}-undercover-{48 + index}.opus" for index in range(1, 4))
DRIVE_ENV = (
    "-e", "DRIVE_TARGET=linux",
    "-e", "DRIVE_RUN_LOG=/run/nothingness/drive/flutter_run.log",
    "-e", "DRIVE_FLUTTER_FIFO=/run/nothingness/drive/flutter_input",
    "-e", "DRIVE_WS_CACHE=/run/nothingness/drive/vm_ws.txt",
)
# Cold debug `flutter run` on arm64 after a fresh image build can exceed three
# minutes before extensions answer; offline `flutter build linux` does not warm
# this path because it is a separate disposable container.
APP_READY_TIMEOUT = 360


def container_run_command(name: str) -> list[str]:
    return [
        "docker", "run", "-d", "--name", name,
        "--label", "nothingness.eval.runtime-baseline=true",
        "--cap-drop", "ALL", "--security-opt", "no-new-privileges=true",
        "--network", "none", IMAGE_NAME,
    ]


def drive_command(name: str, *arguments: str) -> list[str]:
    return ["docker", "exec", *DRIVE_ENV, name, DRIVER, *arguments]


def drive(name: str, *arguments: str) -> dict[str, object]:
    result = command_or_fail(drive_command(name, *arguments), 4, f"runtime_drive_failed:{arguments[0]}", stdout=subprocess.PIPE, stderr=subprocess.PIPE)
    try:
        value = json.loads(result.stdout)
    except json.JSONDecodeError:
        fail(4, f"runtime_drive_invalid_json:{arguments[0]}")
    if not isinstance(value, dict):
        fail(4, f"runtime_drive_invalid_result:{arguments[0]}")
    return value


# 30s was too tight for a cold desktop start under load: the gate failed with
# runtime_state_timeout:ready and passed on retry with nothing changed.
def wait_for_state(name: str, label: str, predicate: object, timeout: float = 120) -> dict[str, object]:
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
        command_or_fail(container_run_command(name), 3, "runtime_container_start_failed", stdout=os.devnull)
        copy_git_archive_into_container(name, FIXTURE)
        wait_for_desktop_ready(name, label="runtime_desktop_not_ready")
        command_or_fail(["docker", "exec", name, "sh", "-c", "cd /workspace && flutter pub get --offline >/tmp/runtime-pub.log"], 4, "runtime_pub_failed")
        launch = """set -eu
rm -f /run/nothingness/drive/flutter_input /run/nothingness/drive/flutter_run.log /run/nothingness/drive/vm_ws.txt
mkfifo /run/nothingness/drive/flutter_input
nohup sh -c 'sleep infinity' > /run/nothingness/drive/flutter_input 2>/dev/null &
nohup env HOME=/run/nothingness/home XDG_CONFIG_HOME=/run/nothingness/config XDG_DATA_HOME=/run/nothingness/data flutter run -d linux --no-pub --debug -t dev/main_debug.dart < /run/nothingness/drive/flutter_input > /run/nothingness/drive/flutter_run.log 2>&1 &
echo $! > /tmp/flutter_pid
"""
        command_or_fail(["docker", "exec", name, "sh", "-c", launch], 4, "runtime_flutter_launch_failed")
        states["ready"] = wait_for_state(name, "ready", lambda state: "playback" in state, timeout=APP_READY_TIMEOUT)
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
        command(["docker", "cp", f"{name}:/run/nothingness/drive/flutter_run.log", str(artifacts / "flutter_run.log")], stdout=os.devnull, stderr=os.devnull)
        command(["docker", "rm", "-f", name], stdout=os.devnull, stderr=os.devnull)
    if command(["docker", "container", "inspect", name], stdout=os.devnull, stderr=subprocess.DEVNULL).returncode == 0:
        fail(4, "runtime_container_cleanup_failed")
    result = {"ok": True, "network": "none", "credentials": "not_loaded", "candidate": "not_launched", "fixture_commit": FIXTURE, "image": {"name": IMAGE_NAME, "immutable_id": image_id}, "tracks": TRACKS, "states": states, "artifacts": str(artifacts.relative_to(ROOT)), "cleanup": "passed"}
    write_json(artifacts / "result.json", result)
    record_gate_pass("runtime-baseline", fingerprint, result)
    emit_json(result)


if __name__ == "__main__":
    main()
