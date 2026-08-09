from __future__ import annotations

import argparse
import contextlib
import io
import json
import subprocess
from pathlib import Path
from typing import Any

from common import IMAGE_NAME, PROVIDER_ENV_KEYS, command, derive_provider_egress_host, emit_json, fail, load_suite, pi_package_roots, read_host_pi_config, require_command, resolve_pi, validate_image_matches_sources, validate_pi_model


# Every check below is either a `common.py` helper that calls `fail()` (raises
# `SystemExit` with a reason on its own stderr, one JSON object per call) or a
# small local wrapper doing the same for a check `common.py` has no helper
# for (docker daemon reachability, provider env presence). `run()` lets every
# check execute regardless of earlier failures -- the whole point of this
# script is one pass reporting everything wrong, not the first-failure exit
# every underlying script gives a normal eval run.
# `ffmpeg`/`ffprobe` are as hard a requirement as docker: validate-opus-fixtures.py
# requires them, and prepare-run.py runs it before any container exists, so a host
# without them fails every run at the first start. Found the only way it could be --
# a cold run that check-host had just told was clean.
REQUIRED_COMMANDS = ("docker", "git", "tar", "uv", "pi", "ffmpeg", "ffprobe")


def extract_reason(stderr_text: str) -> str | None:
    lines = stderr_text.strip().splitlines()
    if not lines:
        return None
    try:
        return json.loads(lines[-1]).get("reason")
    except (json.JSONDecodeError, AttributeError):
        return None


def run(fn: Any) -> dict[str, Any]:
    buffer = io.StringIO()
    try:
        with contextlib.redirect_stderr(buffer):
            detail = fn()
        return {"status": "ok", "detail": "ok" if detail is None else detail}
    except SystemExit:
        return {"status": "fail", "detail": extract_reason(buffer.getvalue()) or "unknown_failure"}


def check_docker_daemon() -> str:
    require_command("docker")
    if command(["docker", "info"], stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL).returncode:
        fail(3, "docker_daemon_unreachable -- start the Docker daemon (e.g. `sudo systemctl start docker`, or open Docker Desktop)")
    return "reachable"


def check_provider_env(provider: str) -> dict[str, Any]:
    """`PROVIDER_ENV_KEYS` is an allowlist of what may be forwarded, not a list
    of what must be set -- most of it is optional, and the API key normally
    lives in `auth.json` rather than the environment. What a run genuinely
    needs is an egress hostname, so check exactly what `prepare-run.py` checks:
    that one is derivable."""
    config = read_host_pi_config(provider=provider)
    egress_host = derive_provider_egress_host(config["pi_config"]["models"], provider, config["provider_env"])
    present = [key for key in PROVIDER_ENV_KEYS.get(provider, ()) if key in config["provider_env"]]
    return {"provider": provider, "egress_host": egress_host, "env_vars_present": present}


def check_model_available(pi: dict[str, str], requested: dict[str, str]) -> dict[str, str]:
    validate_pi_model(pi, requested)
    return dict(requested)


def check_image() -> dict[str, Any]:
    inspect = command(["docker", "image", "inspect", IMAGE_NAME], stdout=subprocess.PIPE, stderr=subprocess.DEVNULL)
    if inspect.returncode:
        return {"present": False, "note": "no local image -- build with build-image.py (or verify-offline-baseline.py --build-image)"}
    labels = json.loads(inspect.stdout)[0].get("Config", {}).get("Labels") or {}
    buffer = io.StringIO()
    try:
        with contextlib.redirect_stderr(buffer):
            source_sha256 = validate_image_matches_sources(labels)
        return {"present": True, "current": True, "source_sha256": source_sha256}
    except SystemExit:
        # Staleness is normal build state, not a host misconfiguration -- report
        # it (with the same remediation `validate_image_matches_sources` already
        # embeds in its reason) without failing the overall health check.
        return {"present": True, "current": False, "note": extract_reason(buffer.getvalue()) or "image_stale_vs_sources"}


def main() -> None:
    parser = argparse.ArgumentParser(description="Report every host-setup problem blocking an eval in one pass, before any Docker build.")
    parser.add_argument("--suite", type=str)
    arguments = parser.parse_args()

    checks: dict[str, dict[str, Any]] = {}
    for name in REQUIRED_COMMANDS:
        checks[f"command:{name}"] = run(lambda cmd=name: require_command(cmd) or "on PATH")

    checks["docker_daemon"] = run(check_docker_daemon)
    docker_ok = checks["docker_daemon"]["status"] == "ok"

    pi_holder: dict[str, dict[str, str]] = {}

    def check_pi_resolve() -> dict[str, str]:
        pi_holder["value"] = resolve_pi()
        return pi_holder["value"]

    checks["pi_resolve"] = run(check_pi_resolve)
    pi_result = pi_holder.get("value")

    checks["pi_config"] = run(lambda: {"config_fingerprints": read_host_pi_config()["config_fingerprints"]})
    checks["pi_package_roots"] = run(lambda: {"present": [str(root) for root in pi_package_roots()]})

    if arguments.suite:
        suite_holder: dict[str, dict[str, Any]] = {}

        def check_suite() -> dict[str, Any]:
            suite_holder["value"] = load_suite(Path(arguments.suite))
            return {"id": suite_holder["value"]["id"], "requested_model": suite_holder["value"]["requested_model"]}

        checks["suite"] = run(check_suite)
        suite = suite_holder.get("value")
        if suite is not None:
            provider = suite["requested_model"]["provider"]
            checks["provider_env"] = run(lambda: check_provider_env(provider))
            if pi_result is not None:
                checks["model_available"] = run(lambda: check_model_available(pi_result, suite["requested_model"]))
            else:
                checks["model_available"] = {"status": "skip", "detail": "skipped: pi not resolved (see 'pi_resolve')"}
        else:
            checks["provider_env"] = {"status": "skip", "detail": "skipped: suite failed to load (see 'suite')"}
            checks["model_available"] = {"status": "skip", "detail": "skipped: suite failed to load (see 'suite')"}
    else:
        for name in ("suite", "provider_env", "model_available"):
            checks[name] = {"status": "skip", "detail": "no --suite given"}

    checks["image"] = run(check_image) if docker_ok else {"status": "skip", "detail": "skipped: docker unavailable (see 'docker_daemon')"}
    # A missing or stale image leaves `ok` true -- the host itself is fine -- but
    # it is still work the operator must do before a run, so it must not read as
    # "nothing to do": give it its own status and surface its note as an action.
    image_detail = checks["image"]["detail"]
    if isinstance(image_detail, dict) and not (image_detail.get("present") and image_detail.get("current")):
        checks["image"]["status"] = "action_required"

    ok = all(entry["status"] != "fail" for entry in checks.values())
    remediation: list[str] = []
    for entry in checks.values():
        if entry["status"] not in ("fail", "action_required"):
            continue
        detail = entry["detail"]
        text = detail.get("note", detail) if isinstance(detail, dict) else detail
        if isinstance(text, str) and " -- " in text:
            text = text.split(" -- ", 1)[1]
        if text not in remediation:
            remediation.append(text)

    emit_json({"ok": ok, "checks": checks, "remediation": remediation})
    raise SystemExit(0 if ok else 1)


if __name__ == "__main__":
    main()
