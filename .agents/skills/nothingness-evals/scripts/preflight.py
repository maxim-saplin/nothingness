from __future__ import annotations

import os
import sys
import time

from common import ROOT, command, emit_json, fail, read_host_pi_config, read_json, run_dir, require_command, utc_now, validate_frozen_suite, validate_frozen_task, validate_model_identity, validate_run_id, write_json
from usage import normalized_usage


def validate_pre_admission_contract(metadata: dict[str, object], root: object = ROOT) -> None:
    validate_frozen_suite(metadata, root)
    validate_frozen_task(metadata, root / "evals" / "tasks" / f"{metadata['task_id']}.json")


def main() -> None:
    for executable in ("docker", "curl"):
        require_command(executable)
    if len(sys.argv) != 2:
        fail(2, "usage:preflight_run_id")
    run_id = sys.argv[1]
    validate_run_id(run_id)
    run = run_dir(run_id)
    if not (run / "run.json").is_file():
        fail(3, "run_not_prepared")
    metadata = read_json(run / "run.json")
    validate_model_identity(metadata["requested_model"], metadata["selected_model"])
    validate_pre_admission_contract(metadata)
    container, proxy, network, url = metadata["container"], metadata["proxy"], metadata["network"], metadata["novnc_url"]
    if command(["docker", "container", "inspect", container], stdout=os.devnull, stderr=os.devnull).returncode:
        fail(4, "container_not_running")
    inspection = command(["docker", "container", "inspect", container, proxy], stdout=-1)
    try:
        candidate, proxy_configuration = read_json_value(inspection.stdout)
        host = candidate["HostConfig"]
        configured_names = {entry.split("=", 1)[0] for entry in candidate["Config"].get("Env", [])}
        candidate_networks = candidate["NetworkSettings"]["Networks"]
        proxy_networks = proxy_configuration["NetworkSettings"]["Networks"]
        proxy_host = proxy_configuration["HostConfig"]
        network_info = read_json_value(command(["docker", "network", "inspect", network], stdout=-1).stdout)[0]
        security_ready = (
            candidate["State"]["Running"] is True
            and proxy_configuration["State"]["Running"] is True
            and
            "ALL" in (host.get("CapDrop") or [])
            and "no-new-privileges=true" in (host.get("SecurityOpt") or [])
            and host.get("NetworkMode") == network
            and set(candidate_networks) == {network}
            and network_info["Internal"] is True
            and {network, "bridge"}.issubset(proxy_networks)
            and "ALL" in (proxy_host.get("CapDrop") or [])
            and "no-new-privileges=true" in (proxy_host.get("SecurityOpt") or [])
            and {"HTTP_PROXY", "HTTPS_PROXY", "NO_PROXY"}.issubset(configured_names)
        )
    except (ValueError, KeyError, IndexError, TypeError):
        security_ready = False
    if not security_ready:
        fail(4, "container_security_mismatch")
    ready = False
    health = None
    for _ in range(60):
        health = command(["docker", "exec", container, "cat", "/run/nothingness/health.json"], stdout=-1, stderr=os.devnull)
        if health.returncode == 0:
            try:
                ready = read_json_value(health.stdout)["status"] == "ready"
            except (ValueError, KeyError):
                ready = False
            if ready:
                break
        time.sleep(0.5)
    if health is None or health.returncode:
        fail(4, "health_missing")
    if not ready:
        fail(4, "desktop_not_ready")
    if command(["curl", "--fail", "--silent", "--output", os.devnull, url]).returncode:
        fail(4, "novnc_unreachable")
    allowed_host = metadata["egress_host"]
    blocked_host = "example.com" if allowed_host != "example.com" else "blocked.invalid"
    proxy_probe = """import socket,sys
proxy,allowed,blocked=sys.argv[1:]
def connect(host):
    with socket.create_connection((proxy,3128),timeout=8) as connection:
        connection.sendall(f'CONNECT {host}:443 HTTP/1.1\\r\\nHost: {host}:443\\r\\n\\r\\n'.encode())
        return connection.recv(128).split(b'\\r\\n',1)[0]
assert connect(allowed).startswith(b'HTTP/1.1 200')
assert connect(blocked).startswith(b'HTTP/1.1 403')
try:
    socket.create_connection((allowed,443),timeout=3)
except OSError:
    pass
else:
    raise AssertionError('direct_egress_succeeded')
"""
    if command(["docker", "exec", container, "python3", "-c", proxy_probe, proxy, allowed_host, blocked_host], stdout=os.devnull, stderr=os.devnull).returncode:
        fail(4, "egress_policy_probe_failed")
    clean = """import json
from pathlib import Path
assert len(list(Path('/opt/nothingness/media').glob('*.opus'))) == 10
assert len(json.loads(Path('/opt/nothingness/media/manifest.json').read_text())) == 10
assert not any(Path('/run/nothingness/drive').iterdir())
assert not any((Path('/run/nothingness') / name).exists() for name in ('candidate.jsonl', 'candidate.stderr', 'candidate-completion.json', 'candidate-launcher.log', 'lifecycle.jsonl', 'progress.json', 'judge-control.sock'))
"""
    checks = (
        ["docker", "exec", container, "python3", "-c", clean],
        ["docker", "exec", container, "git", "-C", "/workspace", "diff", "--quiet"],
        ["docker", "exec", container, "git", "-C", "/workspace", "status", "--porcelain"],
        ["docker", "exec", container, "pgrep", "-f", "flutter run|dart.*main_debug"],
        ["docker", "exec", container, "sh", "-c", "probe=/workspace/linux/flutter/.nothingness-write-probe; mkdir \"$probe\" && rmdir \"$probe\""],
        ["docker", "exec", container, "/workspace/.claude/skills/agent-emulator-debugging/scripts/drive.py", "preflight"],
        ["docker", "exec", container, "flutter", "precache", "--linux"],
        ["docker", "exec", container, "sh", "-c", "temporary=$(mktemp -d); trap 'rm -rf \"$temporary\"' EXIT; cp -a /workspace/. \"$temporary\"; cd \"$temporary\"; flutter pub get --offline >/dev/null"],
    )
    results = [command(check, stdout=-1, stderr=os.devnull) for check in checks]
    if any(result.returncode for result in results[:2]) or results[2].stdout.strip() or results[3].returncode == 0 or any(result.returncode for result in results[4:]):
        fail(4, "container_state_not_clean")
    model = metadata["selected_model"]
    pi_config = read_host_pi_config(provider=model["provider"])
    if pi_config["config_fingerprints"] != metadata["pi"]["config_fingerprints"]:
        fail(4, "pi_config_changed")
    probe = command(
        ["docker", "exec", "-i", container, "python3", "/usr/local/bin/nothingness-eval-candidate", "--probe", "--provider", model["provider"], "--model", model["model"], "--thinking", model["thinking"], "--prompt", "unused", "--timeout-seconds", "60", "--run-id", run_id],
        input=__import__("json").dumps({"pi_config": pi_config["pi_config"], "provider_env": pi_config["provider_env"]}),
        stdout=-1,
        stderr=os.devnull,
    )
    probe_result = command(["docker", "exec", container, "cat", "/run/nothingness/admission/result.json"], stdout=-1, stderr=os.devnull)
    try:
        raw_admission = read_json_value(probe_result.stdout)
        usage = raw_admission.get("usage") if isinstance(raw_admission, dict) else None
        normalized = normalized_usage(usage)
        if probe.returncode or not raw_admission.get("ok") or not isinstance(usage, dict):
            raise ValueError
    except (ValueError, AttributeError):
        fail(4, "pi_admission_failed")
    admission = {"ok": True, "timestamp": utc_now(), "elapsed_ms": raw_admission["elapsed_ms"], "requested_model": metadata["requested_model"], "selected_model": model, "identity_verified": True, "config_fingerprints": metadata["pi"]["config_fingerprints"], "pi_version": metadata["pi"]["version"], "usage": usage, "normalized_usage": normalized}
    write_json(run / "admission.json", admission)
    command(["docker", "exec", container, "rm", "-rf", "/run/nothingness/admission", "/run/nothingness/pi-config"], stdout=os.devnull, stderr=os.devnull)
    if command(["docker", "exec", container, "python3", "-c", clean], stdout=os.devnull, stderr=os.devnull).returncode:
        fail(4, "candidate_artifacts_before_launch")
    result = {"ok": True, "run_id": run_id, "novnc_url": url, "health": "ready", "workspace": "clean", "flutter": "not_running", "candidate_artifacts": "absent", "capabilities": "dropped", "no_new_privileges": True, "network_policy": metadata["network_policy"], "egress_proxy": "verified", "admission": "passed"}
    write_json(run / "preflight.json", result)
    emit_json(result)


def read_json_value(value: str) -> object:
    import json
    return json.loads(value)


if __name__ == "__main__":
    main()