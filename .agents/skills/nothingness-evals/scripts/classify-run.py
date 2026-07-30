from __future__ import annotations

import argparse
import hashlib
import json
from pathlib import Path

from common import emit_json, fail, read_json, run_dir, utc_now, validate_model_identity, validate_run_id, write_json


def validate_classification(validity: str, outcome: str, score: int | None) -> None:
    if validity not in {"valid", "invalid_infrastructure", "unassigned"} or outcome not in {"unassisted_pass", "assisted_pass", "candidate_fail", "unassigned"}:
        fail(2, "invalid_classification")
    if score is not None and not 0 <= score <= 3:
        fail(2, "invalid_score")
    if validity != "valid" and (outcome != "unassigned" or score is not None):
        fail(2, "invalid_run_cannot_have_outcome")
    if validity == "valid":
        if outcome == "unassigned" or score is None:
            fail(2, "valid_run_requires_outcome_and_score")
        if outcome in {"unassisted_pass", "assisted_pass"} and score == 0:
            fail(2, "passing_outcome_requires_positive_score")
        if outcome == "candidate_fail" and score != 0:
            fail(2, "candidate_failure_requires_zero_score")


def lifecycle_interventions(path: Path) -> dict[str, str]:
    states: dict[str, str] = {}
    for line in path.read_text(encoding="utf-8", errors="replace").splitlines():
        try:
            record = json.loads(line)
        except json.JSONDecodeError:
            continue
        event = record.get("event") if isinstance(record, dict) and record.get("source") == "judge_intervention" else None
        if not isinstance(event, dict) or not isinstance(event.get("id"), str) or event.get("delivery") not in {"pending", "delivered", "failed"}:
            continue
        previous = states.get(event["id"])
        if previous in {"delivered", "failed"} and previous != event["delivery"]:
            fail(2, "conflicting_intervention_delivery")
        states[event["id"]] = event["delivery"]
    return states


def delivered_interventions(interventions: object, authoritative: dict[str, str]) -> set[str]:
    if not isinstance(interventions, list):
        fail(2, "invalid_intervention_log")
    host_ids: set[str] = set()
    for intervention in interventions:
        if not isinstance(intervention, dict) or not isinstance(intervention.get("id"), str) or intervention.get("delivery") != "delivered" or intervention["id"] in host_ids:
            fail(2, "unresolved_intervention_delivery")
        host_ids.add(intervention["id"])
    candidate_ids = {identifier for identifier, state in authoritative.items() if state == "delivered"}
    if host_ids != candidate_ids or set(authoritative) != candidate_ids:
        fail(2, "intervention_journal_mismatch")
    return candidate_ids


def verified_observations(run: Path, observations: list[dict[str, object]]) -> dict[str, tuple[dict[str, object], dict[str, object]]]:
    verified: dict[str, tuple[dict[str, object], dict[str, object]]] = {}
    for item in observations:
        observation_id = item.get("observation_id")
        relative = item.get("evidence")
        digest = item.get("sha256")
        if not all(isinstance(value, str) and value for value in (observation_id, relative, digest)):
            continue
        path = (run / relative).resolve()
        if not path.is_relative_to(run.resolve()) or not path.is_file() or hashlib.sha256(path.read_bytes()).hexdigest() != digest:
            continue
        evidence = read_json(path)
        if not isinstance(evidence, dict) or evidence.get("observation_id") != observation_id:
            continue
        verified[observation_id] = (item, evidence)
    return verified


def event_range(item: dict[str, object], evidence: dict[str, object]) -> tuple[int, int] | None:
    after = evidence.get("after")
    next_sequence = evidence.get("next_sequence")
    events = evidence.get("events")
    if not isinstance(after, int) or not isinstance(next_sequence, int) or not isinstance(events, list):
        return None
    sequences = [event.get("sequence") if isinstance(event, dict) else None for event in events]
    if sequences != list(range(after + 1, next_sequence + 1)):
        return None
    if item.get("after") != after or item.get("next_sequence") != next_sequence or item.get("event_count") != len(events):
        return None
    return after, next_sequence


def validate_judge_review(run: Path, completion: dict[str, object], observations: list[dict[str, object]], cited_ids: list[str]) -> None:
    terminal = completion.get("terminal_event_sequence")
    if not isinstance(terminal, int) or terminal < 1:
        fail(2, "terminal_event_sequence_required")
    verified = verified_observations(run, observations)
    cited = set(cited_ids)
    if not cited or not cited.issubset(verified):
        fail(2, "judge_review_and_rationale_required")
    coverage = 0
    event_ranges = []
    for observation_id in cited:
        item, evidence = verified[observation_id]
        if item.get("kind") == "events":
            observed_range = event_range(item, evidence)
            if observed_range is None:
                fail(2, "judge_review_and_rationale_required")
            event_ranges.append(observed_range)
    for after, next_sequence in sorted(event_ranges):
        if after != coverage or next_sequence <= after:
            fail(2, "judge_review_and_rationale_required")
        coverage = next_sequence
    inspections = {
        name: any(
            observation_id in cited
            and item.get("kind") == "inspection"
            and item.get(name) is True
            and name in evidence
            for observation_id, (item, evidence) in verified.items()
        )
        for name in ("runtime", "git", "processes")
    }
    cited_kinds = {verified[value][0].get("kind") for value in cited}
    if coverage != terminal or not all(inspections.values()) or not {"events", "inspection"}.issubset(cited_kinds):
        fail(2, "judge_review_and_rationale_required")


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("run_id")
    parser.add_argument("--validity", required=True, choices=("valid", "invalid_infrastructure", "unassigned"))
    parser.add_argument("--outcome", required=True, choices=("unassisted_pass", "assisted_pass", "candidate_fail", "unassigned"))
    parser.add_argument("--score", type=int)
    parser.add_argument("--notes")
    parser.add_argument("--observation-id", action="append", default=[])
    arguments = parser.parse_args()
    validate_run_id(arguments.run_id)
    run = run_dir(arguments.run_id)
    metadata = read_json(run / "run.json")
    validate_model_identity(metadata["requested_model"], metadata["selected_model"])
    validate_classification(arguments.validity, arguments.outcome, arguments.score)
    required = (run / "admission.json", run / "summary.json", run / "interventions.json", run / "judge-observations.jsonl", run / "artifacts" / "candidate-completion.json", run / "artifacts" / "git-status.txt", run / "artifacts" / "task-evidence.json", run / "artifacts" / "lifecycle.jsonl", run / "artifacts" / "progress.json")
    if arguments.validity == "valid" and not all(path.is_file() for path in required):
        fail(2, "valid_score_evidence_required")
    summary = read_json(run / "summary.json") if (run / "summary.json").is_file() else None
    task_evidence = read_json(run / "artifacts" / "task-evidence.json") if (run / "artifacts" / "task-evidence.json").is_file() else None
    if arguments.validity == "valid" and not isinstance(task_evidence, dict):
        fail(2, "task_oracle_required")
    if arguments.validity == "valid" and arguments.outcome in {"unassisted_pass", "assisted_pass"} and not task_evidence.get("passed"):
        fail(2, "task_oracle_pass_required")
    if arguments.validity == "valid" and arguments.outcome == "candidate_fail" and task_evidence.get("passed"):
        fail(2, "passing_oracle_cannot_be_candidate_failure")
    if arguments.validity == "valid" and (not isinstance(summary, dict) or not isinstance(summary.get("cost_usd"), dict) or set(summary["cost_usd"]) != {"admission", "candidate", "combined"} or not all(summary["cost_usd"][name] is None or isinstance(summary["cost_usd"][name], (int, float)) for name in ("admission", "candidate", "combined"))):
        fail(2, "complete_cost_required")
    admission = read_json(run / "admission.json") if (run / "admission.json").is_file() else None
    if arguments.validity == "valid" and (not isinstance(admission, dict) or not admission.get("identity_verified") or admission.get("requested_model") != metadata["requested_model"] or admission.get("selected_model") != metadata["selected_model"]):
        fail(2, "verified_admission_identity_required")
    interventions = read_json(run / "interventions.json") if (run / "interventions.json").is_file() else None
    authoritative = lifecycle_interventions(run / "artifacts" / "lifecycle.jsonl") if (run / "artifacts" / "lifecycle.jsonl").is_file() else {}
    delivered = delivered_interventions(interventions, authoritative) if arguments.validity == "valid" else set()
    if arguments.validity == "valid" and arguments.outcome == "unassisted_pass" and delivered:
        fail(2, "unassisted_pass_has_interventions")
    if arguments.validity == "valid" and arguments.outcome == "assisted_pass" and not delivered:
        fail(2, "assisted_pass_requires_intervention")
    completion = read_json(run / "artifacts" / "candidate-completion.json") if (run / "artifacts" / "candidate-completion.json").is_file() else None
    if arguments.validity == "valid" and (not isinstance(completion, dict) or completion.get("timed_out") or not str(completion.get("reason", "")).startswith("judge_finish:")):
        fail(2, "valid_candidate_completion_required")
    if arguments.validity == "valid" and arguments.outcome in {"unassisted_pass", "assisted_pass"} and completion.get("judge_finish_phase") != "awaiting_judge":
        fail(2, "passing_candidate_must_finish_naturally")
    observations = []
    if (run / "judge-observations.jsonl").is_file():
        for line in (run / "judge-observations.jsonl").read_text(encoding="utf-8", errors="replace").splitlines():
            try:
                value = json.loads(line)
            except json.JSONDecodeError:
                continue
            if isinstance(value, dict):
                observations.append(value)
    if arguments.validity == "valid":
        if not arguments.notes:
            fail(2, "judge_review_and_rationale_required")
        validate_judge_review(run, completion, observations, arguments.observation_id)
    result = {"schema_version": 2, "run_id": arguments.run_id, "classified_at": utc_now(), "validity": arguments.validity, "outcome": arguments.outcome, "score": arguments.score, "notes": arguments.notes, "rationale_observation_ids": arguments.observation_id, "requested_model": metadata["requested_model"], "selected_model": metadata["selected_model"], "model_identity_verified": True, "fixture_commit": metadata["fixture_commit"], "task_id": metadata["task_id"], "task_contract": metadata["task_contract"], "image": metadata["image"], "config_fingerprints": metadata["pi"]["config_fingerprints"], "admission": read_json(run / "admission.json") if (run / "admission.json").is_file() else None, "candidate": summary.get("candidate") if isinstance(summary, dict) else None, "cost_usd": summary.get("cost_usd") if isinstance(summary, dict) else None, "intervention_count": len(delivered), "unassisted": not delivered, "evidence_complete": all(path.is_file() for path in required)}
    write_json(run / "result.json", result)
    emit_json(result)


if __name__ == "__main__":
    main()