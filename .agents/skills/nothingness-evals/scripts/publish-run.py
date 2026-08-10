"""Promote a judged run out of scratch into the committed results tree.

`.tmp/evals/<run-id>/` is working space: it holds the container's whole session,
including `candidate.jsonl`/`lifecycle.jsonl` that routinely run to hundreds of
megabytes. It is gitignored, so a run that stops there leaves no trace in the
repository and dies with the next `rm -rf .tmp`. That is what this script fixes.

Every judged run is copied to `evals/results/<model>/<task-id>/trial-N/`, the
layout `evals/README.md` already designates ("Consolidated, reviewed results
belong in results/, one directory per model") and that the committed
`gpt-5.4-nano` T1 trial already follows. Only durable evidence travels: the
verdict, the run contract, the judge's scorecard and observation ledger, the
candidate diff, the cited event reads (gzipped, since they are the bulky part),
and the judge's verification screenshots. The multi-hundred-megabyte raw session
logs stay in scratch on purpose — they are replay material, not results.

Idempotent: publishing the same run twice overwrites its own directory and
nothing else.
"""

from __future__ import annotations

import argparse
import gzip
import json
import shutil
from pathlib import Path

from common import ROOT, emit_json, fail, read_json, run_dir, validate_run_id, write_json

RESULTS_ROOT = ROOT / "evals" / "results"
# Copied verbatim when present; small, and each one is cited by a verdict.
# `notes.md` is the judge's own account of what the candidate did. It travels
# with the run so the report can read it, rather than being relayed as chat
# prose and pasted in by hand.
PLAIN_FILES = ("result.json", "run.json", "interventions.json", "judge-observations.jsonl", "summary.json", "notes.md")
# Anything at or above this size is stored gzipped rather than raw.
GZIP_THRESHOLD_BYTES = 256 * 1024


def run_slug(result: dict, prepared_at: str) -> str:
    """`<model>-<thinking>-<YYYYMMDD>` — what a human navigating the tree
    actually looks for.

    A run is a run: the same model re-run tomorrow, or judged by someone else,
    is a separate result and must land beside the old one rather than on top of
    it. Keying on model and thinking alone made the second run collide with the
    first and demand `--force` to overwrite committed results. The date comes
    from the run's own `prepared_at`, so the folder name is a fact about the run
    rather than about when someone got around to publishing it."""
    model = result.get("selected_model") or result.get("requested_model") or {}
    name = str(model.get("model") or "unknown-model")
    thinking = str(model.get("thinking") or "").strip()
    if thinking and thinking != "off":
        name = f"{name}-{thinking}"
    day = str(prepared_at)[:10].replace("-", "") or "unknown-date"
    return f"{name}-{day}".replace("/", "-").replace(" ", "-")


def copy_file(source: Path, destination: Path) -> dict:
    destination.parent.mkdir(parents=True, exist_ok=True)
    size = source.stat().st_size
    if size >= GZIP_THRESHOLD_BYTES:
        target = destination.with_suffix(destination.suffix + ".gz")
        with source.open("rb") as raw, gzip.open(target, "wb") as packed:
            shutil.copyfileobj(raw, packed)
    else:
        target = destination
        shutil.copy2(source, target)
    return {"path": str(target.relative_to(RESULTS_ROOT)), "bytes": target.stat().st_size, "gzipped": target != destination}


def cited_observation_ids(result: dict) -> set[str]:
    cited = set(result.get("rationale_observation_ids") or [])
    for entry in result.get("scorecard") or []:
        reference = entry.get("evidence_ref")
        if isinstance(reference, str):
            cited.add(reference)
    return cited


def occupant_run_id(destination: Path) -> str | None:
    """Which run already owns this directory, if any."""
    for name in ("published.json", "result.json"):
        candidate = destination / name
        if candidate.is_file():
            try:
                return read_json(candidate).get("run_id")
            except Exception:
                continue
    return None


def publish(run_id: str, scorecard: Path | None, force: bool) -> dict:
    run = run_dir(run_id)
    result_path = run / "result.json"
    if not result_path.is_file():
        fail(2, "judge_decision_required_before_publish")
    result = read_json(result_path)
    metadata = read_json(run / "run.json") if (run / "run.json").is_file() else {}
    trial = metadata.get("trial", 1)
    destination = RESULTS_ROOT / run_slug(result, str(metadata.get("prepared_at") or "")) / str(result.get("task_id") or "unknown-task") / f"trial-{trial}"
    # Dated slots make same-run republishing the only way two runs collide, so a
    # collision is a refresh rather than the data loss `--force` used to guard.
    if destination.exists():
        occupant = occupant_run_id(destination)
        if occupant is not None and occupant != run_id and not force:
            fail(2, f"results_slot_occupied_by:{occupant}")
        shutil.rmtree(destination)
    destination.mkdir(parents=True)

    published: list[dict] = []
    for name in PLAIN_FILES:
        source = run / name
        if source.is_file():
            published.append(copy_file(source, destination / ("manifest.json" if name == "run.json" else name)))

    if scorecard and scorecard.is_file():
        published.append(copy_file(scorecard, destination / "scorecard.json"))

    diff = run / "artifacts" / "git-diff.txt"
    if diff.is_file() and diff.stat().st_size:
        published.append(copy_file(diff, destination / "candidate.diff"))

    # Only the observations the verdict actually leans on — an uncited event read
    # is scratch, not evidence.
    cited = cited_observation_ids(result)
    evidence = destination / "evidence"
    for source in sorted((run / "judge-event-reads").glob("*.json")) if (run / "judge-event-reads").is_dir() else []:
        if source.stem in cited:
            published.append(copy_file(source, evidence / source.name))
    for kind in ("judge-inspections", "judge-verifications"):
        base = run / kind
        if not base.is_dir():
            continue
        for observation in sorted(base.iterdir()):
            identifier = observation.stem if observation.is_file() else observation.name
            if identifier not in cited:
                continue
            if observation.is_file():
                published.append(copy_file(observation, evidence / observation.name))
                continue
            for item in sorted(observation.rglob("*")):
                if item.is_file():
                    published.append(copy_file(item, evidence / observation.name / item.relative_to(observation)))

    manifest = {
        "run_id": run_id,
        "task_id": result.get("task_id"),
        "trial": trial,
        "validity": result.get("validity"),
        "outcome": result.get("outcome"),
        "score": result.get("score"),
        "published_files": published,
    }
    write_json(destination / "published.json", manifest)
    return {"destination": str(destination.relative_to(ROOT)), "files": len(published), "validity": manifest["validity"], "outcome": manifest["outcome"], "score": manifest["score"]}


def main() -> None:
    parser = argparse.ArgumentParser(allow_abbrev=False)
    parser.add_argument("run_id")
    parser.add_argument("--scorecard", type=Path)
    parser.add_argument("--force", action="store_true", help="overwrite results published by a different run at the same model/task/trial slot")
    arguments = parser.parse_args()
    validate_run_id(arguments.run_id)
    emit_json({"ok": True, "action": "publish", "run_id": arguments.run_id, **publish(arguments.run_id, arguments.scorecard, arguments.force)})


if __name__ == "__main__":
    main()
