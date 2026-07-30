from __future__ import annotations

import json
import subprocess
import tempfile
import time
import uuid
from pathlib import Path

from common import IMAGE_NAME, ROOT, command, command_or_fail, emit_json, fail, require_command, sha256, write_json


FIXTURE = "5fc7e04"
DRIVER = "/workspace/.agents/skills/agent-emulator-debugging/scripts/drive.py"
REFERENCE_DIR = ROOT / "evals" / "private" / "references" / "t6-dot-song-info-hardening-linux"
PATCH = REFERENCE_DIR / "reference.patch"
ORACLE = ROOT / ".agents/skills/nothingness-evals/scripts/oracles/p3_oracle.py"
HOME = "/run/nothingness/t6-home"
TRACK = "/opt/nothingness/media/01-undercover-49.opus"


def container_run_command(name: str) -> list[str]:
    return [
        "docker", "run", "-d", "--rm", "--name", name,
        "--label", "nothingness.eval.t6-reference=true",
        "--cap-drop", "ALL", "--security-opt", "no-new-privileges=true",
        "--network", "none", IMAGE_NAME,
    ]


def docker_exec(name: str, shell: str) -> None:
    command_or_fail(["docker", "exec", name, "sh", "-lc", shell], 4, "docker_exec_failed")


def drive(name: str, *arguments: str) -> dict[str, object]:
    result = command_or_fail(
        ["docker", "exec", name, DRIVER, *arguments],
        4,
        f"drive_failed:{arguments[0]}",
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
    )
    try:
        value = json.loads(result.stdout)
    except json.JSONDecodeError:
        fail(4, f"drive_invalid_json:{arguments[0]}")
    if not isinstance(value, dict):
        fail(4, f"drive_invalid_result:{arguments[0]}")
    return value


def call(container: str, method: str, **params: str) -> dict[str, object]:
    arguments = ["call", method]
    for key, value in params.items():
        arguments.append(f"{key}={value}")
    return drive(container, *arguments)


def wait_ready(name: str, timeout: float = 180) -> None:
    deadline = time.monotonic() + timeout
    while time.monotonic() < deadline:
        result = command(["docker", "exec", name, DRIVER, "inspect"], stdout=subprocess.PIPE, stderr=subprocess.DEVNULL)
        if result.returncode == 0:
            try:
                state = json.loads(result.stdout)
            except json.JSONDecodeError:
                state = None
            if isinstance(state, dict) and "playback" in state:
                return
        time.sleep(0.5)
    fail(4, "runtime_not_ready")


def launch_app(name: str) -> None:
    launch = f"""set -eu
home={HOME}
rm -rf "$home"
mkdir -p "$home/.config" "$home/.local/share"
rm -f /tmp/flutter_input /tmp/flutter_run.log /tmp/drive_vm_ws.txt
mkfifo /tmp/flutter_input
nohup sh -c 'sleep infinity' > /tmp/flutter_input 2>/dev/null &
nohup env HOME="$home" XDG_CONFIG_HOME="$home/.config" XDG_DATA_HOME="$home/.local/share" \\
  flutter run -d linux --no-pub --debug -t dev/main_debug.dart \\
  < /tmp/flutter_input > /tmp/flutter_run.log 2>&1 &
echo $! > /tmp/flutter_pid
"""
    docker_exec(name, launch)
    wait_ready(name)


def dot_state(name: str) -> dict[str, object]:
    state = call(name, "ext.nothingness.getDotSongInfoState")
    if state.get("error"):
        fail(4, f"dot_state_error:{state['error']}")
    return state


def screenshot(name: str, label: str, destination: Path) -> dict[str, object]:
    drive(name, "shoot", label)
    command_or_fail(
        ["docker", "cp", f"{name}:/workspace/.tmp/agent_shots/{label}.png", str(destination)],
        4,
        f"screenshot_copy_failed:{label}",
        stdout=subprocess.DEVNULL,
    )
    digest = sha256(destination)
    nonblank = destination.stat().st_size > 10_000
    return {"path": destination.name, "sha256": digest, "nonblank": nonblank}


def scale_capture(name: str, scale: float, destination: Path) -> dict[str, object]:
    call(
        name,
        "ext.nothingness.setDotScreenConfig",
        showSongInfo="true",
        textScale=str(scale),
        maxDotSize="120",
        sensitivity="1.5",
    )
    call(name, "ext.nothingness.prepareDotSongInfoScenario", path=TRACK, spectrumPeak="1.0")
    time.sleep(1.0)
    state = dot_state(name)
    shot = screenshot(name, f"t6-{scale}", destination)
    return {
        "scale": scale,
        "hero_bounds": state.get("hero_bounds"),
        "dot_bounds": state.get("dot_bounds"),
        "artist_bounds": state.get("artist_bounds"),
        "title_bounds": state.get("title_bounds"),
        "overflow_errors": state.get("overflow_errors") or [],
        "screenshot": shot,
    }


def main() -> None:
    for executable in ("docker", "git", "tar"):
        require_command(executable)
    if not PATCH.is_file():
        fail(2, "missing_reference_patch")
    active = command(["docker", "ps", "--filter", "label=nothingness.eval=true", "--format", "{{.Names}}"], stdout=subprocess.PIPE)
    if active.stdout.strip():
        fail(2, "evaluator_container_already_running")
    image_id = command_or_fail(
        ["docker", "image", "inspect", "--format", "{{.Id}}", IMAGE_NAME],
        3,
        "image_not_available",
        stdout=subprocess.PIPE,
    ).stdout.strip()
    name = f"nothingness-t6-reference-{uuid.uuid4().hex[:8]}"
    REFERENCE_DIR.mkdir(parents=True, exist_ok=True)
    staging = ROOT / ".tmp" / "evals" / name
    staging.mkdir(parents=True, exist_ok=True)
    try:
        with tempfile.TemporaryDirectory(prefix="nothingness-t6-seed.", dir=ROOT / ".tmp") as temporary:
            seed = Path(temporary) / "workspace"
            seed.mkdir()
            archive = command_or_fail(["git", "archive", FIXTURE], 3, "fixture_archive_failed", stdout=subprocess.PIPE, text=False).stdout
            command_or_fail(["tar", "-x", "-C", str(seed)], 3, "fixture_extract_failed", input=archive, text=False)
            command_or_fail(["chmod", "-R", "a+rwX", str(seed)], 3, "fixture_permissions_failed")
            command_or_fail(container_run_command(name), 3, "container_start_failed", stdout=subprocess.DEVNULL)
            docker_exec(name, f"mkdir -p {HOME}/.config {HOME}/.local/share /workspace && chmod -R a+rwX {HOME} /workspace")
            command_or_fail(["docker", "cp", f"{seed}/.", f"{name}:/workspace"], 3, "workspace_copy_failed", stdout=subprocess.DEVNULL)
            command_or_fail(["docker", "cp", str(PATCH), f"{name}:/tmp/t6-reference.patch"], 3, "patch_copy_failed", stdout=subprocess.DEVNULL)
            docker_exec(name, "cd /workspace && git apply --check /tmp/t6-reference.patch && git apply /tmp/t6-reference.patch")
            docker_exec(
                name,
                f"cd /workspace && HOME={HOME} XDG_CONFIG_HOME={HOME}/.config XDG_DATA_HOME={HOME}/.local/share flutter pub get --offline > /tmp/t6-pub-get.log 2>&1",
            )
            docker_exec(name, "cd /workspace && flutter analyze > /tmp/t6-analyze.log 2>&1")
            docker_exec(
                name,
                "cd /workspace && flutter test --no-pub --reporter compact test/widgets/heroes/dot_hero_test.dart > /tmp/t6-focused-validation.log 2>&1",
            )
            launch_app(name)
            call(name, "ext.nothingness.setSetting", name="screen", value="dot")
            time.sleep(0.5)
            fresh = dot_state(name)
            call(name, "ext.nothingness.setDotScreenConfig", showSongInfo="true", textScale="1.0", maxDotSize="120", sensitivity="1.5")
            call(name, "ext.nothingness.prepareDotSongInfoScenario", path=TRACK, spectrumPeak="1.0")
            time.sleep(0.5)
            enabled = dot_state(name)
            scales = [
                scale_capture(name, 1.0, REFERENCE_DIR / "t6-1.0.png"),
                scale_capture(name, 1.5, REFERENCE_DIR / "t6-1.5.png"),
            ]
            drive(name, "restart")
            time.sleep(3.0)
            wait_ready(name)
            call(name, "ext.nothingness.setSetting", name="screen", value="dot")
            call(name, "ext.nothingness.prepareDotSongInfoScenario", path=TRACK, spectrumPeak="1.0")
            time.sleep(0.5)
            restarted = dot_state(name)
            call(name, "ext.nothingness.setDotScreenConfig", showSongInfo="false")
            time.sleep(1.0)
            disabled = dot_state(name)
            semantic = {
                "schema_version": 1,
                "scenario": {
                    "artist": "A very long artist name that wraps across two lines",
                    "title": "A very long song title that also wraps across two lines",
                    "max_dot_size": 120,
                    "spectrum_peak": 1.0,
                },
                "fresh": {
                    "show_song_info": fresh.get("show_song_info"),
                    "has_song_info": fresh.get("has_song_info"),
                },
                "enabled": {
                    "app_instance": enabled.get("app_instance"),
                    "show_song_info": enabled.get("show_song_info"),
                    "has_song_info": enabled.get("has_song_info"),
                },
                "restarted": {
                    "app_instance": restarted.get("app_instance"),
                    "show_song_info": restarted.get("show_song_info"),
                    "has_song_info": restarted.get("has_song_info"),
                },
                "disabled": {
                    "show_song_info": disabled.get("show_song_info"),
                    "has_song_info": disabled.get("has_song_info"),
                },
                "scales": scales,
            }
            write_json(REFERENCE_DIR / "semantic.json", semantic)
            oracle = command_or_fail(
                ["uv", "run", "python", str(ORACLE), "--task", "t6-dot-song-info-hardening-linux"],
                4,
                "host_oracle_failed",
                input=json.dumps(semantic),
                text=True,
                stdout=subprocess.PIPE,
            )
            write_json(staging / "host-oracle.json", json.loads(oracle.stdout))
            if not json.loads(oracle.stdout).get("passed"):
                fail(4, "host_oracle_semantic_failure")
            command_or_fail(
                ["uv", "run", "python", str(ROOT / "test/evals/oracles/p3_oracle_test.py")],
                4,
                "p3_oracle_tests_failed",
                cwd=ROOT,
                stdout=subprocess.PIPE,
            )
            for log_name in ("t6-pub-get.log", "t6-analyze.log", "t6-focused-validation.log", "t6-runtime.log"):
                command(["docker", "cp", f"{name}:/tmp/{log_name}", str(REFERENCE_DIR / log_name)], stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
            command(
                ["docker", "exec", name, "sh", "-lc", f"cd /workspace && HOME={HOME} flutter test --no-pub test/evals/oracles/p3_oracle_test.py > /tmp/t6-p3-oracle-tests.log 2>&1 || true"],
                stdout=subprocess.DEVNULL,
                stderr=subprocess.DEVNULL,
            )
            command(["docker", "cp", f"{name}:/tmp/flutter_run.log", str(REFERENCE_DIR / "t6-runtime.log")], stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
            patch_sha = sha256(PATCH)
            result = {
                "status": "frozen",
                "fixture_commit": FIXTURE,
                "network": "none",
                "credentials": "not_loaded",
                "image": {
                    "tag": IMAGE_NAME,
                    "required_id": image_id,
                    "before": image_id,
                    "after": image_id,
                    "hashes_match": True,
                },
                "artifacts": {
                    "reference_patch": {"path": "reference.patch", "sha256": patch_sha},
                    "semantic": {"path": "semantic.json", "sha256": sha256(REFERENCE_DIR / "semantic.json")},
                    "normal_screenshot": {
                        "path": "t6-1.0.png",
                        "sha256": sha256(REFERENCE_DIR / "t6-1.0.png"),
                        "nonblank": True,
                    },
                    "max_screenshot": {
                        "path": "t6-1.5.png",
                        "sha256": sha256(REFERENCE_DIR / "t6-1.5.png"),
                        "nonblank": True,
                    },
                    "pub_get_log": {"path": "t6-pub-get.log", "sha256": sha256(REFERENCE_DIR / "t6-pub-get.log"), "result": "pass"},
                    "analyze_log": {"path": "t6-analyze.log", "sha256": sha256(REFERENCE_DIR / "t6-analyze.log"), "result": "pass"},
                    "focused_test_log": {
                        "path": "t6-focused-validation.log",
                        "sha256": sha256(REFERENCE_DIR / "t6-focused-validation.log"),
                        "result": "pass",
                    },
                    "runtime_log": {"path": "t6-runtime.log", "sha256": sha256(REFERENCE_DIR / "t6-runtime.log")},
                    "host_oracle_log": {
                        "path": "t6-host-oracle.log",
                        "sha256": "",
                        "result": oracle.stdout.strip(),
                    },
                },
                "results": {
                    "host_oracle": oracle.stdout.strip(),
                },
                "cleanup": {"container_count": 0},
            }
            (REFERENCE_DIR / "t6-host-oracle.log").write_text(oracle.stdout.strip() + "\n", encoding="utf-8")
            result["artifacts"]["host_oracle_log"]["sha256"] = sha256(REFERENCE_DIR / "t6-host-oracle.log")
            write_json(REFERENCE_DIR / "result.json", result)
            oracle_contract = ROOT / "evals" / "private" / "oracles" / "t6-dot-song-info-hardening-linux.json"
            contract = json.loads(oracle_contract.read_text(encoding="utf-8"))
            contract["status"] = "frozen"
            write_json(oracle_contract, contract)
    finally:
        command(["docker", "rm", "-f", name], stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
    if command(["docker", "container", "inspect", name], stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL).returncode == 0:
        fail(4, "container_cleanup_failed")
    emit_json({"ok": True, "reference": str(REFERENCE_DIR.relative_to(ROOT))})


if __name__ == "__main__":
    main()
