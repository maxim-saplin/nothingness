from __future__ import annotations

import argparse
import os
import subprocess
import sys
import tempfile
import uuid
from pathlib import Path

from common import IMAGE_NAME, ROOT, command, command_or_fail, emit_json, fail, require_command


FIXTURE = "5fc7e04"


def container_run_command(name: str) -> list[str]:
    return [
        "docker", "run", "-d", "--rm", "--name", name,
        "--label", "nothingness.eval.baseline=true",
        "--cap-drop", "ALL", "--security-opt", "no-new-privileges=true",
        "--network", "none", "--entrypoint", "sleep", IMAGE_NAME, "infinity",
    ]


def baseline_checks(name: str) -> tuple[tuple[str, list[str]], ...]:
    return (
        ("exec", ["docker", "exec", name, "true"]),
        ("python", ["docker", "exec", name, "/usr/bin/python3", "--version"]),
        ("uv", ["docker", "exec", name, "uv", "--version"]),
        ("flutter", ["docker", "exec", name, "flutter", "--version"]),
        ("dart", ["docker", "exec", name, "sh", "-c", "dart --version 2>&1"]),
        ("pi", ["docker", "exec", name, "pi", "--version"]),
        ("websockets", ["docker", "exec", name, "python3", "-c", "import websockets; print(websockets.__version__)"]),
        ("linux_engine", ["docker", "exec", name, "test", "-f", "/sdks/flutter/bin/cache/artifacts/engine/linux-arm64/libflutter_linux_gtk.so"]),
        ("media", ["docker", "exec", name, "python3", "-c", "import json; from pathlib import Path; root=Path('/opt/nothingness/media'); assert len(list(root.glob('*.opus'))) == 10; assert len(json.loads((root/'manifest.json').read_text())) == 10"]),
        ("workspace", ["docker", "exec", name, "sh", "-c", "touch /workspace/.baseline-write && rm /workspace/.baseline-write && test -z \"$(git -C /workspace status --porcelain)\""]),
        ("pub", ["docker", "exec", name, "sh", "-c", "cd /workspace && flutter pub get --offline >/tmp/nothingness-baseline-pub.log"]),
        ("linux_build", ["docker", "exec", name, "sh", "-c", "cd /workspace && flutter build linux --no-pub >/tmp/nothingness-baseline-build.log && test -x build/linux/arm64/release/bundle/nothingness"]),
    )


def main() -> None:
    parser = argparse.ArgumentParser(description="Verify the evaluator substrate without credentials, network, or a model call.")
    parser.add_argument("--build-image", action="store_true")
    arguments = parser.parse_args()
    for executable in ("docker", "git", "tar"):
        require_command(executable)
    active = command(["docker", "ps", "--filter", "label=nothingness.eval=true", "--format", "{{.Names}}"], stdout=subprocess.PIPE)
    if active.stdout.strip():
        fail(2, "evaluator_container_already_running")
    if arguments.build_image:
        command_or_fail([sys.executable, str(Path(__file__).with_name("build-image.py"))], 3, "image_build_failed", stdout=subprocess.PIPE)
    image_id = command_or_fail(["docker", "image", "inspect", "--format", "{{.Id}}", IMAGE_NAME], 3, "image_not_available", stdout=subprocess.PIPE).stdout.strip()
    name = f"nothingness-eval-baseline-{uuid.uuid4().hex[:12]}"
    checks: dict[str, str] = {}
    (ROOT / ".tmp").mkdir(exist_ok=True)
    try:
        with tempfile.TemporaryDirectory(prefix="nothingness-eval-baseline.", dir=ROOT / ".tmp") as temporary:
            seed = Path(temporary) / "workspace"
            seed.mkdir()
            archive = command_or_fail(["git", "archive", FIXTURE], 3, "fixture_archive_failed", stdout=subprocess.PIPE, text=False).stdout
            command_or_fail(["tar", "-x", "-C", str(seed)], 3, "fixture_extract_failed", input=archive, text=False)
            for git_arguments in (("init", "-q"), ("config", "user.name", "Nothingness Evaluator"), ("config", "user.email", "evaluator@invalid"), ("add", "-A"), ("commit", "-qm", "fixture baseline")):
                command_or_fail(["git", *git_arguments], 3, "fixture_baseline_failed", cwd=seed)
            command_or_fail(["chmod", "-R", "a+rwX", str(seed)], 3, "fixture_permissions_failed")
            command_or_fail(container_run_command(name), 3, "baseline_container_start_failed", stdout=os.devnull)
            command_or_fail(["docker", "cp", f"{seed}/.", f"{name}:/workspace"], 3, "baseline_workspace_copy_failed", stdout=os.devnull)
            command_or_fail(["docker", "exec", name, "mkdir", "-p", "/run/nothingness/home"], 3, "baseline_home_setup_failed")
            command_or_fail(["docker", "exec", name, "git", "config", "--global", "--add", "safe.directory", "/workspace"], 3, "baseline_git_trust_failed")
            for label, check in baseline_checks(name):
                output = command_or_fail(check, 4, f"baseline_check_failed:{label}", stdout=subprocess.PIPE, stderr=subprocess.STDOUT).stdout.strip()
                checks[label] = output.splitlines()[0] if output else "passed"
    finally:
        command(["docker", "rm", "-f", name], stdout=os.devnull, stderr=os.devnull)
    if command(["docker", "container", "inspect", name], stdout=os.devnull, stderr=os.devnull).returncode == 0:
        fail(4, "baseline_container_cleanup_failed")
    emit_json({"ok": True, "network": "none", "credentials": "not_loaded", "candidate": "not_launched", "fixture_commit": FIXTURE, "image": {"name": IMAGE_NAME, "immutable_id": image_id}, "checks": checks, "cleanup": "passed"})


if __name__ == "__main__":
    main()