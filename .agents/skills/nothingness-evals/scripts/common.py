from __future__ import annotations

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
RUNS_ROOT = ROOT / ".tmp" / "evals"
IMAGE_NAME = os.environ.get("NOTHINGNESS_EVAL_IMAGE", "nothingness-eval:t1")
HOSTNAME_PATTERN = re.compile(
    r"(?=.{1,253}\Z)(?:[A-Za-z0-9](?:[A-Za-z0-9-]{0,61}[A-Za-z0-9])?\.)+[A-Za-z]{2,63}\.?"
)


def emit_json(value: dict[str, Any], *, stream: Any = sys.stdout) -> None:
    print(json.dumps(value, separators=(",", ":")), file=stream)


def fail(code: int, reason: str) -> None:
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


def pi_payload_root(executable: Path) -> Path:
    executable = executable.resolve()
    candidates = (executable.parent.parent / "libexec", executable.parent.parent)
    for candidate in candidates:
        if (candidate / "bin" / "pi").is_file():
            return candidate
    fail(3, "pi_payload_not_found")
    raise AssertionError("unreachable")


def resolve_pi() -> dict[str, str]:
    override = os.environ.get("PI_ARTIFACT")
    if override:
        artifact = Path(override).expanduser()
        payload = artifact / "libexec" if (artifact / "libexec" / "bin" / "pi").is_file() else artifact
        if not (payload / "bin" / "pi").is_file():
            fail(3, "invalid_PI_ARTIFACT")
    else:
        found = shutil.which("pi")
        if found is None:
            fail(3, "missing_command:pi")
        payload = pi_payload_root(Path(found))
    version = command_or_fail([str(payload / "bin" / "pi"), "--version"], 3, "pi_version_failed", stdout=subprocess.PIPE, stderr=subprocess.DEVNULL).stdout.strip()
    if not version:
        fail(3, "pi_version_missing")
    return {"payload": str(payload), "version": version}


def host_pi_config_dir() -> Path:
    return Path(os.environ.get("PI_CODING_AGENT_DIR", "~/.pi/agent")).expanduser()


def pi_package_roots(config_dir: Path | None = None) -> tuple[Path, Path]:
    directory = config_dir or host_pi_config_dir()
    roots = (directory / "npm", directory / "git")
    if not all(root.is_dir() and not root.is_symlink() for root in roots):
        fail(3, "pi_package_cache_missing")
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


def validate_pi_model(payload: str, requested: dict[str, str]) -> None:
    listing = command_or_fail(
        [str(Path(payload) / "bin" / "pi"), "--offline", "--list-models", requested["model"]],
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
    if not isinstance(tasks, list) or not tasks or not all(isinstance(item, dict) and isinstance(item.get("id"), str) and isinstance(item.get("valid_trials"), int) and item["valid_trials"] > 0 for item in tasks):
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