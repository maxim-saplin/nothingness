from __future__ import annotations

import json
import subprocess
import tempfile
import time
import uuid
from pathlib import Path

from common import IMAGE_NAME, ROOT, command, command_or_fail, emit_json, fail, read_json, require_command, sha256, write_json


FIXTURE = "5fc7e04"
DRIVER = "/workspace/.agents/skills/agent-emulator-debugging/scripts/drive.py"
REFERENCE_DIR = ROOT / "evals" / "private" / "references" / "t7-opus-shuffled-playlist-linux"
PATCH = REFERENCE_DIR / "reference.patch"
ORACLE = ROOT / ".agents/skills/nothingness-evals/scripts/oracles/p3_oracle.py"
MANIFEST = ROOT / "evals" / "assets" / "opus" / "manifest.json"
HOME = "/run/nothingness/t7-home"
CONTAINER_MEDIA = "/opt/nothingness/media"


def container_paths() -> list[str]:
    return [f"{CONTAINER_MEDIA}/{Path(item['path']).name}" for item in read_json(MANIFEST)]


def container_run_command(name: str) -> list[str]:
    return [
        "docker", "run", "-d", "--rm", "--name", name,
        "--label", "nothingness.eval.t7-reference=true",
        "--cap-drop", "ALL", "--security-opt", "no-new-privileges=true",
        "--network", "none", IMAGE_NAME,
    ]


def docker_exec(name: str, shell: str) -> None:
    command_or_fail(["docker", "exec", name, "sh", "-lc", shell], 4, "docker_exec_failed")


def drive(container: str, *arguments: str) -> dict[str, object]:
    result = command_or_fail(
        ["docker", "exec", container, DRIVER, *arguments],
        4,
        f"drive_failed:{arguments[0]}",
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
    )
    return json.loads(result.stdout)


def call(container: str, method: str, **params: str) -> dict[str, object]:
    arguments = ["call", method]
    for key, value in params.items():
        arguments.append(f"{key}={value}")
    return drive(container, *arguments)


def wait_ready(container: str, timeout: float = 180) -> None:
    deadline = time.monotonic() + timeout
    while time.monotonic() < deadline:
        result = command(["docker", "exec", container, DRIVER, "inspect"], stdout=subprocess.PIPE, stderr=subprocess.DEVNULL)
        if result.returncode == 0:
            state = json.loads(result.stdout)
            if isinstance(state, dict) and "playback" in state:
                return
        time.sleep(0.5)
    fail(4, "runtime_not_ready")


def launch_app(container: str) -> None:
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
    docker_exec(container, launch)
    wait_ready(container)


def playback_state(container: str) -> dict[str, object]:
    return drive(container, "inspect")["playback"]


def build_inventory() -> list[dict[str, object]]:
    command_or_fail(["uv", "run", "python", str(ROOT / ".agents/skills/nothingness-evals/scripts/validate-opus-fixtures.py")], 3, "opus_fixture_validation_failed")
    return [
        {
            "path": f"{CONTAINER_MEDIA}/{Path(item['path']).name}",
            "sha256": item["sha256"],
            "codec": "opus",
            "full_decode": True,
        }
        for item in read_json(MANIFEST)
    ]


def main() -> None:
    for executable in ("docker", "git", "tar"):
        require_command(executable)
    if not PATCH.is_file():
        fail(2, "missing_reference_patch")
    paths = container_paths()
    if len(paths) != 10:
        fail(2, "invalid_opus_fixture_count")
    image_id = command_or_fail(
        ["docker", "image", "inspect", "--format", "{{.Id}}", IMAGE_NAME],
        3,
        "image_not_available",
        stdout=subprocess.PIPE,
    ).stdout.strip()
    name = f"nothingness-t7-reference-{uuid.uuid4().hex[:8]}"
    REFERENCE_DIR.mkdir(parents=True, exist_ok=True)
    inventory = build_inventory()
    try:
        with tempfile.TemporaryDirectory(prefix="nothingness-t7-seed.", dir=ROOT / ".tmp") as temporary:
            seed = Path(temporary) / "workspace"
            seed.mkdir()
            archive = command_or_fail(["git", "archive", FIXTURE], 3, "fixture_archive_failed", stdout=subprocess.PIPE, text=False).stdout
            command_or_fail(["tar", "-x", "-C", str(seed)], 3, "fixture_extract_failed", input=archive, text=False)
            command_or_fail(["chmod", "-R", "a+rwX", str(seed)], 3, "fixture_permissions_failed")
            command_or_fail(container_run_command(name), 3, "container_start_failed", stdout=subprocess.DEVNULL)
            docker_exec(name, f"mkdir -p {HOME}/.config {HOME}/.local/share /workspace && chmod -R a+rwX {HOME} /workspace")
            command_or_fail(["docker", "cp", f"{seed}/.", f"{name}:/workspace"], 3, "workspace_copy_failed", stdout=subprocess.DEVNULL)
            command_or_fail(["docker", "cp", str(PATCH), f"{name}:/tmp/t7-reference.patch"], 3, "patch_copy_failed", stdout=subprocess.DEVNULL)
            docker_exec(name, "cd /workspace && git apply --check /tmp/t7-reference.patch && git apply /tmp/t7-reference.patch")
            docker_exec(name, "cd /workspace && flutter pub get --offline > /tmp/t7-pub-get.log 2>&1")
            docker_exec(name, "cd /workspace && flutter analyze > /tmp/t7-analyze.log 2>&1")
            launch_app(name)
            call(name, "ext.nothingness.setQueue", paths=",".join(paths), startIndex="0", shuffle="true")
            drive(name, "resume")
            deadline = time.monotonic() + 30
            pre = playback_state(name)
            while time.monotonic() < deadline and not pre.get("isPlaying"):
                time.sleep(0.5)
                pre = playback_state(name)
            if not pre.get("isPlaying"):
                fail(4, "playback_not_started")
            action = drive(name, "next")
            time.sleep(1.0)
            post = playback_state(name)
            queue = [
                {"path": item.get("path"), "is_not_found": item.get("isNotFound", False)}
                for item in pre.get("queue", [])
                if isinstance(item, dict)
            ]
            semantic = {
                "schema_version": 1,
                "inventory": inventory,
                "queue": queue,
                "pre": {
                    "shuffle": pre.get("shuffle"),
                    "is_playing": pre.get("isPlaying"),
                    "current_index": pre.get("currentIndex"),
                    "current_path": (pre.get("songInfo") or {}).get("path"),
                },
                "action": {"type": "next", "succeeded": action.get("ok") is True},
                "post": {
                    "shuffle": post.get("shuffle"),
                    "is_playing": post.get("isPlaying"),
                    "current_index": post.get("currentIndex"),
                    "current_path": (post.get("songInfo") or {}).get("path"),
                },
            }
            write_json(REFERENCE_DIR / "semantic.json", semantic)
            oracle = command_or_fail(
                ["uv", "run", "python", str(ORACLE), "--task", "t7-opus-shuffled-playlist-linux"],
                4,
                "host_oracle_failed",
                input=json.dumps(semantic),
                text=True,
                stdout=subprocess.PIPE,
            )
            if not json.loads(oracle.stdout).get("passed"):
                fail(4, "host_oracle_semantic_failure")
            command_or_fail(
                ["uv", "run", "python", str(ROOT / "test/evals/oracles/p3_oracle_test.py")],
                4,
                "p3_oracle_tests_failed",
                cwd=ROOT,
                stdout=subprocess.PIPE,
            )
            for log_name in ("t7-pub-get.log", "t7-analyze.log"):
                command(["docker", "cp", f"{name}:/tmp/{log_name}", str(REFERENCE_DIR / log_name)], stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
            command(["docker", "cp", f"{name}:/tmp/flutter_run.log", str(REFERENCE_DIR / "t7-runtime.log")], stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
            (REFERENCE_DIR / "t7-host-oracle.log").write_text(oracle.stdout.strip() + "\n", encoding="utf-8")
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
                    "reference_patch": {"path": "reference.patch", "sha256": sha256(PATCH)},
                    "semantic": {"path": "semantic.json", "sha256": sha256(REFERENCE_DIR / "semantic.json")},
                    "pub_get_log": {"path": "t7-pub-get.log", "sha256": sha256(REFERENCE_DIR / "t7-pub-get.log"), "result": "pass"},
                    "analyze_log": {"path": "t7-analyze.log", "sha256": sha256(REFERENCE_DIR / "t7-analyze.log"), "result": "pass"},
                    "runtime_log": {"path": "t7-runtime.log", "sha256": sha256(REFERENCE_DIR / "t7-runtime.log")},
                    "host_oracle_log": {
                        "path": "t7-host-oracle.log",
                        "sha256": sha256(REFERENCE_DIR / "t7-host-oracle.log"),
                        "result": oracle.stdout.strip(),
                    },
                },
                "results": {"host_oracle": oracle.stdout.strip()},
                "cleanup": {"container_count": 0},
            }
            write_json(REFERENCE_DIR / "result.json", result)
            contract = read_json(ROOT / "evals/private/oracles/t7-opus-shuffled-playlist-linux.json")
            contract["status"] = "frozen"
            write_json(ROOT / "evals/private/oracles/t7-opus-shuffled-playlist-linux.json", contract)
    finally:
        command(["docker", "rm", "-f", name], stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
    if command(["docker", "container", "inspect", name], stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL).returncode == 0:
        fail(4, "container_cleanup_failed")
    emit_json({"ok": True, "reference": str(REFERENCE_DIR.relative_to(ROOT))})


if __name__ == "__main__":
    main()
