from __future__ import annotations

import argparse
import hashlib
import json
import subprocess
import uuid
from pathlib import Path

from common import DRIVE_DEFAULT_RUN_LOG as DEFAULT_RUN_LOG, DRIVE_DRIVER as DRIVER, DRIVE_NO_LIVE_APP_REASON as NO_LIVE_APP_REASON, append_jsonl, command, discover_drive_endpoint, drive_exec_args, emit_json, fail, read_host_pi_config, read_json, redact_bytes, redact_value, run_dir, secret_values, sha256, utc_now, validate_run_id, write_json

PNG_MAGIC = b"\x89PNG\r\n\x1a\n"


def drive(container: str, env: dict[str, str], *arguments: str) -> subprocess.CompletedProcess[str]:
    """Run `drive.py` inside `container`, with `env` overlaid via `docker exec
    -e` (empty for default discovery). Every capture in one judge-verify.py
    invocation is called with the same `env`, resolved once by
    `discover_endpoint` — see `common.discover_drive_endpoint`'s docstring for
    why."""
    return command(drive_exec_args(container, env, *arguments), stdout=subprocess.PIPE, stderr=subprocess.DEVNULL)


def discover_endpoint(container: str) -> dict[str, object]:
    """Find a live app inside the container before any capture runs. The
    algorithm is shared with judge-inspect.py via
    `common.discover_drive_endpoint`; this module's own `command` is passed
    through so existing test-patching of `judge_verify.command` keeps
    working unchanged."""
    return discover_drive_endpoint(container, command)


# Each capture below returns (payload_to_persist, available, reason_if_not).
# `available` is never just "the command exited zero": drive.py's own
# extension handlers return _ok(...) — exit 0, valid JSON — for several
# "nothing to show" cases (no live isolate, no accessibility tree attached),
# which is indistinguishable from a real capture by return code alone (D3).
# Each function inspects the actual payload for the known sentinel(s).

def runtime_capture(container: str, env: dict[str, str]) -> tuple[object, bool, str | None]:
    result = drive(container, env, "inspect")
    if result.returncode:
        return {"available": False}, False, "drive.py inspect failed"
    try:
        payload = json.loads(result.stdout)
    except json.JSONDecodeError:
        return {"available": True, "output": result.stdout[:16_000]}, False, "inspect output was not JSON"
    if not isinstance(payload, dict) or "playback" not in payload:
        return payload, False, "inspect payload missing playback state"
    return payload, True, None


def tree_capture(container: str, env: dict[str, str]) -> tuple[str, bool, str | None]:
    result = drive(container, env, "tree", "80")
    if result.returncode:
        return "", False, "drive.py tree failed"
    stripped = result.stdout.strip()
    if not stripped:
        return result.stdout, False, "tree output was empty"
    if stripped == "no root element":
        return result.stdout, False, "no root element (app not attached to a live isolate)"
    return result.stdout, True, None


def semantics_capture(container: str, env: dict[str, str]) -> tuple[object, bool, str | None]:
    result = drive(container, env, "call", "ext.nothingness.getSemantics")
    if result.returncode:
        return {"available": False}, False, "drive.py call getSemantics failed"
    try:
        payload = json.loads(result.stdout)
    except json.JSONDecodeError:
        return {"available": True, "output": result.stdout[:16_000]}, False, "getSemantics output was not JSON"
    semantics = payload.get("semantics") if isinstance(payload, dict) else None
    if not isinstance(semantics, str) or not semantics.strip() or semantics == "semantics not available":
        return payload, False, "semantics not available (no live accessibility tree)"
    return payload, True, None


def settings_capture(container: str, env: dict[str, str]) -> tuple[object, bool, str | None]:
    result = drive(container, env, "call", "ext.nothingness.getSettings")
    if result.returncode:
        return {"available": False}, False, "drive.py call getSettings failed"
    try:
        payload = json.loads(result.stdout)
    except json.JSONDecodeError:
        return {"available": True, "output": result.stdout[:16_000]}, False, "getSettings output was not JSON"
    if not isinstance(payload, dict) or "screenType" not in payload:
        return payload, False, "getSettings payload missing screenType"
    return payload, True, None


def screenshot_capture(container: str, env: dict[str, str], shot_name: str) -> tuple[bytes, bool, str | None]:
    shoot = drive(container, env, "shoot", shot_name)
    if shoot.returncode:
        return b"", False, "drive.py shoot failed"
    screenshot = command(["docker", "exec", container, "cat", f"/workspace/.tmp/agent_shots/{shot_name}.png"], stdout=subprocess.PIPE, stderr=subprocess.DEVNULL, text=False)
    if screenshot.returncode or not screenshot.stdout.startswith(PNG_MAGIC):
        return b"", False, "screenshot file missing or not a valid PNG"
    return screenshot.stdout, True, None


def write_artifact(run: Path, destination: Path, name: str, content: bytes) -> dict[str, object]:
    path = destination / name
    path.write_bytes(content)
    return {"path": str(path.relative_to(run)), "sha256": hashlib.sha256(content).hexdigest()}


def main() -> None:
    parser = argparse.ArgumentParser(allow_abbrev=False)
    parser.add_argument("run_id")
    parser.add_argument("--label", required=True)
    arguments = parser.parse_args()
    validate_run_id(arguments.run_id)
    run = run_dir(arguments.run_id)
    metadata = read_json(run / "run.json")
    pi_config = read_host_pi_config(provider=metadata["selected_model"]["provider"])
    if pi_config["config_fingerprints"] != metadata["pi"]["config_fingerprints"]:
        fail(4, "pi_config_changed_during_judge_verification")
    secrets = secret_values(pi_config["pi_config"], pi_config["provider_env"])
    container = metadata["container"]
    observation_id = f"verification-{uuid.uuid4().hex}"
    destination = run / "judge-verifications" / observation_id
    destination.mkdir(parents=True)

    # Locate a live app ONCE per invocation; every capture below reuses the
    # same discovered env so they are consistent with each other (D4: the
    # judge must not report a mix of endpoints across one observation).
    discovery = discover_endpoint(container)
    env = discovery["env"]

    artifacts: dict[str, dict[str, object]] = {}
    availability: dict[str, bool] = {}
    reasons: dict[str, str] = {}

    if discovery["ok"]:
        runtime_payload, runtime_ok, runtime_reason = runtime_capture(container, env)
        tree_text, tree_ok, tree_reason = tree_capture(container, env)
        semantics_payload, semantics_ok, semantics_reason = semantics_capture(container, env)
        settings_payload, settings_ok, settings_reason = settings_capture(container, env)
        screenshot_bytes, screenshot_ok, screenshot_reason = screenshot_capture(container, env, observation_id)
    else:
        # Discovery itself found no live app — every capture below would
        # fail for the SAME root cause, not five independent problems. Say
        # so once, distinctly from a per-capture failure reason (a live app
        # found but e.g. no accessibility tree attached), and skip the
        # doomed docker execs.
        runtime_payload, runtime_ok, runtime_reason = {"available": False}, False, NO_LIVE_APP_REASON
        tree_text, tree_ok, tree_reason = "", False, NO_LIVE_APP_REASON
        semantics_payload, semantics_ok, semantics_reason = {"available": False}, False, NO_LIVE_APP_REASON
        settings_payload, settings_ok, settings_reason = {"available": False}, False, NO_LIVE_APP_REASON
        screenshot_bytes, screenshot_ok, screenshot_reason = b"", False, NO_LIVE_APP_REASON

    artifacts["runtime"] = write_artifact(run, destination, "inspect.json", json.dumps(redact_value(runtime_payload, secrets), separators=(",", ":")).encode())
    availability["runtime"] = runtime_ok
    if runtime_reason:
        reasons["runtime"] = runtime_reason

    artifacts["tree"] = write_artifact(run, destination, "tree.txt", redact_bytes(tree_text.encode("utf-8", "replace"), secrets))
    availability["tree"] = tree_ok
    if tree_reason:
        reasons["tree"] = tree_reason

    artifacts["semantics"] = write_artifact(run, destination, "semantics.json", json.dumps(redact_value(semantics_payload, secrets), separators=(",", ":")).encode())
    availability["semantics"] = semantics_ok
    if semantics_reason:
        reasons["semantics"] = semantics_reason

    artifacts["settings"] = write_artifact(run, destination, "settings.json", json.dumps(redact_value(settings_payload, secrets), separators=(",", ":")).encode())
    availability["settings"] = settings_ok
    if settings_reason:
        reasons["settings"] = settings_reason

    artifacts["screenshot"] = write_artifact(run, destination, "screenshot.png", redact_bytes(screenshot_bytes, secrets))
    availability["screenshot"] = screenshot_ok
    if screenshot_reason:
        reasons["screenshot"] = screenshot_reason

    manifest = {
        "observation_id": observation_id,
        "label": arguments.label,
        "artifacts": artifacts,
        "availability": availability,
        "unavailable_reasons": reasons,
        "discovery": {"method": discovery["method"], "log_path": discovery["log_path"], "env": env},
    }
    manifest_path = destination / "manifest.json"
    write_json(manifest_path, manifest)
    digest = sha256(manifest_path)
    append_jsonl(run / "judge-observations.jsonl", {"observation_id": observation_id, "timestamp": utc_now(), "kind": "verification", "label": arguments.label, "availability": availability, "evidence": str(manifest_path.relative_to(run)), "sha256": digest})
    emit_json({"ok": True, "run_id": arguments.run_id, "observation_id": observation_id, "availability": availability, "unavailable_reasons": reasons, "discovery": manifest["discovery"], "manifest": str(manifest_path.relative_to(run))})


if __name__ == "__main__":
    main()
