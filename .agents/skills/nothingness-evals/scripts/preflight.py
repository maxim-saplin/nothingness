from __future__ import annotations

import os
import sys
import time

from common import ROOT, command, emit_json, fail, read_host_pi_config, read_json, redact_text, run_dir, require_command, secret_values, utc_now, validate_frozen_rubric, validate_frozen_suite, validate_frozen_task, validate_run_id, wait_for_desktop_ready, write_json
from usage import normalized_usage


NOVNC_READY_POLLS = 30
NOVNC_READY_INTERVAL = 0.5


def validate_pre_admission_contract(metadata: dict[str, object], root: object = ROOT) -> None:
    validate_frozen_suite(metadata, root)
    validate_frozen_task(metadata, root / "evals" / "tasks" / f"{metadata['task_id']}.json")
    validate_frozen_rubric(metadata, root / "evals" / "tasks" / "rubrics" / f"{metadata['task_id']}.md")


def admission_failure_detail(raw_admission: dict[str, object]) -> str:
    """Surface whatever the probe itself captured about a genuine provider
    rejection -- pi's own exit code / stop reason / final text, exactly the
    fields `candidate.py`'s `run_probe` writes onto `result.json` when the
    request completed but didn't qualify as `ok`. When none of those are
    present, the probe hit its except branch (subprocess timeout or an
    undecodable event stream) before it ever got that far."""
    parts = [f"{name}={raw_admission[name]!r}" for name in ("exit_code", "stop_reason", "text") if name in raw_admission]
    return ",".join(parts) if parts else "probe_timed_out_or_output_undecodable"


def evaluate_admission_probe(probe: object, probe_result: object, secrets: tuple[str, ...] = ()) -> tuple[dict[str, object], dict[str, object], dict[str, object]]:
    """Replaces the old single `pi_admission_failed` catch-all with the
    distinct causes an operator actually needs to tell apart: our own exec of
    the probe crashing, `result.json` being absent or corrupt, pi's own
    provider genuinely rejecting the request (`ok: false` -- the one case
    that really means "check Azure config/quota"), and our own probe contract
    being violated (`usage`/`served_model` missing or malformed -- never the
    provider's fault; this is exactly the defect class a stale image with an
    older `candidate.py` produces, now caught here as a second line of
    defense behind Part 1's build-time hash check)."""
    if probe.returncode:
        # The probe crashing on our side (a staging bug, a missing path) is
        # indistinguishable from a provider rejection unless its own error comes
        # with it -- an opaque `exit=1` cost hours once. The probe handles
        # credentials, so the tail is redacted with the same secret set the
        # artifact scanner uses, and bounded rather than dumped whole.
        detail = redact_text((probe.stderr or "").strip(), secrets).splitlines()
        suffix = f" -- {detail[-1][:300]}" if detail else ""
        fail(4, f"admission_probe_process_failed:exit={probe.returncode}{suffix}")
    if probe_result.returncode:
        fail(4, "admission_result_missing")
    try:
        raw_admission = read_json_value(probe_result.stdout)
    except (ValueError, TypeError):
        fail(4, "admission_result_unparseable")
    if not isinstance(raw_admission, dict):
        fail(4, "admission_result_unparseable")
    if not raw_admission.get("ok"):
        fail(4, f"admission_rejected:{admission_failure_detail(raw_admission)}")
    usage = raw_admission.get("usage")
    if not isinstance(usage, dict):
        fail(4, "admission_usage_missing")
    served = raw_admission.get("served_model")
    if not (isinstance(served, dict) and isinstance(served.get("provider"), str) and isinstance(served.get("model"), str)):
        fail(4, "admission_served_model_missing")
    return raw_admission, usage, served


def served_model_matches(requested: dict[str, object], served: object) -> bool:
    """The one genuine identity check the admission probe can make: does the
    provider/model pi's own response reported (`served`, straight off the
    "provider"/"model" fields on its assistant message -- see
    candidate.py's run_probe) match what we asked it to run? `thinking` is
    deliberately excluded: it is a request-time parameter pi's event stream
    never echoes back, so there is nothing to compare it against."""
    return isinstance(served, dict) and served.get("provider") == requested.get("provider") and served.get("model") == requested.get("model")


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
    # There is nothing to compare `selected_model` against yet: prepare-run.py
    # correctly leaves it `None` because no pi call has happened. The genuine
    # comparison happens below, once the admission probe returns pi's own
    # account of what it served.
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
    wait_for_desktop_ready(container, polls=60, interval=0.5, label="desktop_not_ready")
    # noVNC binds its port slightly after the desktop reports healthy, so a single
    # probe here throws away the several minutes prepare-run.py already spent on
    # fixture export, container, network and proxy setup -- for a race that clears
    # in a second. Retry on the same budget as the health loop above.
    # The timeouts are as important as the retry: a published port that accepts the
    # connection but never answers (as a misconfigured proxy does) hangs curl on the
    # OS TCP timeout, so an unbounded call here turns a retry loop into a multi-minute
    # stall -- which is exactly how this failure first presented.
    for poll in range(NOVNC_READY_POLLS):
        if command(["curl", "--fail", "--silent", "--connect-timeout", "2", "--max-time", "2", "--output", os.devnull, url]).returncode == 0:
            break
        if poll + 1 == NOVNC_READY_POLLS:
            fail(4, "novnc_unreachable")
        time.sleep(NOVNC_READY_INTERVAL)
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
        # `.agents/skills` is canonical; `.claude` is only a symlink to it. Reach
        # for the real path so this keeps working if the symlink ever goes.
        ["docker", "exec", container, "/workspace/.agents/skills/agent-emulator-debugging/scripts/drive.py", "preflight"],
    )
    results = [command(check, stdout=-1, stderr=os.devnull) for check in checks]
    if any(result.returncode for result in results[:2]) or results[2].stdout.strip() or results[3].returncode == 0 or any(result.returncode for result in results[4:]):
        fail(4, "container_state_not_clean")
    # `requested_model` is what we ask pi to run with -- there is no other
    # candidate value to pass, since we are the one choosing the flags. It is
    # NOT yet "the selected model": that term is reserved for what pi's own
    # response says it actually served, established below once the probe
    # returns.
    requested = metadata["requested_model"]
    pi_config = read_host_pi_config(provider=requested["provider"])
    if pi_config["config_fingerprints"] != metadata["pi"]["config_fingerprints"]:
        fail(4, "pi_config_changed")
    probe = command(
        ["docker", "exec", "-i", container, "python3", "/usr/local/bin/nothingness-eval-candidate", "--probe", "--provider", requested["provider"], "--model", requested["model"], "--thinking", requested["thinking"], "--prompt", "unused", "--timeout-seconds", "60", "--run-id", run_id],
        input=__import__("json").dumps({"pi_config": pi_config["pi_config"], "provider_env": pi_config["provider_env"]}),
        stdout=-1,
        stderr=-1,
    )
    probe_result = command(["docker", "exec", container, "cat", "/run/nothingness/admission/result.json"], stdout=-1, stderr=os.devnull)
    raw_admission, usage, served = evaluate_admission_probe(probe, probe_result, secret_values(pi_config["pi_config"], pi_config["provider_env"]))
    normalized = normalized_usage(usage)
    # This is the genuine identity check: `served` came back on pi's own
    # assistant message (its "provider"/"model" fields), independent of
    # anything we asked for. `thinking` has no analogous server confirmation
    # anywhere in pi's event stream (see candidate.py's run_probe), so it is
    # carried through from the request, not verified -- documented in
    # references/scoring.md and references/run-protocol.md rather than
    # silently claimed. A provider/model mismatch is infrastructure-invalid:
    # the harness asked for one model and something else answered.
    if not served_model_matches(requested, served):
        fail(4, "served_model_identity_mismatch")
    selected_model = {"provider": served["provider"], "model": served["model"], "thinking": requested["thinking"]}
    admission = {"ok": True, "timestamp": utc_now(), "elapsed_ms": raw_admission["elapsed_ms"], "requested_model": requested, "selected_model": selected_model, "served_model": served, "identity_verified": True, "config_fingerprints": metadata["pi"]["config_fingerprints"], "pi_version": metadata["pi"]["version"], "usage": usage, "normalized_usage": normalized}
    write_json(run / "admission.json", admission)
    # Persist the genuinely-discovered selected_model back into run.json: every
    # later stage of this run (launch-candidate.py, judge-control.py,
    # judge-verify.py, judge-events.py, judge-inspect.py, collect.py) reads
    # `selected_model` straight from run.json, not from admission.json.
    write_json(run / "run.json", {**metadata, "selected_model": selected_model})
    command(["docker", "exec", container, "rm", "-rf", "/run/nothingness/admission", "/run/nothingness/pi-config"], stdout=os.devnull, stderr=os.devnull)
    if command(["docker", "exec", container, "python3", "-c", clean], stdout=os.devnull, stderr=os.devnull).returncode:
        fail(4, "candidate_artifacts_before_launch")
    result = {"ok": True, "run_id": run_id, "novnc_url": url, "health": "ready", "workspace": "clean", "flutter": "not_running", "candidate_artifacts": "absent", "capabilities": "dropped", "no_new_privileges": True, "network_policy": metadata["network_policy"], "egress_proxy": "verified", "admission": "passed", "requested_model": requested, "selected_model": selected_model, "identity_verified": True}
    write_json(run / "preflight.json", result)
    emit_json(result)


def read_json_value(value: str) -> object:
    import json
    return json.loads(value)


if __name__ == "__main__":
    main()