from __future__ import annotations

import argparse
import statistics
from pathlib import Path
from typing import Any

from common import ROOT, emit_json, fail, load_suite, read_json, run_dir, utc_now, validate_run_id, write_json


COHORT_FIELDS = ("task_id", "fixture_commit", "requested_model", "selected_model", "image", "config_fingerprints", "task_contract")


def consolidate_results(results: list[dict[str, Any]], required_trials: int) -> dict[str, Any]:
    if len(results) != required_trials or len({item.get("run_id") for item in results}) != required_trials:
        fail(2, "exact_distinct_valid_trials_required")
    if any(item.get("validity") != "valid" or not item.get("model_identity_verified") for item in results):
        fail(2, "valid_identity_verified_trials_required")
    reference = results[0]
    if any(any(item.get(field) != reference.get(field) for field in COHORT_FIELDS) for item in results[1:]):
        fail(2, "mixed_trial_cohort")
    trials = sorted(results, key=lambda item: read_json(run_dir(item["run_id"]) / "run.json").get("trial", 0))
    trial_numbers = [read_json(run_dir(item["run_id"]) / "run.json").get("trial") for item in trials]
    if trial_numbers != list(range(1, required_trials + 1)) or any(read_json(run_dir(item["run_id"]) / "run.json").get("calibration") for item in trials):
        fail(2, "canonical_trial_numbers_required")
    scores = [item["score"] for item in trials]
    outcomes = [item["outcome"] for item in trials]
    return {"schema_version": 1, "suite_id": read_json(run_dir(trials[0]["run_id"]) / "run.json")["suite_id"], "task_id": reference["task_id"], "requested_model": reference["requested_model"], "selected_model": reference["selected_model"], "trial_run_ids": [item["run_id"] for item in trials], "scores": scores, "outcomes": outcomes, "median_score": statistics.median(scores), "score_range": [min(scores), max(scores)], "unassisted_pass_rate": outcomes.count("unassisted_pass") / required_trials, "assisted_pass_rate": outcomes.count("assisted_pass") / required_trials, "stability": "stable" if len(set(scores)) == 1 else "mixed", "consolidated_at": utc_now()}


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("suite", type=Path)
    parser.add_argument("task_id")
    parser.add_argument("run_ids", nargs="+")
    arguments = parser.parse_args()
    suite = load_suite(arguments.suite.resolve())
    task = next((item for item in suite["tasks"] if item["id"] == arguments.task_id), None)
    if task is None:
        fail(2, "task_not_in_suite")
    for run_id in arguments.run_ids:
        validate_run_id(run_id)
    results = [read_json(run_dir(run_id) / "result.json") for run_id in arguments.run_ids]
    consolidated = consolidate_results(results, task["valid_trials"])
    output = ROOT / "evals" / "results" / suite["id"] / arguments.task_id / "consolidated.json"
    write_json(output, consolidated)
    emit_json({"ok": True, "output": str(output), "result": consolidated})


if __name__ == "__main__":
    main()