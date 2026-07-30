from __future__ import annotations

import json
import os
import re
import shlex
import shutil
import subprocess
import sys
import tempfile
from pathlib import Path

from common import command, command_or_fail, emit_json, fail, read_host_pi_config, read_json, redact_bytes, redact_text, redact_value, run_dir, require_command, secret_values, validate_no_secret_leaks, validate_run_id, write_json


def safe_untracked_path(value: str) -> Path | None:
    path = Path(value)
    if not value or path.is_absolute() or ".." in path.parts:
        return None
    return path


def redacted_path(path: Path, secrets: tuple[str, ...]) -> Path:
    value = safe_untracked_path(redact_text(path.as_posix(), secrets))
    if value is None:
        fail(4, "unsafe_redacted_artifact_path")
    return value


def container_file(container: str, source: str, destination: Path, secrets: tuple[str, ...]) -> bool:
    result = command(["docker", "exec", container, "cat", source], stdout=subprocess.PIPE, stderr=subprocess.DEVNULL, text=False)
    if result.returncode:
        return False
    destination.parent.mkdir(parents=True, exist_ok=True)
    destination.write_bytes(redact_bytes(result.stdout, secrets))
    return True


def container_tree(container: str, source: str, destination: Path, secrets: tuple[str, ...]) -> int:
    listing = command(["docker", "exec", container, "find", source, "-type", "f", "-print0"], stdout=subprocess.PIPE, stderr=subprocess.DEVNULL, text=False)
    if listing.returncode:
        return 0
    copied = 0
    prefix = source.rstrip("/") + "/"
    for encoded in listing.stdout.split(b"\0"):
        if not encoded:
            continue
        path = encoded.decode("utf-8", "surrogateescape")
        if not path.startswith(prefix):
            fail(4, "unsafe_container_artifact_path")
        relative = safe_untracked_path(path.removeprefix(prefix))
        if relative is None or not container_file(container, path, destination / redacted_path(relative, secrets), secrets):
            fail(4, "container_artifact_copy_failed")
        copied += 1
    return copied


def copy_untracked(container: str, artifacts: Path, secrets: tuple[str, ...]) -> int:
    result = command_or_fail(
        ["docker", "exec", container, "git", "-C", "/workspace", "ls-files", "--others", "--exclude-standard", "-z"],
        4,
        "workspace_artifact_failed",
        stdout=-1,
        text=False,
    )
    paths = result.stdout.split(b"\0")
    output = artifacts / "untracked.txt"
    untracked = artifacts / "workspace-untracked"
    untracked.mkdir(exist_ok=True)
    copied = 0
    with output.open("w", encoding="utf-8") as listing:
        for encoded in paths:
            if not encoded:
                continue
            try:
                relative = safe_untracked_path(encoded.decode("utf-8", "surrogateescape"))
            except UnicodeDecodeError:
                relative = None
            if relative is None:
                fail(4, "invalid_untracked_path")
            safe_destination = redacted_path(relative, secrets)
            listing.write(f"{safe_destination.as_posix()}\n")
            kind = command(["docker", "exec", container, "python3", "-c", "import os,sys; print('symlink' if os.path.islink(sys.argv[1]) else 'file' if os.path.isfile(sys.argv[1]) else 'other')", f"/workspace/{relative.as_posix()}"], stdout=-1, stderr=os.devnull)
            if kind.returncode or kind.stdout.strip() != "file":
                fail(4, "unsafe_untracked_file")
            destination = untracked / safe_destination
            destination.parent.mkdir(parents=True, exist_ok=True)
            if not container_file(container, f"/workspace/{relative.as_posix()}", destination, secrets):
                fail(4, "untracked_copy_failed")
            copied += 1
    return copied


def copy_optional(container: str, source: str, destination: Path, secrets: tuple[str, ...]) -> bool:
    return container_file(container, source, destination, secrets)


def publish_artifacts(staging: Path, destination: Path, scan_root: Path, secrets: tuple[str, ...]) -> None:
    try:
        validate_no_secret_leaks(scan_root, secrets)
        for path in staging.rglob("*"):
            if path.is_file() and not path.is_symlink():
                descriptor = os.open(path, os.O_RDONLY)
                try:
                    os.fsync(descriptor)
                finally:
                    os.close(descriptor)
        for path in sorted((item for item in staging.rglob("*") if item.is_dir()), reverse=True):
            descriptor = os.open(path, os.O_RDONLY)
            try:
                os.fsync(descriptor)
            finally:
                os.close(descriptor)
        descriptor = os.open(staging, os.O_RDONLY)
        try:
            os.fsync(descriptor)
        finally:
            os.close(descriptor)
        if destination.exists():
            if any(destination.iterdir()):
                fail(4, "artifacts_already_collected")
            destination.rmdir()
        os.replace(staging, destination)
        descriptor = os.open(destination.parent, os.O_RDONLY)
        try:
            os.fsync(descriptor)
        finally:
            os.close(descriptor)
    except BaseException:
        shutil.rmtree(staging, ignore_errors=True)
        if destination.is_dir() and not any(destination.iterdir()):
            destination.rmdir()
        raise


def drive_action(arguments: object) -> str | None:
    if not isinstance(arguments, dict) or not isinstance(arguments.get("command"), str):
        return None
    raw = arguments["command"]
    if any(character in raw for character in ";&|<>$`()\r\n"):
        return None
    lexer = shlex.shlex(raw, posix=True, punctuation_chars=";&|<>")
    lexer.whitespace_split = True
    try:
        tokens = list(lexer)
    except ValueError:
        return None
    if not tokens or any(token and set(token) <= set(";&|<>") for token in tokens):
        return None
    while tokens and "=" in tokens[0] and not tokens[0].startswith(("/", "./", "../")):
        tokens.pop(0)
    if tokens and Path(tokens[0]).name in {"python", "python3"}:
        tokens.pop(0)
    elif tokens[:2] == ["uv", "run"]:
        tokens = tokens[2:]
        if tokens and tokens[0] == "--script":
            tokens.pop(0)
        elif tokens and Path(tokens[0]).name in {"python", "python3"}:
            tokens.pop(0)
    if len(tokens) < 2 or Path(tokens[0]).name != "drive.py":
        return None
    action = tokens[1]
    if action in {"play", "resume"}:
        return "play"
    if action == "pause":
        return "pause"
    if action in {"next", "prev"}:
        return "skip"
    if action == "seek":
        return "seek"
    if action == "call" and len(tokens) >= 3:
        return {
            "ext.nothingness.play": "play",
            "ext.nothingness.playTrackByPath": "play",
            "ext.nothingness.pause": "pause",
            "ext.nothingness.next": "skip",
            "ext.nothingness.prev": "skip",
            "ext.nothingness.seek": "seek",
        }.get(tokens[2])
    return None


def drive_actions(arguments: object) -> set[str]:
    direct = drive_action(arguments)
    if direct is not None:
        return {direct}
    if not isinstance(arguments, dict) or not isinstance(arguments.get("command"), str):
        return set()
    lines = [line.strip() for line in arguments["command"].splitlines() if line.strip() and not line.lstrip().startswith("#")]
    if "set -euo pipefail" not in lines:
        return set()
    variables: set[str] = set()
    for line in lines:
        match = re.fullmatch(r"([A-Za-z_][A-Za-z0-9_]*)=([^\s;&|<>$`()]+)", line)
        if match and Path(match.group(2)).name == "drive.py":
            variables.add(match.group(1))
    observed: set[str] = set()
    for line in lines:
        match = re.fullmatch(r"\$([A-Za-z_][A-Za-z0-9_]*)\s+(resume|pause|next|prev|seek)(?:\s+([0-9]+(?::[0-9]{2})?))?\s*(?:>>?\s*[^\s;&|<>$`()]+)?", line)
        if not match or match.group(1) not in variables:
            continue
        command_name, command_argument = match.group(2), match.group(3)
        if command_name == "seek" and command_argument is None:
            continue
        if command_name != "seek" and command_argument is not None:
            continue
        observed.add({"resume": "play", "pause": "pause", "next": "skip", "prev": "skip", "seek": "seek"}[command_name])
    return observed


def t1_task_evidence(transcript: Path, inspection: subprocess.CompletedProcess[str]) -> dict[str, object]:
    starts: dict[str, object] = {}
    successful: set[str] = set()
    with transcript.open(encoding="utf-8", errors="replace") as source:
        for line in source:
            try:
                event = json.loads(line)
            except json.JSONDecodeError:
                continue
            call_id = event.get("toolCallId")
            if event.get("type") == "tool_execution_start" and isinstance(call_id, str):
                starts[call_id] = event.get("args")
            elif event.get("type") == "tool_execution_end" and isinstance(call_id, str) and event.get("isError") is False:
                successful.add(call_id)
    observed = set().union(*(drive_actions(starts[call_id]) for call_id in successful if call_id in starts))
    actions = {name: name in observed for name in ("play", "pause", "skip", "seek")}
    state = None
    if inspection.returncode == 0:
        try:
            state = json.loads(inspection.stdout).get("playback")
        except (json.JSONDecodeError, AttributeError):
            pass
    state_valid = isinstance(state, dict) and isinstance(state.get("queueLength"), int) and state["queueLength"] > 0 and isinstance(state.get("currentIndex"), int) and 0 <= state["currentIndex"] < state["queueLength"] and isinstance(state.get("songInfo"), dict) and str(state["songInfo"].get("path", "")).endswith(".opus")
    return {"schema_version": 1, "oracle": "t1-playback-smoke-linux", "actions": actions, "post_run_playback": state, "passed": all(actions.values()) and state_valid}


def main() -> None:
    require_command("docker")
    if len(sys.argv) != 2:
        fail(2, "usage:collect_run_id")
    run_id = sys.argv[1]
    validate_run_id(run_id)
    run = run_dir(run_id)
    if not (run / "run.json").is_file():
        fail(3, "run_not_prepared")
    container = read_json(run / "run.json")["container"]
    metadata = read_json(run / "run.json")
    pi_config = read_host_pi_config(provider=metadata["selected_model"]["provider"])
    if pi_config["config_fingerprints"] != metadata["pi"]["config_fingerprints"]:
        fail(4, "pi_config_changed_before_collection")
    secrets = secret_values(pi_config["pi_config"], pi_config["provider_env"])
    destination = run / "artifacts"
    artifacts = Path(tempfile.mkdtemp(prefix=".artifacts-", dir=run))
    try:
        if not container_file(container, "/run/nothingness/candidate.jsonl", artifacts / "candidate.jsonl", secrets):
            fail(4, "candidate_output_copy_failed")
        for source, destination_name in (("candidate.stderr", "candidate.stderr"), ("candidate-completion.json", "candidate-completion.json"), ("lifecycle.jsonl", "lifecycle.jsonl"), ("progress.json", "progress.json")):
            container_file(container, f"/run/nothingness/{source}", artifacts / destination_name, secrets)
        container_tree(container, "/run/nothingness/sessions", artifacts / "sessions", secrets)
        container_tree(container, "/run/nothingness/logs", artifacts / "service-logs", secrets)
        for git_args, name in ((("status", "--short"), "git-status.txt"), (("diff", "--binary"), "candidate.diff")):
            result = command_or_fail(["docker", "exec", container, "git", "-C", "/workspace", *git_args], 4, "workspace_artifact_failed", stdout=subprocess.PIPE)
            (artifacts / name).write_text(redact_text(result.stdout, secrets))
        untracked_count = copy_untracked(container, artifacts, secrets)
        health = command(["docker", "exec", container, "cat", "/run/nothingness/health.json"], stdout=-1, stderr=os.devnull)
        write_json(artifacts / "health.json", redact_value(json.loads(health.stdout), secrets) if health.returncode == 0 else {"available": False})
        processes = command(["docker", "top", container, "-eo", "pid,ppid,stat,etime,comm"], stdout=-1, stderr=os.devnull)
        write_json(artifacts / "processes.json", redact_value({"available": processes.returncode == 0, "snapshot": processes.stdout.splitlines()[:200] if processes.returncode == 0 else []}, secrets))
        flutter_log_copied = copy_optional(container, "/run/nothingness/drive/flutter_run.log", artifacts / "flutter_run.log", secrets)
        if not flutter_log_copied:
            flutter_log_copied = copy_optional(container, "/tmp/flutter_run.log", artifacts / "flutter_run.log", secrets)
        task_evidence_copied = False
        if metadata["task_id"] == "t1-playback-smoke-linux":
            inspection = command(["docker", "exec", container, "python3", "/workspace/.agents/skills/agent-emulator-debugging/scripts/drive.py", "inspect"], stdout=-1, stderr=os.devnull)
            evidence = t1_task_evidence(artifacts / "candidate.jsonl", inspection)
            write_json(artifacts / "task-evidence.json", redact_value(evidence, secrets))
            task_evidence_copied = True
        proxy_logs = command(["docker", "logs", metadata["proxy"]], stdout=-1, stderr=subprocess.STDOUT)
        if proxy_logs.returncode == 0:
            (artifacts / "proxy.log").write_text(redact_text(proxy_logs.stdout, secrets))
        with (artifacts / "container.txt").open("w") as output:
            command_or_fail(["docker", "inspect", "--format", "{{.Id}} {{.Image}} {{.State.Status}}", container], 4, "container_metadata_failed", stdout=output)
        result = {"ok": True, "run_id": run_id, "artifacts": str(destination), "scoring": metadata["scoring"], "untracked_files": untracked_count, "flutter_log_copied": flutter_log_copied, "task_evidence_copied": task_evidence_copied, "lifecycle_copied": (artifacts / "lifecycle.jsonl").is_file(), "progress_copied": (artifacts / "progress.json").is_file(), "proxy_log_copied": proxy_logs.returncode == 0}
        publish_artifacts(artifacts, destination, run, secrets)
        write_json(run / "collect.json", result)
        emit_json(result)
    finally:
        shutil.rmtree(artifacts, ignore_errors=True)


if __name__ == "__main__":
    main()