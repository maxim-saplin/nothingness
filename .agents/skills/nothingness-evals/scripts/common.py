from __future__ import annotations

import contextlib
import fcntl
import json
import os
import re
import hashlib
import shutil
import subprocess
import sys
import tempfile
from datetime import UTC, datetime
from pathlib import Path
from typing import Any
from urllib.parse import urlparse

SCRIPT_DIR = Path(__file__).resolve().parent
ROOT = Path(
    subprocess.run(
        ["git", "-C", str(SCRIPT_DIR), "rev-parse", "--show-toplevel"],
        check=True,
        stdout=subprocess.PIPE,
        text=True,
    ).stdout.strip()
)
# A judge is sandboxed in a git worktree so it cannot read `evals/results`, but
# the run it is scoring lives in the manager's tree -- `ROOT` alone would send it
# looking in `<worktree>/.tmp/evals/`, which no script ever creates, so its very
# first `observe` would fail. The manager points it here explicitly; the results
# tree stays `ROOT`-derived, so the isolation that matters is untouched.
RUNS_ROOT = Path(os.environ["NOTHINGNESS_EVAL_RUNS_ROOT"]).resolve() if os.environ.get("NOTHINGNESS_EVAL_RUNS_ROOT") else ROOT / ".tmp" / "evals"
GATE_STAMPS = RUNS_ROOT / "gate-stamps"
IMAGE_NAME = os.environ.get("NOTHINGNESS_EVAL_IMAGE", "nothingness-eval:t1")
# The files `build-image.py` actually bakes into the image (see its Dockerfile
# COPY list) -- everything the candidate/proxy/entrypoint run as code, plus
# the Dockerfile itself. `.dockerignore` and the media/dependency-seed/pi
# archives are build inputs, not code the image executes, so they are
# deliberately excluded from the staleness contract below.
IMAGE_SOURCE_FILES = ("Dockerfile", "entrypoint.py", "candidate.py", "egress_proxy.py", "pi.py")
IMAGE_SOURCE_HASH_LABEL = "nothingness.eval.source_sha256"
IMAGE_SOURCE_MANIFEST_LABEL = "nothingness.eval.source_manifest"
HOSTNAME_PATTERN = re.compile(
    r"(?=.{1,253}\Z)(?:[A-Za-z0-9](?:[A-Za-z0-9-]{0,61}[A-Za-z0-9])?\.)+[A-Za-z]{2,63}\.?"
)


def emit_json(value: dict[str, Any], *, stream: Any = None) -> None:
    print(json.dumps(value, separators=(",", ":")), file=sys.stdout if stream is None else stream)


# One-line fixes for reasons a human hits during setup, not mid-run. Keyed by
# either the full reason or the part before its first `:` (many of these carry
# a dynamic suffix, e.g. `missing_pi_config:models.json`), so `fail()` can
# append a concrete next step the same way `image_stale_vs_sources` already
# does by hand. Only cover reasons where there IS a single, real command to
# suggest -- not every failure has one.
SETUP_REMEDIATION: dict[str, str] = {
    "pi_payload_not_found": "install pi (npm i -g @earendil-works/pi-coding-agent) or set PI_ARTIFACT to its install dir",
    "invalid_PI_ARTIFACT": "point PI_ARTIFACT at a pi install dir containing bin/pi (or libexec/bin/pi), or a package.json with a bin.pi entry",
    "missing_command": "install the missing command and ensure it is on PATH",
    "missing_pi_config": "run `pi` once to generate ~/.pi/agent config, or set PI_CODING_AGENT_DIR to a directory with auth.json/models.json/settings.json",
    "invalid_pi_config": "fix the malformed JSON in the named file under ~/.pi/agent (or $PI_CODING_AGENT_DIR)",
    "unsafe_pi_config_permissions": "chmod 600 ~/.pi/agent/*.json",
    "requested_model_unavailable": "check available models: pi --offline --list-models <model>",
    "requested_thinking_unavailable": "pick a model/thinking combination pi actually supports: pi --offline --list-models <model>",
    "azure_provider_endpoint_missing": "set AZURE_OPENAI_BASE_URL or AZURE_OPENAI_RESOURCE_NAME in ~/.pi/agent/auth.json or the environment",
    "novnc_port_busy": "cleanup the previous task container (`judge-run.py cleanup <run-id>`) so the campaign port is free before starting the next run",
    "novnc_port_exhausted": "free a published eval port in 20000-39999, or stop the leftover campaign container holding one",
    "unsupported_container_arch": "harness gap, not a misconfiguration: add this `uname -m` value to FLUTTER_ARCH in verify-offline-baseline.py",
}


def fail(code: int, reason: str) -> None:
    remediation = SETUP_REMEDIATION.get(reason) or SETUP_REMEDIATION.get(reason.split(":", 1)[0])
    if remediation and " -- " not in reason:
        reason = f"{reason} -- {remediation}"
    emit_json({"ok": False, "reason": reason}, stream=sys.stderr)
    raise SystemExit(code)


def require_command(command: str) -> None:
    if shutil.which(command) is None:
        fail(3, f"missing_command:{command}")


def validate_run_id(run_id: str) -> None:
    if not re.fullmatch(r"[A-Za-z0-9_.-]+", run_id):
        fail(2, "invalid_run_id")


PI_CONFIG_FILES = ("auth.json", "models.json", "settings.json")
MAX_PI_CONFIG_BYTES = 1_048_576
PROVIDER_ENV_KEYS = {
    "azure-openai-responses": (
        "AZURE_OPENAI_API_KEY",
        "AZURE_OPENAI_BASE_URL",
        "AZURE_OPENAI_RESOURCE_NAME",
        "AZURE_OPENAI_API_VERSION",
        "AZURE_OPENAI_DEPLOYMENT_NAME_MAP",
    ),
}


def utc_now() -> str:
    return datetime.now(UTC).isoformat().replace("+00:00", "Z")


PI_BUNDLED_ENTRY = "bin/pi"


def pi_package_entry(root: Path) -> str | None:
    """The `bin.pi` entry of a package-manager install (npm/pnpm/bun global),
    relative to `root`. Pi ships as an npm package whose manifest points at
    `dist/cli.js`; there is no `bin/` directory to find."""
    manifest = root / "package.json"
    if not manifest.is_file():
        return None
    try:
        binaries = json.loads(manifest.read_text(encoding="utf-8")).get("bin")
    except (OSError, UnicodeDecodeError, json.JSONDecodeError):
        return None
    declared = binaries.get("pi") if isinstance(binaries, dict) else binaries
    if not isinstance(declared, str) or not declared:
        return None
    entry = Path(declared.lstrip("./"))
    if entry.is_absolute() or ".." in entry.parts or not (root / entry).is_file():
        return None
    return entry.as_posix()


def pi_payload_layout(root: Path) -> tuple[Path, str] | None:
    """`(payload root, node entry relative to it)` for one candidate directory,
    or None. Two layouts exist in the wild and the evaluator must not care
    which one the operator has: the bundled artifact (`bin/pi`, sometimes
    nested under `libexec/`) and a package-manager global install."""
    for base in (root / "libexec", root):
        if (base / PI_BUNDLED_ENTRY).is_file():
            return base, PI_BUNDLED_ENTRY
        entry = pi_package_entry(base)
        if entry is not None:
            return base, entry
    return None


def resolve_pi() -> dict[str, str]:
    override = os.environ.get("PI_ARTIFACT")
    if override:
        layout = pi_payload_layout(Path(override).expanduser())
        if layout is None:
            fail(3, "invalid_PI_ARTIFACT")
    else:
        found = shutil.which("pi")
        if found is None:
            fail(3, "missing_command:pi")
        executable = Path(found).resolve()
        layout = pi_payload_layout(executable.parent.parent) or pi_payload_layout(executable.parent.parent.parent)
        if layout is None:
            fail(3, "pi_payload_not_found")
    payload, entry = layout
    version = command_or_fail([str(payload / entry), "--version"], 3, "pi_version_failed", stdout=subprocess.PIPE, stderr=subprocess.DEVNULL).stdout.strip()
    if not version:
        fail(3, "pi_version_missing")
    return {"payload": str(payload), "entry": entry, "version": version}


def host_pi_config_dir() -> Path:
    return Path(os.environ.get("PI_CODING_AGENT_DIR", "~/.pi/agent")).expanduser()


def pi_package_roots(config_dir: Path | None = None) -> tuple[Path, ...]:
    """The pi package caches to freeze into the image. Either may be absent: pi
    only creates them once `pi install` has run, so a clean install legitimately
    has no packages at all and the candidate simply gets none."""
    directory = config_dir or host_pi_config_dir()
    roots = tuple(root for root in (directory / "npm", directory / "git") if root.exists())
    if not all(root.is_dir() and not root.is_symlink() for root in roots):
        fail(3, "unsafe_pi_package_root")
    for root in roots:
        for path in root.rglob("*"):
            if path.is_symlink():
                target = Path(os.readlink(path))
                resolved = (path.parent / target).resolve()
                if target.is_absolute() or not resolved.is_relative_to(root.resolve()):
                    fail(3, "unsafe_pi_package_symlink")
            elif not path.is_file() and not path.is_dir():
                fail(3, "unsafe_pi_package_file")
    return roots


def read_host_pi_config(config_dir: Path | None = None, provider: str | None = None) -> dict[str, Any]:
    directory = config_dir or host_pi_config_dir()
    contents: dict[str, str] = {}
    fingerprints: dict[str, str] = {}
    for name in PI_CONFIG_FILES:
        path = directory / name
        try:
            info = path.lstat()
        except OSError:
            fail(3, f"missing_pi_config:{name}")
        if path.is_symlink() or not path.is_file() or info.st_size > MAX_PI_CONFIG_BYTES:
            fail(3, f"unsafe_pi_config:{name}")
        if info.st_mode & 0o077:
            fail(3, f"unsafe_pi_config_permissions:{name}")
        try:
            content = path.read_text(encoding="utf-8")
            json.loads(content)
        except (OSError, UnicodeDecodeError, json.JSONDecodeError):
            fail(3, f"invalid_pi_config:{name}")
        contents[name.removesuffix(".json")] = content
        fingerprints[name] = hashlib.sha256(content.encode()).hexdigest()
    provider_env = provider_environment(contents["auth"], provider) if provider else {}
    fingerprints.update({f"env:{name}": hashlib.sha256(value.encode()).hexdigest() for name, value in provider_env.items()})
    return {"pi_config": contents, "provider_env": provider_env, "config_fingerprints": fingerprints}


def provider_environment(auth_json: str, provider: str, environ: dict[str, str] | None = None) -> dict[str, str]:
    allowed = PROVIDER_ENV_KEYS.get(provider, ())
    if not allowed:
        return {}
    auth = json.loads(auth_json)
    entry = auth.get(provider) if isinstance(auth, dict) else None
    configured = entry.get("env", {}) if isinstance(entry, dict) else {}
    process = os.environ if environ is None else environ
    result: dict[str, str] = {}
    for name in allowed:
        value = configured.get(name) if isinstance(configured, dict) else None
        if not isinstance(value, str) or not value:
            value = process.get(name)
        if isinstance(value, str) and value:
            result[name] = value
    return result


def _provider_nodes(value: Any, provider: str) -> list[dict[str, Any]]:
    matches: list[dict[str, Any]] = []
    if isinstance(value, dict):
        providers = value.get("providers")
        if isinstance(providers, dict) and isinstance(providers.get(provider), dict):
            matches.append(providers[provider])
        if value.get("name") == provider or value.get("id") == provider or value.get("provider") == provider:
            matches.append(value)
        for key, child in value.items():
            if key == provider and isinstance(child, dict):
                matches.append(child)
            matches.extend(_provider_nodes(child, provider))
    elif isinstance(value, list):
        for child in value:
            matches.extend(_provider_nodes(child, provider))
    return matches


def derive_egress_host(models_json: str, provider: str) -> str:
    try:
        models = json.loads(models_json)
    except json.JSONDecodeError:
        fail(3, "invalid_pi_config:models.json")
    hosts: set[str] = set()
    for node in _provider_nodes(models, provider):
        base_url = node.get("baseUrl", node.get("base_url"))
        if not isinstance(base_url, str):
            continue
        parsed = urlparse(base_url)
        host = (parsed.hostname or "").lower().rstrip(".")
        if parsed.scheme != "https" or not host or not HOSTNAME_PATTERN.fullmatch(host):
            fail(2, "invalid_provider_base_url")
        hosts.add(host)
    if len(hosts) != 1:
        fail(2, "ambiguous_or_missing_provider_base_url")
    return hosts.pop()


def derive_provider_egress_host(models_json: str, provider: str, provider_env: dict[str, str]) -> str:
    if provider == "azure-openai-responses":
        base_url = provider_env.get("AZURE_OPENAI_BASE_URL")
        resource = provider_env.get("AZURE_OPENAI_RESOURCE_NAME")
        if base_url:
            parsed = urlparse(base_url)
            host = (parsed.hostname or "").lower().rstrip(".")
            if parsed.scheme != "https" or not host or not HOSTNAME_PATTERN.fullmatch(host):
                fail(2, "invalid_provider_base_url")
            return host
        if resource and re.fullmatch(r"[A-Za-z0-9][A-Za-z0-9-]{0,62}", resource):
            return f"{resource.lower()}.openai.azure.com"
        fail(2, "azure_provider_endpoint_missing")
    return derive_egress_host(models_json, provider)


def validate_model_selection(models_json: str, provider: str, model: str) -> None:
    models = json.loads(models_json)
    matches = []
    for node in _provider_nodes(models, provider):
        configured = node.get("models")
        if isinstance(configured, list):
            matches.extend(item for item in configured if isinstance(item, dict))
    if not any(item.get("id") == model for item in matches):
        fail(2, "model_not_configured_for_provider")


def validate_model_identity(requested: dict[str, str], selected: dict[str, str]) -> None:
    required = {"provider", "model", "thinking"}
    if set(requested) != required or set(selected) != required:
        fail(2, "invalid_model_identity")
    if requested != selected:
        fail(2, "requested_model_mismatch")


def parse_pi_model_listing(output: str) -> list[dict[str, str]]:
    models = []
    for line in output.splitlines()[1:]:
        columns = line.split()
        if len(columns) >= 6:
            models.append({"provider": columns[0], "model": columns[1], "thinking": columns[4]})
    return models


def validate_pi_model(pi: dict[str, str], requested: dict[str, str]) -> None:
    listing = command_or_fail(
        [str(Path(pi["payload"]) / pi["entry"]), "--offline", "--list-models", requested["model"]],
        3,
        "pi_model_registry_failed",
        stdout=subprocess.PIPE,
        stderr=subprocess.DEVNULL,
    )
    matches = [item for item in parse_pi_model_listing(listing.stdout) if item["provider"] == requested["provider"] and item["model"] == requested["model"]]
    if len(matches) != 1:
        fail(2, "requested_model_unavailable")
    if requested["thinking"] != "off" and matches[0]["thinking"] != "yes":
        fail(2, "requested_thinking_unavailable")


def load_suite(path: Path) -> dict[str, Any]:
    path = path.resolve()
    suites_root = (ROOT / "evals" / "suites").resolve()
    if not path.is_relative_to(suites_root) or path.suffix != ".json":
        fail(2, "suite_manifest_must_be_committed")
    suite = read_json(path)
    if not isinstance(suite, dict) or suite.get("schema_version") != 1 or not isinstance(suite.get("id"), str):
        fail(2, "invalid_suite_manifest")
    model = suite.get("requested_model")
    tasks = suite.get("tasks")
    if not isinstance(model, dict) or set(model) != {"provider", "model", "thinking"} or not all(isinstance(value, str) and value for value in model.values()):
        fail(2, "invalid_suite_model")
    if not isinstance(tasks, list) or not tasks or not all(isinstance(item, dict) and isinstance(item.get("id"), str) and item["id"] for item in tasks):
        fail(2, "invalid_suite_tasks")
    validate_run_id(suite["id"])
    return suite


def validate_frozen_task(metadata: dict[str, Any], task_path: Path) -> None:
    contract = metadata.get("task_contract")
    if not isinstance(contract, dict) or sha256(task_path) != contract.get("manifest_sha256"):
        fail(4, "task_manifest_changed")
    current = read_json(task_path)
    expected = {name: contract.get(name) for name in ("id", "prompt", "limits", "platform_variant")}
    actual = {"id": current.get("id"), "prompt": current.get("prompt"), "limits": current.get("limits"), "platform_variant": current.get("platform_variant")}
    if actual != expected:
        fail(4, "frozen_task_mismatch")


def validate_frozen_rubric(metadata: dict[str, Any], rubric_path: Path) -> None:
    """Mirrors `validate_frozen_task`: `prepare-run.py` freezes the rubric's
    hash into `run.json["rubric_contract"]` before the candidate ever sees the
    prompt (F1) — a hash a scorer recomputes from disk at scoring time and
    compares against a value the scorecard declares about itself is circular,
    since both are written by the same actor at the same time. Distinguishes
    "no rubric on disk" (`2`, the task cannot be scored at all — the same
    clean error `classify-run.py` always gave for this case) from "the rubric
    that's there no longer matches what was frozen at prepare" (`4`, the same
    infrastructure-tamper class as `task_manifest_changed`)."""
    contract = metadata.get("rubric_contract")
    if not isinstance(contract, dict) or not isinstance(contract.get("manifest_sha256"), str):
        fail(4, "rubric_contract_missing")
    if not rubric_path.is_file():
        fail(2, "rubric_not_found")
    if sha256(rubric_path) != contract["manifest_sha256"]:
        fail(4, "rubric_manifest_changed")


def image_source_hashes(root: Path = ROOT) -> dict[str, str]:
    """Per-file sha256 of `evals/image/`'s baked-in sources, keyed by
    filename. This is the raw material both `build-image.py` (bakes it into
    image labels at build time) and `validate_image_matches_sources` (recomputes
    it from the working tree at prepare time) hash from -- kept as a
    dict-per-file rather than a single digest so a mismatch can name exactly
    which file drifted, not just "something did"."""
    directory = root / "evals" / "image"
    return {name: sha256(directory / name) for name in IMAGE_SOURCE_FILES}


def image_source_sha256(hashes: dict[str, str]) -> str:
    """Combines the per-file hashes into the single digest baked into the
    image label, in the fixed `IMAGE_SOURCE_FILES` order so the result is
    stable regardless of dict ordering."""
    digest = hashlib.sha256()
    for name in IMAGE_SOURCE_FILES:
        digest.update(f"{name}:{hashes[name]}\n".encode())
    return digest.hexdigest()


def validate_image_matches_sources(labels: dict[str, Any], root: Path = ROOT) -> str:
    """The fix for "nothing detects a stale image": mirrors
    `validate_frozen_task`/`validate_frozen_rubric` (the image's declared
    source hash was frozen into its labels at build time; this recomputes the
    same hash from the current `evals/image/` working tree and refuses to let
    a run proceed if they disagree), except the "manifest" being frozen is the
    image's own labels rather than a JSON file on disk. A missing label (an
    image built before this check existed, or with `build-image.py` bypassed)
    is treated the same as a mismatch -- there is no baseline to trust it
    against, so it fails closed rather than silently passing an unverifiable
    image. Returns the current source hash on success so the caller can record
    it in `run.json` without a second recomputation.
    """
    current_hashes = image_source_hashes(root)
    current_sha256 = image_source_sha256(current_hashes)
    baked_sha256 = labels.get(IMAGE_SOURCE_HASH_LABEL) if isinstance(labels, dict) else None
    if baked_sha256 == current_sha256:
        return current_sha256
    baked_manifest_raw = labels.get(IMAGE_SOURCE_MANIFEST_LABEL) if isinstance(labels, dict) else None
    try:
        baked_manifest = json.loads(baked_manifest_raw) if isinstance(baked_manifest_raw, str) else {}
    except json.JSONDecodeError:
        baked_manifest = {}
    if not isinstance(baked_manifest, dict):
        baked_manifest = {}
    differing = sorted(name for name in IMAGE_SOURCE_FILES if baked_manifest.get(name) != current_hashes.get(name))
    files = ",".join(differing) if differing else "unknown (image predates source verification)"
    fail(4, f"image_stale_vs_sources:{files} -- rebuild with: verify-offline-baseline.py --build-image")
    raise AssertionError("unreachable")


CHANGELOG_PATH = ROOT / "evals" / "CHANGELOG.md"
VERSION_HEADING = re.compile(r"^##\s+(\d+\.\d+\.\d+)\b")


def eval_version() -> str:
    """The harness version, read from the topmost heading in the changelog.

    Deliberately not a `VERSION` file: two places to edit is one place to
    forget, and a version nobody can trace to a change is worse than none. The
    changelog IS the source, so bumping the number and describing the change are
    the same edit. Recorded into every run at prepare time, so a published
    result says what it was produced by long after the tree has moved on."""
    if not CHANGELOG_PATH.is_file():
        fail(2, f"eval_changelog_missing:{CHANGELOG_PATH.relative_to(ROOT)} -- the harness version is read from its topmost '## <x.y.z>' heading")
    for line in CHANGELOG_PATH.read_text(encoding="utf-8").splitlines():
        match = VERSION_HEADING.match(line)
        if match:
            return match.group(1)
    fail(2, f"eval_version_not_found:{CHANGELOG_PATH.relative_to(ROOT)} -- add a '## <x.y.z> — <date>' heading at the top of the entries")
    raise AssertionError("unreachable")


def gate_fingerprint(image_id: str, fixture: str, script: Path) -> str:
    """What a gate pass is actually a statement about: this image, this fixture
    commit, and this gate's own code. Docker image ids are content-addressed, so
    any rebuild moves the first; nothing else a gate proves can change without
    one of the three changing too."""
    digest = hashlib.sha256()
    for part in (image_id, fixture, sha256(script), sha256(SCRIPT_DIR / "common.py")):
        digest.update(f"{part}\n".encode())
    return digest.hexdigest()


def passed_gate(gate: str, fingerprint: str) -> dict[str, Any] | None:
    """The previous pass for this exact fingerprint, or None.

    The two gates cost a container Linux release build and a full debug launch
    plus drive sequence -- together about ten minutes. They were re-proving the
    same unchanged image on every single eval, which was the largest chunk of
    dead time between "eval <model>" and the first task actually starting. A
    gate is a statement about an image, not about a wall clock: when the
    fingerprint matches, the proof still holds and re-running it buys nothing.
    """
    stamp = GATE_STAMPS / f"{gate}.json"
    if not stamp.is_file():
        return None
    try:
        recorded = read_json(stamp)
    except Exception:
        return None
    if not isinstance(recorded, dict) or recorded.get("fingerprint") != fingerprint:
        return None
    return recorded


def record_gate_pass(gate: str, fingerprint: str, result: dict[str, Any]) -> None:
    GATE_STAMPS.mkdir(parents=True, exist_ok=True)
    write_json(GATE_STAMPS / f"{gate}.json", {"gate": gate, "fingerprint": fingerprint, "passed_at": utc_now(), "result": result})


def validate_frozen_suite(metadata: dict[str, Any], root: Path = ROOT) -> None:
    suite_id = metadata.get("suite_id")
    if not isinstance(suite_id, str):
        fail(4, "frozen_suite_missing")
    path = root / "evals" / "suites" / f"{suite_id}.json"
    if not path.is_file() or sha256(path) != metadata.get("suite_manifest_sha256"):
        fail(4, "suite_manifest_changed")


def secret_values(pi_config: dict[str, str], provider_env: dict[str, str]) -> tuple[str, ...]:
    values: set[str] = set()
    sensitive = re.compile(r"(?:key|token|secret|password|authorization|cookie|credential)", re.IGNORECASE)

    def visit(value: Any, name: str = "", inherited_sensitive: bool = False) -> None:
        is_sensitive = inherited_sensitive or sensitive.search(name) is not None
        if isinstance(value, dict):
            for key, child in value.items():
                visit(child, str(key), is_sensitive)
        elif isinstance(value, list):
            for child in value:
                visit(child, name, is_sensitive)
        elif isinstance(value, str) and is_sensitive and len(value) >= 6:
            values.add(value)

    for content in pi_config.values():
        try:
            visit(json.loads(content))
        except json.JSONDecodeError:
            continue
    for name, value in provider_env.items():
        if sensitive.search(name) and len(value) >= 6:
            values.add(value)
    return tuple(sorted(values, key=len, reverse=True))


def redact_text(value: str, secrets: tuple[str, ...]) -> str:
    for secret in secrets:
        value = value.replace(secret, "[REDACTED]")
    return value


def redact_bytes(value: bytes, secrets: tuple[str, ...]) -> bytes:
    for secret in secrets:
        value = value.replace(secret.encode(), b"[REDACTED]")
    return value


def redact_value(value: Any, secrets: tuple[str, ...]) -> Any:
    if isinstance(value, str):
        return redact_text(value, secrets)
    if isinstance(value, list):
        return [redact_value(item, secrets) for item in value]
    if isinstance(value, dict):
        return {
            redact_text(key, secrets) if isinstance(key, str) else key: redact_value(item, secrets)
            for key, item in value.items()
        }
    return value


def validate_no_secret_leaks(root: Path, secrets: tuple[str, ...]) -> None:
    encoded = tuple(secret.encode() for secret in secrets)
    for path in root.rglob("*"):
        relative = path.relative_to(root).as_posix()
        if any(secret in relative for secret in secrets):
            fail(4, "secret_in_artifact_path")
        if path.is_file() and not path.is_symlink():
            try:
                value = path.read_bytes()
            except OSError:
                fail(4, "artifact_secret_scan_failed")
            if any(secret in value for secret in encoded):
                fail(4, "secret_in_artifact")


def run_dir(run_id: str) -> Path:
    return RUNS_ROOT / run_id


def docker_run_key(run_id: str) -> str:
    return hashlib.sha256(run_id.encode()).hexdigest()[:16]


def container_name(run_id: str) -> str:
    return f"nothingness-eval-{docker_run_key(run_id)}"


def proxy_name(run_id: str) -> str:
    return f"nothingness-eval-proxy-{docker_run_key(run_id)}"


def network_name(run_id: str) -> str:
    return f"nothingness-eval-net-{docker_run_key(run_id)}"


def read_json(path: Path) -> Any:
    try:
        return json.loads(path.read_text())
    except (OSError, json.JSONDecodeError):
        fail(3, f"invalid_json:{path}")


def task_scoring(task: dict[str, Any]) -> dict[str, Any]:
    scoring = task.get("scoring")
    if not isinstance(scoring, dict) or not isinstance(scoring.get("mode"), str):
        fail(2, "invalid_task_scoring")
    return scoring


def write_json(path: Path, value: dict[str, Any]) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    descriptor, temporary = tempfile.mkstemp(prefix=f".{path.name}.", dir=path.parent)
    try:
        with os.fdopen(descriptor, "w", encoding="utf-8") as output:
            output.write(json.dumps(value, separators=(",", ":")) + "\n")
            output.flush()
            os.fsync(output.fileno())
        os.replace(temporary, path)
        directory = os.open(path.parent, os.O_RDONLY)
        try:
            os.fsync(directory)
        finally:
            os.close(directory)
    finally:
        if os.path.exists(temporary):
            os.unlink(temporary)


def append_jsonl(path: Path, value: dict[str, Any]) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    with path.open("a", encoding="utf-8") as output:
        output.write(json.dumps(value, separators=(",", ":")) + "\n")
        output.flush()
        os.fsync(output.fileno())


@contextlib.contextmanager
def exclusive_lock(path: Path):
    """Hold an OS-level exclusive lock on `path` for the duration of the `with` block.

    Blocks concurrent holders (including other processes) rather than merely
    other threads, so a read-check-append-write sequence guarded by this lock
    is atomic across concurrent CLI invocations, not just within one process.
    """
    path.parent.mkdir(parents=True, exist_ok=True)
    with path.open("a+") as handle:
        fcntl.flock(handle.fileno(), fcntl.LOCK_EX)
        try:
            yield
        finally:
            fcntl.flock(handle.fileno(), fcntl.LOCK_UN)


def sha256(path: Path) -> str:
    digest = hashlib.sha256()
    with path.open("rb") as source:
        for chunk in iter(lambda: source.read(1024 * 1024), b""):
            digest.update(chunk)
    return digest.hexdigest()


def command(args: list[str], **kwargs: Any) -> subprocess.CompletedProcess[Any]:
    for stream in ("stdin", "stdout", "stderr"):
        if kwargs.get(stream) == os.devnull:
            kwargs[stream] = subprocess.DEVNULL
    kwargs.setdefault("text", True)
    return subprocess.run(args, check=False, **kwargs)


def command_or_fail(args: list[str], code: int, reason: str, **kwargs: Any) -> subprocess.CompletedProcess[Any]:
    result = command(args, **kwargs)
    if result.returncode:
        fail(code, reason)
    return result


NOVNC_PORT_MIN = 20000
NOVNC_PORT_SPAN = 20000


def novnc_preferred_port(seed: str) -> int:
    digest = int(hashlib.sha256(seed.encode("utf-8")).hexdigest()[:8], 16)
    return NOVNC_PORT_MIN + digest % NOVNC_PORT_SPAN


def format_novnc_url(port: int) -> str:
    return f"http://127.0.0.1:{port}/vnc.html?autoconnect=true&resize=scale"


def host_port_in_use(port: int) -> bool:
    return command(["curl", "--silent", "--connect-timeout", "2", "--max-time", "2", "--output", os.devnull, f"http://127.0.0.1:{port}/"]).returncode == 0


def allocate_campaign_novnc_port(campaign_id: str) -> int:
    port = novnc_preferred_port(campaign_id)
    ceiling = NOVNC_PORT_MIN + NOVNC_PORT_SPAN
    while host_port_in_use(port):
        port += 1
        if port >= ceiling:
            fail(3, "novnc_port_exhausted")
    return port


def command_or_fail_chained(args: list[str], code: int, reason: str, **kwargs: Any) -> subprocess.CompletedProcess[Any]:
    """Like `command_or_fail`, but `args` invokes ANOTHER harness script that
    itself calls `fail()` on error -- its real cause lands on ITS stderr as
    one `emit_json` object. Surfacing only the outer, generic `reason` (the
    caller's own label for "the sub-invocation failed") throws that cause
    away; this recovers it and chains it on as `reason:inner_reason`, falling
    back to the bare outer `reason` if stderr is missing, not JSON, or has no
    `reason` field.
    """
    kwargs.setdefault("stderr", subprocess.PIPE)
    result = command(args, **kwargs)
    if result.returncode:
        inner_reason = None
        stderr = result.stderr
        if isinstance(stderr, bytes):
            stderr = stderr.decode(errors="replace")
        if isinstance(stderr, str) and stderr.strip():
            try:
                inner_reason = json.loads(stderr.strip().splitlines()[-1]).get("reason")
            except (json.JSONDecodeError, AttributeError):
                inner_reason = None
        fail(code, f"{reason}:{inner_reason}" if isinstance(inner_reason, str) else reason)
    return result


# --- drive.py endpoint discovery --------------------------------------------
# Shared by judge-verify.py and judge-inspect.py, both of which drive the
# candidate's live app inside its container via `docker exec ... drive.py`.
# drive.py itself discovers the Dart VM service by scraping a `flutter run`
# log, defaulting to /tmp/flutter_run.log and overridable via $DRIVE_RUN_LOG
# (or its cached websocket URI, $DRIVE_WS_CACHE) -- but a candidate is free to
# launch `flutter run` logging anywhere else, which otherwise makes the judge
# structurally blind to a perfectly live, drivable app (the bug this closes).

DRIVE_DRIVER = "/workspace/.agents/skills/agent-emulator-debugging/scripts/drive.py"
DRIVE_DEFAULT_RUN_LOG = "/tmp/flutter_run.log"
DRIVE_NO_LIVE_APP_REASON = (
    f"no live app found in container: default discovery ({DRIVE_DEFAULT_RUN_LOG} "
    "and its cache) found no responsive Dart VM service, and scanning "
    "/tmp/flutter_run*.log for another live session also found none"
)


def drive_exec_args(container: str, env: dict[str, str], *arguments: str) -> list[str]:
    """Build the `docker exec [-e K=V ...] <container> python3 DRIVER <args>`
    argv that drives `drive.py` inside `container` with an env override
    (empty for none). Pure -- no subprocess call -- so each caller runs it
    through its OWN already-imported `command`, keeping each script's
    existing test-patching (`patch.object(<module>, "command", ...)`)
    working unchanged rather than requiring every test to patch a single
    shared `common.command`."""
    exec_args = ["docker", "exec"]
    for key, value in env.items():
        exec_args += ["-e", f"{key}={value}"]
    exec_args += [container, "python3", DRIVE_DRIVER, *arguments]
    return exec_args


def discover_drive_endpoint(container: str, run_command: Any) -> dict[str, object]:
    """Find a live app inside `container` before any drive.py capture runs.

    `run_command` is the CALLER's own `command`-shaped callable (same
    signature as `command()` above), injected rather than imported directly,
    so judge-verify.py and judge-inspect.py share this exact algorithm while
    each script's own tests keep patching their own module's `command` name
    instead of a shared one buried in this module.

    Strategy, cheapest first:
      1. Default discovery (no env override) -- works when the candidate used
         the documented convention, and also covers drive.py's own WS-cache
         fallback (it tries that internally when the default log has no URI).
      2. Scan for other `/tmp/flutter_run*.log` files, newest first, pointing
         DRIVE_RUN_LOG at each in turn. drive.py scopes its websocket cache
         per log path, so a stale cache from one candidate cannot leak into
         another.
    Every candidate is validated by an actual RPC round trip (a cheap `drive.py
    contract`, which only exits 0 when it can connect to the Dart VM service
    and enumerate the live isolate's registered extensions -- deliberately
    NOT a nothingness-specific payload check, so a live-but-content-odd app is
    never mistaken for a dead one), never by file presence alone -- a stale WS
    cache or a dead log both fail that check and get passed over, which is
    exactly the class of bug this closes.

    Returns the env overrides to use for every capture this invocation makes
    (so they stay consistent with each other), plus enough metadata for the
    caller's manifest to record how the endpoint was found: `method` is one
    of `default` (the default log itself carried a live URI), `cache` (the
    default log was absent/stale but drive.py's own cached websocket for it
    still answered), `scanned_log` (a non-default log was found and
    answered), or `unavailable` (nothing answered).
    """
    def alive(env: dict[str, str]) -> bool:
        # Exit code alone is not liveness. `drive.py contract` exits 0 whenever it can
        # reach the VM service at all, including against a half-initialized isolate
        # that has registered nothing and answers `{"count": 0, "extensions": []}`.
        # Accepting that endpoint makes discovery stop on a dead app and never scan
        # the log the candidate is actually using, so every later capture fails with
        # no obvious cause. Require a registered extension surface.
        result = run_command(drive_exec_args(container, env, "contract"), stdout=subprocess.PIPE, stderr=subprocess.DEVNULL)
        if result.returncode:
            return False
        try:
            payload = json.loads(result.stdout)
        except (json.JSONDecodeError, TypeError):
            return False
        return isinstance(payload, dict) and isinstance(payload.get("count"), int) and payload["count"] > 0

    def log_exists(log_path: str) -> bool:
        return run_command(["docker", "exec", container, "test", "-f", log_path], stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL).returncode == 0

    def candidate_logs() -> list[str]:
        listing = run_command(["docker", "exec", container, "sh", "-c", "ls -t /tmp/flutter_run*.log 2>/dev/null"], stdout=subprocess.PIPE, stderr=subprocess.DEVNULL)
        if listing.returncode:
            return []
        return [line.strip() for line in listing.stdout.splitlines() if line.strip()]

    if alive({}):
        if log_exists(DRIVE_DEFAULT_RUN_LOG):
            return {"ok": True, "env": {}, "method": "default", "log_path": DRIVE_DEFAULT_RUN_LOG}
        return {"ok": True, "env": {}, "method": "cache", "log_path": None}
    for log_path in candidate_logs():
        if log_path == DRIVE_DEFAULT_RUN_LOG:
            continue  # already tried above
        env = {"DRIVE_RUN_LOG": log_path}
        if alive(env):
            return {"ok": True, "env": env, "method": "scanned_log", "log_path": log_path}
    return {"ok": False, "env": {}, "method": "unavailable", "log_path": None}