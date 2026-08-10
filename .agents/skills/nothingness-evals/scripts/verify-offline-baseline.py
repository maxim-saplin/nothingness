from __future__ import annotations

import argparse
import contextlib
import io
import json
import os
import subprocess
import sys
import tempfile
import uuid
from pathlib import Path

from common import IMAGE_NAME, ROOT, command, command_or_fail, command_or_fail_chained, emit_json, fail, gate_fingerprint, passed_gate, record_gate_pass, require_command, validate_image_matches_sources


FIXTURE = "5fc7e04"

# Flutter's own arch naming (`bin/cache/artifacts/engine/linux-<arch>`, `build/linux/<arch>`),
# keyed by the container's `uname -m` -- read from the CONTAINER, not the host, since docker
# can run an emulated image whose arch differs from the host's.
FLUTTER_ARCH = {"x86_64": "x64", "aarch64": "arm64", "arm64": "arm64"}
VERSION_CHECKS = frozenset({"python", "uv", "flutter", "dart", "pi", "websockets"})


def container_arch(name: str) -> str:
    machine = command_or_fail(["docker", "exec", name, "uname", "-m"], 4, "container_arch_probe_failed", stdout=subprocess.PIPE).stdout.strip()
    arch = FLUTTER_ARCH.get(machine)
    if arch is None:
        fail(4, f"unsupported_container_arch:{machine}")
    return arch


def container_run_command(name: str) -> list[str]:
    return [
        "docker", "run", "-d", "--rm", "--name", name,
        "--label", "nothingness.eval.baseline=true",
        "--cap-drop", "ALL", "--security-opt", "no-new-privileges=true",
        "--network", "none", "--entrypoint", "sleep", IMAGE_NAME, "infinity",
    ]


def baseline_checks(name: str, arch: str) -> tuple[tuple[str, list[str]], ...]:
    return (
        ("exec", ["docker", "exec", name, "true"]),
        ("python", ["docker", "exec", name, "/usr/bin/python3", "--version"]),
        ("uv", ["docker", "exec", name, "uv", "--version"]),
        ("flutter", ["docker", "exec", name, "flutter", "--version"]),
        ("dart", ["docker", "exec", name, "sh", "-c", "dart --version 2>&1"]),
        ("pi", ["docker", "exec", name, "pi", "--version"]),
        ("websockets", ["docker", "exec", name, "python3", "-c", "import websockets; print(websockets.__version__)"]),
        ("linux_engine", ["docker", "exec", name, "test", "-f", f"/sdks/flutter/bin/cache/artifacts/engine/linux-{arch}/libflutter_linux_gtk.so"]),
        # The candidate must never see the machinery that scores it. The fixture is
        # the whole repo at 5fc7e04, so this asserts that commit carries no rubrics,
        # suites, published results or evaluator skill -- otherwise a candidate could
        # read the rubric it is being graded against.
        ("fixture_has_no_eval_machinery", ["docker", "exec", name, "sh", "-c", "! ls -d /workspace/evals /workspace/.agents/skills/nothingness-evals /workspace/.claude/skills/nothingness-evals 2>/dev/null | grep -q ."]),
        ("media", ["docker", "exec", name, "python3", "-c", "import json; from pathlib import Path; root=Path('/opt/nothingness/media'); assert len(list(root.glob('*.opus'))) == 10; assert len(json.loads((root/'manifest.json').read_text())) == 10"]),
        ("workspace", ["docker", "exec", name, "sh", "-c", "touch /workspace/.baseline-write && rm /workspace/.baseline-write && test -z \"$(git -C /workspace status --porcelain)\""]),
        ("pub", ["docker", "exec", name, "sh", "-c", "cd /workspace && flutter pub get --offline >/tmp/nothingness-baseline-pub.log"]),
        ("linux_build", ["docker", "exec", name, "sh", "-c", f"cd /workspace && flutter build linux --no-pub >/tmp/nothingness-baseline-build.log && test -x build/linux/{arch}/release/bundle/nothingness"]),
    )



def image_matches_sources() -> bool:
    """True when the built image's frozen source manifest still matches disk."""
    inspect = command(["docker", "image", "inspect", IMAGE_NAME], stdout=subprocess.PIPE, stderr=subprocess.DEVNULL)
    if inspect.returncode:
        return False
    labels = json.loads(inspect.stdout)[0].get("Config", {}).get("Labels") or {}
    buffer = io.StringIO()
    try:
        with contextlib.redirect_stderr(buffer):
            validate_image_matches_sources(labels)
    except SystemExit:
        return False
    return True


def main() -> None:
    parser = argparse.ArgumentParser(description="Verify the evaluator substrate without credentials, network, or a model call.")
    parser.add_argument("--build-image", action="store_true")
    parser.add_argument("--force", action="store_true", help="re-verify even if this exact image/fixture/gate already passed")
    arguments = parser.parse_args()
    for executable in ("docker", "git", "tar"):
        require_command(executable)
    active = command(["docker", "ps", "--filter", "label=nothingness.eval=true", "--format", "{{.Names}}"], stdout=subprocess.PIPE)
    if active.stdout.strip():
        fail(2, "evaluator_container_already_running")
    # Checked before `--build-image` runs, not after: when the image is already
    # current there is nothing to build, and invoking the builder just to learn
    # that is most of what made this gate feel expensive on a no-op run.
    existing = command(["docker", "image", "inspect", "--format", "{{.Id}}", IMAGE_NAME], stdout=subprocess.PIPE, stderr=subprocess.DEVNULL)
    if existing.returncode == 0 and not arguments.force and image_matches_sources():
        # `image_matches_sources()` guards the skip because the fingerprint below
        # is (image id, fixture, this script) and says nothing about the image's
        # own sources. Editing candidate.py therefore left the fingerprint intact:
        # the gate skipped, silently ignored --build-image, and reported ok on a
        # stale image -- which `judge-run.py start` then refused, so the gate was
        # the last thing to notice a problem it exists to catch.
        previous = passed_gate("offline-baseline", gate_fingerprint(existing.stdout.strip(), FIXTURE, Path(__file__)))
        if previous is not None:
            emit_json({**previous["result"], "skipped": "unchanged_since_last_pass", "previously_passed_at": previous["passed_at"], "reverify_with": "--force"})
            return
    if arguments.build_image:
        command_or_fail_chained([sys.executable, str(Path(__file__).with_name("build-image.py"))], 3, "image_build_failed", stdout=subprocess.PIPE)
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
            arch = container_arch(name)
            for label, check in baseline_checks(name, arch):
                output = command_or_fail(check, 4, f"baseline_check_failed:{label}", stdout=subprocess.PIPE, stderr=subprocess.STDOUT).stdout.strip()
                # Only the version probes have meaningful stdout. Every other check
                # is pass/fail, and echoing its first output line reports things like
                # SoLoud's CMake banner as if it were the result -- which reads as a
                # broken check to anyone who hasn't seen a build log here before.
                checks[label] = (output.splitlines()[0] if output else "passed") if label in VERSION_CHECKS else "passed"
    finally:
        command(["docker", "rm", "-f", name], stdout=os.devnull, stderr=os.devnull)
    if command(["docker", "container", "inspect", name], stdout=os.devnull, stderr=os.devnull).returncode == 0:
        fail(4, "baseline_container_cleanup_failed")
    result = {"ok": True, "network": "none", "credentials": "not_loaded", "candidate": "not_launched", "fixture_commit": FIXTURE, "image": {"name": IMAGE_NAME, "immutable_id": image_id}, "checks": checks, "cleanup": "passed"}
    record_gate_pass("offline-baseline", gate_fingerprint(image_id, FIXTURE, Path(__file__)), result)
    emit_json(result)


if __name__ == "__main__":
    main()