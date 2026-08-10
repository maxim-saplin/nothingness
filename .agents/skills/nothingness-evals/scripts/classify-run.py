from __future__ import annotations

import argparse
import hashlib
import json
import re
from pathlib import Path

from common import ROOT, emit_json, fail, read_json, run_dir, utc_now, validate_frozen_rubric, validate_model_identity, validate_run_id, write_json

VALIDITIES = ("valid", "invalid_infrastructure", "unassigned")
OUTCOMES = ("pass", "partial", "fail", "unassigned")
CREDIT = {"met": 1.0, "partial": 0.5, "unmet": 0.0}
TIERS = ("required", "secondary")
MAX_PENALIZED_INTERVENTIONS = 3
INTERVENTION_PENALTY_WEIGHT = 0.05

# Rubric convention (see evals/README.md "Scoring rubric" and evals/tasks/rubrics/*.md):
# a rubric is markdown with a "## Required expectations" section and a
# "## Secondary expectations" section, each containing one "### <id> — <title>"
# sub-heading per expectation, followed by the existing free-form
# **Statement:** / **Drive:** / **Confirms** / **Falsifies** structure plus one
# machine-readable declaration line: **Evidence:** verification|inspection|events
# — which judge-observations.jsonl `kind` may settle this expectation. Absent
# a declaration, an expectation defaults to `verification`: fail closed toward
# requiring eyes-on-the-app evidence rather than toward a weaker kind.
# `verification` may carry an optional lens qualifier naming exactly one of
# judge-verify.py's five captures (`**Evidence:** verification:screenshot`),
# for the rare expectation that is meaningless without that one specific
# capture (F2) — e.g. a screenshot expectation isn't settled by a runtime
# dump alone. Unqualified `verification` means "any one genuine capture",
# which stays correct for expectations multiple lenses can settle together.
# classify-run.py mechanically parses only the section membership (-> tier),
# the id token right after "### ", and the Evidence declaration; every prose
# statement, driving recipe, and falsification note stays free-form per the
# plan's principle 3 and is never parsed, only hashed.
SECTION_PATTERN = re.compile(r"^##\s+(Required|Secondary) expectations\s*$", re.MULTILINE)
EXPECTATION_HEADER_PATTERN = re.compile(r"^###\s+([A-Za-z0-9_-]+)\b", re.MULTILINE)
EVIDENCE_DECLARATION_PATTERN = re.compile(r"\*\*Evidence:\*\*\s*(verification|inspection|events)(?::([a-z]+))?\b")
VERIFICATION_LENSES = ("runtime", "tree", "semantics", "settings", "screenshot")


def score_band(adjusted: float) -> int:
    if adjusted >= 0.85:
        return 3
    if adjusted >= 0.60:
        return 2
    if adjusted >= 0.30:
        return 1
    return 0


def derive_outcome(score: int) -> str:
    if score == 3:
        return "pass"
    if score == 0:
        return "fail"
    return "partial"


def validate_classification(validity: str, outcome: str, score: int | None) -> None:
    if validity not in VALIDITIES or outcome not in OUTCOMES:
        fail(2, "invalid_classification")
    if score is not None and not 0 <= score <= 3:
        fail(2, "invalid_score")
    if validity != "valid":
        if outcome != "unassigned" or score is not None:
            fail(2, "invalid_run_cannot_have_outcome")
        return
    if outcome == "unassigned" or score is None:
        fail(2, "valid_run_requires_outcome_and_score")
    if outcome == "pass" and score != 3:
        fail(2, "pass_requires_score_three")
    if outcome == "fail" and score != 0:
        fail(2, "fail_requires_score_zero")
    if outcome == "partial" and score not in (1, 2):
        fail(2, "partial_requires_score_one_or_two")


def rubric_path_for_task(task_id: str) -> Path:
    return ROOT / "evals" / "tasks" / "rubrics" / f"{task_id}.md"


def rubric_expectations(path: Path) -> dict[str, dict[str, str | None]]:
    """Parse a rubric into {expectation_id: {"tier": ..., "evidence": ..., "lens": ...}}.

    `evidence` is the judge-observations.jsonl `kind` that may settle this
    expectation (D1): scoped to the text between this expectation's own
    header and the next one, so a declaration can never leak across
    expectations. Defaults to "verification" when absent. `lens` (F2) is an
    optional single capture name (`VERIFICATION_LENSES`) required for
    `verification`-kind expectations where one specific capture is
    self-evidently the whole point; `None` means any genuine capture suffices.
    """
    if not path.is_file():
        fail(2, "rubric_not_found")
    text = path.read_text(encoding="utf-8", errors="replace")
    sections = SECTION_PATTERN.split(text)
    expectations: dict[str, dict[str, str | None]] = {}
    for index in range(1, len(sections), 2):
        tier = sections[index].strip().lower()
        body = sections[index + 1]
        matches = list(EXPECTATION_HEADER_PATTERN.finditer(body))
        for position, match in enumerate(matches):
            identifier = match.group(1)
            if identifier in expectations:
                fail(2, "duplicate_expectation_id")
            block_end = matches[position + 1].start() if position + 1 < len(matches) else len(body)
            block = body[match.end():block_end]
            declared = EVIDENCE_DECLARATION_PATTERN.search(block)
            evidence = declared.group(1) if declared else "verification"
            lens = declared.group(2) if declared else None
            if lens is not None:
                if evidence != "verification":
                    fail(2, f"invalid_evidence_lens:{identifier}:lens_requires_verification")
                if lens not in VERIFICATION_LENSES:
                    fail(2, f"invalid_evidence_lens:{identifier}:unknown_lens_{lens}")
            expectations[identifier] = {"tier": tier, "evidence": evidence, "lens": lens}
    if not expectations:
        fail(2, "empty_rubric")
    return expectations


def load_scorecard_file(path: Path) -> tuple[str, str, object]:
    """Read the judge-authored scorecard file: the task id and rubric hash the
    judge actually read when writing verdicts, plus the raw expectations list.
    Both are compared against the run's live state in `main()` (D4) so a
    rubric edited, or a scorecard written against the wrong task, after the
    judge read it is rejected rather than silently accepted."""
    payload = read_json(path)
    if not isinstance(payload, dict):
        fail(2, "invalid_scorecard_file")
    task_id, rubric_sha256_value, expectations_payload = payload.get("task_id"), payload.get("rubric_sha256"), payload.get("expectations")
    if not isinstance(task_id, str) or not task_id or not isinstance(rubric_sha256_value, str) or not rubric_sha256_value or not isinstance(expectations_payload, list):
        fail(2, "invalid_scorecard_file")
    return task_id, rubric_sha256_value, expectations_payload


def validate_scorecard(scorecard: object, expectations: dict[str, dict[str, str]]) -> list[dict[str, object]]:
    if not isinstance(scorecard, list) or not scorecard:
        fail(2, "invalid_scorecard")
    seen: dict[str, str] = {}
    for item in scorecard:
        if not isinstance(item, dict):
            fail(2, "invalid_scorecard")
        identifier, tier, verdict, note, evidence_ref = (item.get("id"), item.get("tier"), item.get("verdict"), item.get("note"), item.get("evidence_ref"))
        if not isinstance(identifier, str) or identifier in seen:
            fail(2, "invalid_scorecard")
        if tier not in TIERS or verdict not in CREDIT:
            fail(2, "invalid_scorecard")
        if not isinstance(note, str) or not note.strip():
            fail(2, "invalid_scorecard")
        if not isinstance(evidence_ref, str) or not evidence_ref:
            fail(2, "invalid_scorecard")
        seen[identifier] = tier
    if seen != {identifier: value["tier"] for identifier, value in expectations.items()}:
        fail(2, "scorecard_rubric_mismatch")
    return scorecard


def validate_scorecard_evidence_kinds(run: Path, scorecard: list[dict[str, object]], expectations: dict[str, dict[str, str]], verified: dict[str, tuple[dict[str, object], dict[str, object]]]) -> None:
    """D1 + F2: each expectation's evidence_ref must resolve to a ledger
    observation of the exact kind that expectation's rubric entry declares —
    not merely *some* hash-verified observation of *any* kind (prevents e.g.
    an inspection/events observation settling a verification-only
    expectation). For `verification` entries, this now also checks the cited
    observation *itself*, not the aggregate `--observation-id` list (F2):
    citing a verification observation whose captures all failed, or whose
    only successful capture isn't the one lens the expectation actually
    needs (`**Evidence:** verification:<lens>`), is rejected by expectation id."""
    for item in scorecard:
        reference = verified.get(item["evidence_ref"])
        if reference is None:
            fail(2, f"scorecard_evidence_not_verified:{item['id']}")
        declaration = expectations[item["id"]]
        required_kind = declaration["evidence"]
        ledger_item = reference[0]
        if ledger_item.get("kind") != required_kind:
            fail(2, f"evidence_kind_mismatch:{item['id']}:requires_{required_kind}")
        # An `unmet` verdict is the one case where a capture that found nothing
        # is itself the evidence: when the candidate never launched the app,
        # "no live app in container" is exactly what proves the expectation
        # failed, and demanding a successful capture makes the single most
        # common weak-model outcome unscoreable. Credit still requires a real
        # capture of the declared lens, so absence can never buy a `met`.
        if required_kind == "verification" and item["verdict"] != "unmet":
            lens = declaration.get("lens")
            availability = ledger_item.get("availability")
            if lens is not None:
                if not isinstance(availability, dict) or not availability.get(lens):
                    fail(2, f"scorecard_evidence_not_captured:{item['id']}:requires_{lens}")
            elif not has_genuine_capture(ledger_item):
                fail(2, f"scorecard_evidence_not_captured:{item['id']}")


def compute_scorecard(scorecard: list[dict[str, object]], delivered_count: int) -> dict[str, object]:
    raw = sum(CREDIT[item["verdict"]] for item in scorecard) / len(scorecard)
    penalty = INTERVENTION_PENALTY_WEIGHT * min(delivered_count, MAX_PENALIZED_INTERVENTIONS)
    adjusted = round(min(1.0, max(0.0, raw - penalty)), 6)
    band = score_band(adjusted)
    required_unmet = any(item["tier"] == "required" and item["verdict"] == "unmet" for item in scorecard)
    score = min(band, 2) if required_unmet else band
    return {"raw": round(raw, 6), "penalty": round(penalty, 6), "adjusted": adjusted, "band": band, "required_unmet": required_unmet, "score": score, "outcome": derive_outcome(score)}


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


def has_genuine_capture(item: dict[str, object]) -> bool:
    """D2: a `kind: verification` ledger entry with a structurally valid
    manifest but zero successful captures (every drive.py call failed, or
    every capture was a content sentinel per judge-verify.py's own
    availability accounting) must not satisfy 'the judge looked'."""
    availability = item.get("availability")
    return isinstance(availability, dict) and any(bool(value) for value in availability.values())


def validate_judge_review(run: Path, completion: dict[str, object], observations: list[dict[str, object]], cited_ids: list[str], credited_refs: frozenset[str] = frozenset()) -> None:
    terminal = completion.get("terminal_event_sequence")
    if not isinstance(terminal, int) or terminal < 1:
        fail(2, "terminal_event_sequence_required")
    verified = verified_observations(run, observations)
    cited = set(cited_ids)
    if not cited:
        fail(2, "judge_review_required:cite observations with --observation-id (events, inspection and verification)")
    unverified = sorted(cited - set(verified))
    if unverified:
        fail(2, f"cited_observation_unverified:{','.join(unverified)} -- id absent from judge-observations.jsonl or its evidence file failed its sha256")
    coverage = 0
    event_ranges = []
    for observation_id in cited:
        item, evidence = verified[observation_id]
        if item.get("kind") == "events":
            observed_range = event_range(item, evidence)
            if observed_range is None:
                fail(2, f"event_observation_malformed:{observation_id} -- ledger range disagrees with the stored batch")
            event_ranges.append(observed_range)
    for after, next_sequence in sorted(event_ranges):
        if after != coverage or next_sequence <= after:
            fail(2, f"event_coverage_not_contiguous:expected_after={coverage},got_after={after},next={next_sequence} -- cite one events read per range, chained from 0")
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
    # "The judge looked" is satisfied either by a real capture, or by a capture
    # that honestly found nothing live and is used only to justify `unmet`
    # verdicts -- `credited_refs` carries every observation a met/partial verdict
    # leans on, and those still have to be genuine (see
    # validate_scorecard_evidence_kinds).
    verification_captured = any(
        item.get("kind") == "verification" and (has_genuine_capture(item) or observation_id not in credited_refs)
        for observation_id, (item, _evidence) in ((value, verified[value]) for value in cited)
    )
    if coverage != terminal:
        fail(2, f"event_coverage_incomplete:{coverage}/{terminal} -- page events again after judge-control.py finish, which appends its own terminal events")
    missing_lenses = sorted(name for name, present in inspections.items() if not present)
    if missing_lenses:
        fail(2, f"inspection_lenses_missing:{','.join(missing_lenses)} -- run judge-inspect.py --runtime --git --processes and cite it")
    missing_kinds = sorted({"events", "inspection", "verification"} - cited_kinds)
    if missing_kinds:
        fail(2, f"cited_observation_kinds_missing:{','.join(missing_kinds)} -- cite at least one observation of each kind")
    if not verification_captured:
        fail(2, "verification_capture_required -- every cited verification failed its captures and a met/partial verdict leans on it; only unmet verdicts may rest on a capture that found nothing")


def main() -> None:
    parser = argparse.ArgumentParser(allow_abbrev=False)
    parser.add_argument("run_id")
    parser.add_argument("--validity", required=True, choices=VALIDITIES)
    parser.add_argument("--scorecard")
    parser.add_argument("--notes")
    parser.add_argument("--observation-id", action="append", default=[])
    arguments = parser.parse_args()
    validate_run_id(arguments.run_id)
    run = run_dir(arguments.run_id)
    metadata = read_json(run / "run.json")
    # `selected_model` is only ever genuinely known once preflight's admission
    # probe has run: a run classified before that (invalid_infrastructure,
    # unassigned) legitimately has none yet, so there is nothing to compare
    # here for those. The real, non-tautological comparisons -- against the
    # admission probe's own served-model evidence, and separately against the
    # actual candidate session's own transcript -- happen below, gated to
    # `validity == "valid"` alongside every other valid-only evidence check.
    if arguments.validity == "valid" and metadata.get("selected_model") is not None:
        validate_model_identity(metadata["requested_model"], metadata["selected_model"])
    if arguments.validity != "valid" and arguments.scorecard:
        fail(2, "invalid_run_cannot_have_scorecard")
    if arguments.validity == "valid" and not arguments.scorecard:
        fail(2, "scorecard_required")
    required = (run / "admission.json", run / "summary.json", run / "interventions.json", run / "judge-observations.jsonl", run / "artifacts" / "candidate-completion.json", run / "artifacts" / "git-status.txt", run / "artifacts" / "lifecycle.jsonl", run / "artifacts" / "progress.json")
    if arguments.validity == "valid" and not all(path.is_file() for path in required):
        fail(2, "valid_score_evidence_required")
    summary = read_json(run / "summary.json") if (run / "summary.json").is_file() else None
    if arguments.validity == "valid" and (not isinstance(summary, dict) or not isinstance(summary.get("cost_usd"), dict) or set(summary["cost_usd"]) != {"admission", "candidate", "combined"} or not all(summary["cost_usd"][name] is None or isinstance(summary["cost_usd"][name], (int, float)) for name in ("admission", "candidate", "combined"))):
        fail(2, "complete_cost_required")
    admission = read_json(run / "admission.json") if (run / "admission.json").is_file() else None
    if arguments.validity == "valid" and (not isinstance(admission, dict) or not admission.get("identity_verified") or admission.get("requested_model") != metadata["requested_model"] or admission.get("selected_model") != metadata["selected_model"]):
        fail(2, "verified_admission_identity_required")
    # The admission probe only proves pi *could* serve the requested identity
    # moments before launch; it is not itself evidence about the scored
    # candidate session. summarize-run.py derives `model_identity_verified`
    # from the actual candidate transcript's own served-model evidence (every
    # `turn_end` message pi emitted during the real run) -- a candidate
    # session that never completed a turn, or that shows a different served
    # model than requested, must not be scored as identity-verified.
    if arguments.validity == "valid" and (not isinstance(summary, dict) or not summary.get("model_identity_verified")):
        fail(2, "verified_candidate_identity_required")
    interventions = read_json(run / "interventions.json") if (run / "interventions.json").is_file() else None
    authoritative = lifecycle_interventions(run / "artifacts" / "lifecycle.jsonl") if (run / "artifacts" / "lifecycle.jsonl").is_file() else {}
    delivered = delivered_interventions(interventions, authoritative) if arguments.validity == "valid" else set()
    completion = read_json(run / "artifacts" / "candidate-completion.json") if (run / "artifacts" / "candidate-completion.json").is_file() else None
    # `deadline_guard:` is the supervisor terminalizing a run just before its
    # wall so it stays scoreable. It is as valid as a judge finish -- the
    # candidate ran, its work is on disk, and the only thing it forfeits is
    # `pass`, enforced below via judge_finish_phase. Without this a candidate
    # that runs long produces no data point at all, which silently biases a
    # leaderboard against slower models rather than losing runs at random.
    completion_reason = str(completion.get("reason", "")) if isinstance(completion, dict) else ""
    accepted_completion = completion_reason.startswith("judge_finish:") or completion_reason.startswith("deadline_guard:")
    if arguments.validity == "valid" and (not isinstance(completion, dict) or completion.get("timed_out") or not accepted_completion):
        fail(2, "valid_candidate_completion_required")
    observations = []
    if (run / "judge-observations.jsonl").is_file():
        for line in (run / "judge-observations.jsonl").read_text(encoding="utf-8", errors="replace").splitlines():
            try:
                value = json.loads(line)
            except json.JSONDecodeError:
                continue
            if isinstance(value, dict):
                observations.append(value)
    outcome = "unassigned"
    score = None
    rubric_id = None
    rubric_sha256_value = None
    scorecard_entries = None
    computed = None
    if arguments.validity == "valid":
        if not arguments.notes:
            fail(2, "judge_review_and_rationale_required")
        scorecard_task_id, scorecard_rubric_sha256, raw_scorecard = load_scorecard_file(Path(arguments.scorecard))
        # Read the scorecard first: whether a capture that found nothing counts
        # as "the judge looked" depends on whether any verdict actually claims
        # credit from it, which is only knowable once the verdicts are in hand.
        credited_refs = frozenset(
            entry["evidence_ref"]
            for entry in raw_scorecard
            if isinstance(entry, dict) and isinstance(entry.get("evidence_ref"), str) and entry.get("verdict") != "unmet"
        )
        validate_judge_review(run, completion, observations, arguments.observation_id, credited_refs)
        if scorecard_task_id != metadata["task_id"]:
            fail(2, "scorecard_task_mismatch")
        rubric_path = rubric_path_for_task(metadata["task_id"])
        # F1: the authoritative rubric hash is the one prepare-run.py froze
        # into run.json *before the candidate ever saw the prompt*, not one
        # recomputed from disk right now — recomputing here and comparing
        # only against the scorecard's own self-declared field was circular,
        # since both values are written by the same actor at the same time.
        # validate_frozen_rubric also restores the clean `rubric_not_found`
        # error (F3) by checking existence before ever hashing.
        validate_frozen_rubric(metadata, rubric_path)
        rubric_sha256_value = metadata["rubric_contract"]["manifest_sha256"]
        if scorecard_rubric_sha256 != rubric_sha256_value:
            fail(2, "scorecard_rubric_hash_mismatch")
        expectations = rubric_expectations(rubric_path)
        scorecard_entries = validate_scorecard(raw_scorecard, expectations)
        verified = verified_observations(run, observations)
        validate_scorecard_evidence_kinds(run, scorecard_entries, expectations, verified)
        computed = compute_scorecard(scorecard_entries, len(delivered))
        outcome = computed["outcome"]
        score = computed["score"]
        if outcome == "pass" and completion.get("judge_finish_phase") != "awaiting_judge":
            fail(2, "passing_candidate_must_finish_naturally")
        rubric_id = rubric_path.stem
    validate_classification(arguments.validity, outcome, score)
    result = {
        "schema_version": 3,
        # Carried from `run.json` rather than re-read from the working tree: the
        # version that scored a run is the one it was prepared under, even if the
        # harness moved on mid-campaign.
        "eval_version": metadata.get("eval_version") or None,
        "run_id": arguments.run_id,
        "classified_at": utc_now(),
        "validity": arguments.validity,
        "outcome": outcome,
        "score": score,
        "notes": arguments.notes,
        "rationale_observation_ids": arguments.observation_id,
        "judge": metadata.get("judge") or None, "requested_model": metadata["requested_model"],
        "selected_model": metadata.get("selected_model"),
        # True only for a `valid` run whose admission probe AND whose actual
        # candidate transcript both independently confirmed pi served the
        # requested provider/model -- both checks above already exited before
        # this point if either was false or missing, so this is a genuine
        # derived fact by the time it's written, not an asserted one.
        "model_identity_verified": arguments.validity == "valid",
        "fixture_commit": metadata["fixture_commit"],
        "task_id": metadata["task_id"],
        "task_contract": metadata["task_contract"],
        "image": metadata["image"],
        "config_fingerprints": metadata["pi"]["config_fingerprints"],
        "admission": admission,
        "candidate": summary.get("candidate") if isinstance(summary, dict) else None,
        "cost_usd": summary.get("cost_usd") if isinstance(summary, dict) else None,
        "intervention_count": len(delivered),
        "assisted": bool(delivered),
        "evidence_complete": all(path.is_file() for path in required),
        "rubric_id": rubric_id,
        "rubric_sha256": rubric_sha256_value,
        "scorecard": scorecard_entries,
        "raw": computed["raw"] if computed else None,
        "penalty": computed["penalty"] if computed else None,
        "adjusted": computed["adjusted"] if computed else None,
    }
    write_json(run / "result.json", result)
    emit_json(result)


if __name__ == "__main__":
    main()
