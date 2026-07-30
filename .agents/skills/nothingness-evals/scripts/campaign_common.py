from __future__ import annotations

import fcntl
import hashlib
import json
import os
import re
import shutil
import tempfile
from contextlib import contextmanager
from datetime import UTC, datetime
from pathlib import Path
from typing import Any, Iterator

from common import IMAGE_NAME, ROOT, RUNS_ROOT, fail, load_suite, read_json, run_dir, sha256, utc_now, write_json

CAMPAIGNS_ROOT = ROOT / ".tmp" / "evals" / "campaigns"
CONTROLLER_VERSION = "1"
_PUBLICATION_ROOT: Path | None = None
EXPECTED_TASK_IDS = (
    "t1-playback-smoke-linux",
    "t2-settings-placement-linux",
    "t3-settings-placement-color-scheme-linux",
    "t4-swipe-to-seek-linux",
    "t5-jump-to-now-playing-linux",
    "t6-dot-song-info-hardening-linux",
    "t7-opus-shuffled-playlist-linux",
)
CAMPAIGN_ID_PATTERN = re.compile(
    r"^[A-Za-z0-9][A-Za-z0-9.-]*--[A-Za-z0-9][A-Za-z0-9.-]*--\d{8}T\d{6}Z$"
)
MAX_ATTEMPTS_PER_TASK = 3
DEFAULT_COST_CEILING_USD = 1.0
DEFAULT_TOKEN_CEILING = 5_000_000
TERMINAL_STATUSES = frozenset(
    {"completed", "blocked_infrastructure", "aborted_operator", "failed_evaluator"}
)
RESUMABLE_STATUSES = frozenset({"paused_budget", "cleanup_retrying", "prepared"})


def model_path_id(model: str) -> str:
    return model.replace("/", "--")


def validate_campaign_id(campaign_id: str) -> None:
    if not CAMPAIGN_ID_PATTERN.fullmatch(campaign_id):
        fail(2, "invalid_campaign_id")


def campaigns_root() -> Path:
    env = os.environ.get("NOTHINGNESS_EVAL_CAMPAIGNS_ROOT")
    if env:
        return Path(env)
    return CAMPAIGNS_ROOT


def campaign_dir(campaign_id: str) -> Path:
    validate_campaign_id(campaign_id)
    return campaigns_root() / campaign_id


def campaign_state_path(campaign_id: str) -> Path:
    return campaign_dir(campaign_id) / "campaign-state.json"


def campaign_lock_path(campaign_id: str) -> Path:
    return campaign_dir(campaign_id) / "campaign.lock"


def attempt_storage(campaign_id: str, task_id: str, attempt: int) -> Path:
    return campaign_dir(campaign_id) / "tasks" / task_id / f"attempt-{attempt:02d}"


def set_publication_root(path: Path | None) -> None:
    global _PUBLICATION_ROOT
    _PUBLICATION_ROOT = path


def publication_root() -> Path:
    env = os.environ.get("NOTHINGNESS_EVAL_PUBLICATION_ROOT")
    if env:
        return Path(env)
    return _PUBLICATION_ROOT if _PUBLICATION_ROOT is not None else ROOT / "evals"


def published_trial_dir(campaign_id: str, model_id: str, task_id: str) -> Path:
    return publication_root() / "results" / model_id / "campaigns" / campaign_id / task_id / "trial-1"


def archive_attempt_dir(campaign_id: str, task_id: str, attempt: int) -> Path:
    return publication_root() / "archive" / "evaluator-attempts" / campaign_id / task_id / f"attempt-{attempt:02d}"


def campaign_results_root(campaign_id: str, model_id: str) -> Path:
    return publication_root() / "results" / model_id / "campaigns" / campaign_id


def load_campaign_state(campaign_id: str) -> dict[str, Any]:
    path = campaign_state_path(campaign_id)
    if not path.is_file():
        fail(3, "campaign_not_found")
    state = read_json(path)
    if state.get("schema_version") != 1:
        fail(4, "unsupported_campaign_schema")
    if state.get("campaign_id") != campaign_id:
        fail(4, "campaign_id_mismatch")
    return state


@contextmanager
def campaign_lock(campaign_id: str) -> Iterator[None]:
    campaign_dir(campaign_id).mkdir(parents=True, exist_ok=True)
    lock_path = campaign_lock_path(campaign_id)
    with lock_path.open("w", encoding="utf-8") as handle:
        try:
            fcntl.flock(handle.fileno(), fcntl.LOCK_EX)
            yield
        finally:
            fcntl.flock(handle.fileno(), fcntl.LOCK_UN)


def save_campaign_state(state: dict[str, Any]) -> None:
    state["updated_at"] = utc_now()
    path = campaign_state_path(state["campaign_id"])
    path.parent.mkdir(parents=True, exist_ok=True)
    write_json(path, state)


def append_event(state: dict[str, Any], *, actor: str, reason: str, prior: str, new: str, **extra: object) -> None:
    state.setdefault("events", []).append(
        {
            "timestamp": utc_now(),
            "actor": actor,
            "reason": reason,
            "prior_status": prior,
            "new_status": new,
            **extra,
        }
    )


def transition_status(state: dict[str, Any], new_status: str, *, actor: str, reason: str, **extra: object) -> None:
    prior = state["status"]
    if prior in TERMINAL_STATUSES:
        fail(4, "campaign_already_terminal")
    append_event(state, actor=actor, reason=reason, prior=prior, new=new_status, **extra)
    state["status"] = new_status


def task_manifest_hashes() -> dict[str, str]:
    hashes: dict[str, str] = {}
    for task_id in EXPECTED_TASK_IDS:
        path = ROOT / "evals" / "tasks" / f"{task_id}.json"
        if not path.is_file():
            fail(2, f"task_not_found:{task_id}")
        hashes[task_id] = sha256(path)
    return hashes


def oracle_contract_path(task_id: str) -> Path:
    if task_id == "t1-playback-smoke-linux":
        fail(2, "t1_has_no_private_oracle_contract")
    return ROOT / "evals" / "private" / "oracles" / f"{task_id}.json"


def oracle_contract_hashes() -> dict[str, str]:
    hashes: dict[str, str] = {}
    for task_id in EXPECTED_TASK_IDS[1:]:
        path = oracle_contract_path(task_id)
        if not path.is_file():
            fail(2, f"oracle_contract_not_found:{task_id}")
        contract = read_json(path)
        if contract.get("status") != "frozen":
            fail(2, f"oracle_not_frozen:{task_id}")
        hashes[task_id] = sha256(path)
    return hashes


def validate_suite_for_campaign(suite_path: Path) -> dict[str, Any]:
    suite = load_suite(suite_path.resolve())
    task_ids = [item["id"] for item in suite["tasks"]]
    if task_ids != list(EXPECTED_TASK_IDS):
        fail(2, "campaign_suite_task_order")
    if any(item["valid_trials"] != 1 for item in suite["tasks"]):
        fail(2, "campaign_suite_requires_one_trial_per_task")
    task_manifest_hashes()
    oracle_contract_hashes()
    return suite


def parse_campaign_id(campaign_id: str, suite: dict[str, Any], model: dict[str, str]) -> None:
    validate_campaign_id(campaign_id)
    expected_prefix = f"{model_path_id(model['model'])}--{suite['id']}--"
    if not campaign_id.startswith(expected_prefix):
        fail(2, "campaign_id_model_suite_mismatch")


def build_initial_state(
    *,
    campaign_id: str,
    suite_path: Path,
    cost_ceiling_usd: float,
    token_ceiling: int,
) -> dict[str, Any]:
    suite = validate_suite_for_campaign(suite_path)
    model = dict(suite["requested_model"])
    parse_campaign_id(campaign_id, suite, model)
    manifests = task_manifest_hashes()
    now = utc_now()
    tasks = []
    for index, task_id in enumerate(EXPECTED_TASK_IDS, start=1):
        tasks.append(
            {
                "id": task_id,
                "ordinal": index,
                "status": "queued",
                "attempts": [],
                "published_path": None,
            }
        )
    return {
        "schema_version": 1,
        "campaign_id": campaign_id,
        "status": "prepared",
        "controller_version": CONTROLLER_VERSION,
        "suite": {
            "path": str(suite_path.resolve().relative_to(ROOT)),
            "id": suite["id"],
            "manifest_sha256": sha256(suite_path.resolve()),
            "task_ids": list(EXPECTED_TASK_IDS),
            "task_manifest_sha256": manifests,
            "oracle_contract_sha256": oracle_contract_hashes(),
        },
        "environment": {
            "fixture_commit": "5fc7e04",
            "image_name": IMAGE_NAME,
            "proxy_policy": "exact_host",
        },
        "model": {
            **model,
            "path_id": model_path_id(model["model"]),
        },
        "budget": {
            "candidate_admission_cost_ceiling_usd": cost_ceiling_usd,
            "token_ceiling": token_ceiling,
            "candidate_cost_usd": 0.0,
            "admission_cost_usd": 0.0,
            "combined_cost_usd": 0.0,
            "tokens": 0,
            "unknown_cost": False,
            "allow_unknown_cost": False,
            "overrides": [],
        },
        "current": {
            "task_index": 0,
            "task_id": EXPECTED_TASK_IDS[0],
            "attempt": 1,
            "run_id": None,
            "phase": "queued",
            "started_at": None,
            "cleanup_status": None,
        },
        "tasks": tasks,
        "events": [],
        "abort_requested": False,
        "invalid_attempt_count": 0,
        "created_at": now,
        "updated_at": now,
    }


def current_task(state: dict[str, Any]) -> dict[str, Any]:
    return state["tasks"][state["current"]["task_index"]]


def run_id_for(state: dict[str, Any], task_id: str, attempt: int, trial: int = 1) -> str:
    return f"{state['suite']['id']}-{task_id}-trial-{trial:02d}-attempt-{attempt:02d}"


def usage_from_result(result: dict[str, Any]) -> tuple[float | None, float | None, float | None, int, bool]:
    cost = result.get("cost_usd")
    candidate = admission = combined = None
    unknown = False
    if isinstance(cost, dict):
        candidate = cost.get("candidate")
        admission = cost.get("admission")
        combined = cost.get("combined")
        unknown = any(value is None for value in (candidate, admission, combined))
    tokens = 0
    candidate_usage = result.get("candidate")
    if isinstance(candidate_usage, dict):
        aggregate = candidate_usage.get("usage", {}).get("aggregate", {})
        if isinstance(aggregate, dict):
            token_block = aggregate.get("tokens")
            if isinstance(token_block, dict) and isinstance(token_block.get("total"), (int, float)):
                tokens += int(token_block["total"])
    admission_block = result.get("admission")
    if isinstance(admission_block, dict):
        normalized = admission_block.get("normalized_usage", {})
        if isinstance(normalized, dict):
            token_block = normalized.get("tokens")
            if isinstance(token_block, dict) and isinstance(token_block.get("total"), (int, float)):
                tokens += int(token_block["total"])
    return (
        float(candidate) if isinstance(candidate, (int, float)) else None,
        float(admission) if isinstance(admission, (int, float)) else None,
        float(combined) if isinstance(combined, (int, float)) else None,
        tokens,
        unknown,
    )


def apply_result_costs(state: dict[str, Any], result: dict[str, Any]) -> None:
    candidate, admission, combined, tokens, unknown = usage_from_result(result)
    budget = state["budget"]
    if candidate is not None:
        budget["candidate_cost_usd"] = round(budget["candidate_cost_usd"] + candidate, 8)
    if admission is not None:
        budget["admission_cost_usd"] = round(budget["admission_cost_usd"] + admission, 8)
    if combined is not None:
        budget["combined_cost_usd"] = round(budget["combined_cost_usd"] + combined, 8)
    elif candidate is not None and admission is not None:
        budget["combined_cost_usd"] = round(budget["candidate_cost_usd"] + budget["admission_cost_usd"], 8)
    budget["tokens"] = int(budget["tokens"]) + tokens
    if unknown:
        budget["unknown_cost"] = True


def budget_exceeded(state: dict[str, Any]) -> bool:
    budget = state["budget"]
    if budget["tokens"] >= budget["token_ceiling"]:
        return True
    if budget["unknown_cost"] and not budget["allow_unknown_cost"]:
        return True
    if not budget["unknown_cost"] and budget["combined_cost_usd"] >= budget["candidate_admission_cost_ceiling_usd"]:
        return True
    return False


def verify_resume_fingerprints(state: dict[str, Any], suite_path: Path) -> None:
    if sha256(suite_path.resolve()) != state["suite"]["manifest_sha256"]:
        fail(4, "suite_manifest_changed")
    manifests = task_manifest_hashes()
    if manifests != state["suite"]["task_manifest_sha256"]:
        fail(4, "task_manifest_changed")
    oracle_hashes = oracle_contract_hashes()
    if oracle_hashes != state["suite"]["oracle_contract_sha256"]:
        fail(4, "oracle_contract_changed")


def cleanup_verified(run: Path) -> bool:
    cleanup = run / "cleanup.json"
    if not cleanup.is_file():
        return False
    payload = read_json(cleanup)
    return bool(payload.get("ok")) and payload.get("container_removed") is not False


def copy_tree(source: Path, destination: Path) -> None:
    if destination.exists():
        shutil.rmtree(destination)
    shutil.copytree(source, destination)


def atomic_publish(staging: Path, destination: Path) -> None:
    destination.parent.mkdir(parents=True, exist_ok=True)
    if destination.exists():
        fail(4, "publication_destination_exists")
    os.replace(staging, destination)
    directory = os.open(destination.parent, os.O_RDONLY)
    try:
        os.fsync(directory)
    finally:
        os.close(directory)


def stage_attempt_publication(
    *,
    run: Path,
    result: dict[str, Any],
    campaign_id: str,
    model_id: str,
    task_id: str,
    report_markdown: str,
) -> Path:
    destination = published_trial_dir(campaign_id, model_id, task_id)
    destination.parent.mkdir(parents=True, exist_ok=True)
    staging = Path(tempfile.mkdtemp(prefix=".publish-", dir=destination.parent))
    try:
        evidence = staging / "evidence"
        evidence.mkdir()
        artifacts = run / "artifacts"
        if artifacts.is_dir():
            for name in ("task-evidence.json", "git-status.txt", "health.json", "processes.json"):
                source = artifacts / name
                if source.is_file():
                    shutil.copy2(source, evidence / name)
            diff = artifacts / "candidate.diff"
            if diff.is_file():
                shutil.copy2(diff, evidence / "candidate.diff")
        write_json(staging / "result.json", result)
        (staging / "report.md").write_text(report_markdown, encoding="utf-8")
        cleanup = run / "cleanup.json"
        if cleanup.is_file():
            shutil.copy2(cleanup, staging / "cleanup.json")
        fingerprint = {
            "campaign_id": campaign_id,
            "task_id": task_id,
            "controller_version": CONTROLLER_VERSION,
            "suite_manifest_sha256": result.get("suite_manifest_sha256") or result.get("task_contract", {}).get("manifest_sha256"),
            "fixture_commit": result.get("fixture_commit"),
            "run_id": result.get("run_id"),
        }
        write_json(staging / "fingerprint.json", fingerprint)
        atomic_publish(staging, destination)
        return destination
    except BaseException:
        if staging.exists():
            shutil.rmtree(staging, ignore_errors=True)
        raise


def stage_invalid_archive(
    *,
    run: Path,
    result: dict[str, Any],
    campaign_id: str,
    task_id: str,
    attempt: int,
    report_markdown: str,
) -> Path:
    destination = archive_attempt_dir(campaign_id, task_id, attempt)
    staging = Path(tempfile.mkdtemp(prefix=".archive-", dir=destination.parent if destination.parent.exists() else None))
    try:
        write_json(staging / "result.json", result)
        (staging / "report.md").write_text(report_markdown, encoding="utf-8")
        cleanup = run / "cleanup.json"
        if cleanup.is_file():
            shutil.copy2(cleanup, staging / "cleanup.json")
        evidence = staging / "evidence"
        evidence.mkdir()
        artifacts = run / "artifacts"
        if artifacts.is_dir():
            for name in ("git-status.txt", "health.json"):
                source = artifacts / name
                if source.is_file():
                    shutil.copy2(source, evidence / name)
        digest = hashlib.sha256(json.dumps(result, sort_keys=True).encode()).hexdigest()
        write_json(staging / "seal.json", {"sha256": digest, "campaign_id": campaign_id, "task_id": task_id, "attempt": attempt})
        destination.parent.mkdir(parents=True, exist_ok=True)
        atomic_publish(staging, destination)
        return destination
    except BaseException:
        if staging.exists():
            shutil.rmtree(staging, ignore_errors=True)
        raise


def active_run_resources_absent(run_id: str | None) -> bool:
    if not run_id:
        return True
    run = run_dir(run_id)
    metadata_path = run / "run.json"
    if not metadata_path.is_file():
        return True
    metadata = read_json(metadata_path)
    container = metadata.get("container")
    if isinstance(container, str):
        from common import command
        import subprocess

        if command(["docker", "container", "inspect", container], stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL).returncode == 0:
            return False
    return cleanup_verified(run)


def campaign_elapsed_seconds(state: dict[str, Any]) -> int:
    try:
        started = datetime.fromisoformat(state["created_at"].replace("Z", "+00:00"))
    except (KeyError, ValueError):
        return 0
    return max(0, int((datetime.now(UTC) - started).total_seconds()))
