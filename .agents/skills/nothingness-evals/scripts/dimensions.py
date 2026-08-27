"""Render the extended, multi-axis leaderboard from published campaign results.

The published score condenses each task to one integer, discarding most of what a
run already recorded. Nothing here needs a new campaign: every axis below is
derived from artifacts already on disk.

Axes are assigned to expectations by parsing the rubric headings and their
declared evidence kind, never by a hardcoded list of ids, so a rubric edit moves
its expectations without touching this file. The assignment is printed as its own
table so it can be audited rather than trusted.
"""

from __future__ import annotations

import argparse
import re
import statistics
from pathlib import Path
from typing import Any

from common import ROOT, emit_json, fail, read_json

RESULTS_ROOT = ROOT / "evals" / "results"
RUBRIC_ROOT = ROOT / "evals" / "tasks" / "rubrics"
INDEX_PATH = ROOT / "evals" / "DIMENSIONS.md"
BEGIN_MARKER = "<!-- BEGIN GENERATED DIMENSIONS -->"
END_MARKER = "<!-- END GENERATED DIMENSIONS -->"

CREDIT = {"met": 1.0, "partial": 0.5, "unmet": 0.0}

# Ordered: the first pattern that matches a heading wins. `self` is what is left
# of the evidence-kind `events` items once the honesty patterns have been taken.
INTACT = re.compile(
    r"unaffected|undisturbed|nothing else regresses|scoped to|no crashes"
    r"|no new errors|unrequested source changes",
    re.I,
)
PROOF = re.compile(
    r"actually captured and is on-point|corroborat|narrating over"
    r"|traceable to an actual observation",
    re.I,
)
# An `events` expectation only measures self-verification when it asks whether the
# candidate observed its own change *as it happened*. Other `events` items audit
# the trail for correctness instead, and belong on `works`.
SELF = re.compile(r"while swiping|track the swipe|during-gesture|genuinely captured", re.I)

AXES = ("works", "self", "proof", "intact")
AXIS_LABEL = {
    "works": "works",
    "self": "self-ev",
    "proof": "proof",
    "intact": "intact",
}


def rubric_axes() -> dict[str, dict[str, str]]:
    """task_id -> {expectation id: axis}, parsed from the rubric prose."""
    mapping: dict[str, dict[str, str]] = {}
    for path in sorted(RUBRIC_ROOT.glob("t*.md")):
        text = path.read_text(encoding="utf-8")
        per_task: dict[str, str] = {}
        for block in text.split("\n### ")[1:]:
            heading = block.split("\n", 1)[0]
            ident = heading.split(None, 1)[0].strip()
            if not re.fullmatch(r"E\d+", ident):
                continue
            evidence = re.search(r"\*\*Evidence:\*\*\s*(\S+)", block)
            kind = evidence.group(1) if evidence else ""
            if INTACT.search(heading):
                axis = "intact"
            elif PROOF.search(heading):
                axis = "proof"
            elif kind.startswith("events") and SELF.search(heading):
                axis = "self"
            else:
                axis = "works"
            per_task[ident] = axis
        mapping[path.stem] = per_task
    return mapping


def load_runs() -> list[dict[str, Any]]:
    runs = []
    for path in sorted(RESULTS_ROOT.rglob("result.json")):
        parts = path.relative_to(RESULTS_ROOT).parts
        if len(parts) < 2:
            continue
        payload = read_json(path)
        if not (isinstance(payload, dict) and payload.get("task_id")):
            continue
        payload["_campaign"] = parts[0]
        summary = path.parent / "summary.json"
        payload["_summary"] = read_json(summary) if summary.is_file() else {}
        runs.append(payload)
    return runs


def axis_credit(run: dict[str, Any], axes: dict[str, dict[str, str]]) -> dict[str, float | None]:
    lookup = axes.get(str(run.get("rubric_id") or run.get("task_id")), {})
    buckets: dict[str, list[float]] = {axis: [] for axis in AXES}
    scorecard = run.get("scorecard")
    if not isinstance(scorecard, list):
        return {axis: None for axis in AXES}
    for item in scorecard:
        if not isinstance(item, dict):
            continue
        axis = lookup.get(str(item.get("id")))
        credit = CREDIT.get(str(item.get("verdict")))
        if axis and credit is not None:
            buckets[axis].append(credit)
    return {
        axis: (statistics.mean(values) if values else None)
        for axis, values in buckets.items()
    }


def wall_minutes(run: dict[str, Any]) -> float | None:
    timing = (run.get("_summary") or {}).get("timing")
    if isinstance(timing, dict):
        elapsed = timing.get("elapsed_seconds")
        if isinstance(elapsed, (int, float)):
            return float(elapsed) / 60.0
    return None


def candidate_cost(run: dict[str, Any]) -> float | None:
    cost = run.get("cost_usd")
    if isinstance(cost, dict) and isinstance(cost.get("candidate"), (int, float)):
        return float(cost["candidate"])
    if isinstance(cost, (int, float)):
        return float(cost)
    return None


def tool_calls(run: dict[str, Any]) -> int | None:
    executions = (run.get("candidate") or {}).get("tool_executions")
    return executions if isinstance(executions, int) else None


def pct(value: float | None) -> str:
    return "–" if value is None else f"{100 * value:.0f}"


def num(value: float | None, spec: str = ".2f") -> str:
    return "–" if value is None else format(value, spec)


def mean_or_none(values: list[float]) -> float | None:
    return statistics.mean(values) if values else None


def model_of(run: dict[str, Any]) -> str:
    selected = run.get("selected_model") or {}
    model = selected.get("model") or "?"
    thinking = selected.get("thinking") or "?"
    return f"`{model}` {thinking}"


def render(runs: list[dict[str, Any]], axes: dict[str, dict[str, str]]) -> list[str]:
    per_campaign: dict[str, list[dict[str, Any]]] = {}
    for run in runs:
        per_campaign.setdefault(run["_campaign"], []).append(run)

    lines: list[str] = []
    lines.append("### Per campaign")
    lines.append("")
    lines.append(
        "| Campaign | Model | Eval | Score | works | self-ev | proof | intact "
        "| Candidate $ | Wall min | Tools | Help |"
    )
    lines.append("| --- | --- | --- | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: |")
    for campaign in sorted(per_campaign):
        items = per_campaign[campaign]
        credits = [axis_credit(run, axes) for run in items]
        scored = [r.get("score") for r in items if isinstance(r.get("score"), int)]
        costs = [c for c in (candidate_cost(r) for r in items) if c is not None]
        mins = [m for m in (wall_minutes(r) for r in items) if m is not None]
        calls = [d for d in (tool_calls(r) for r in items) if d is not None]
        help_total = sum(
            r.get("intervention_count") or 0
            for r in items
            if isinstance(r.get("intervention_count"), int)
        )
        version = next((str(r.get("eval_version")) for r in items if r.get("eval_version")), "–")
        row = [
            f"[{campaign}](results/{campaign}/README.md)",
            model_of(items[0]),
            version,
            f"**{sum(scored)}**" if scored else "–",
        ]
        for axis in AXES:
            row.append(pct(mean_or_none([c[axis] for c in credits if c[axis] is not None])))
        row.append(num(sum(costs) if costs else None, ".3f"))
        row.append(num(sum(mins) if mins else None, ".0f"))
        row.append(num(mean_or_none([float(d) for d in calls]), ".0f"))
        row.append(str(help_total))
        lines.append("| " + " | ".join(row) + " |")
    lines.append("")

    lines.append("### Per task, pooled over every campaign")
    lines.append("")
    lines.append("| Task | n | Score mean | works | self-ev | proof | intact | Candidate $ | Wall min | Tools |")
    lines.append("| --- | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: |")
    per_task: dict[str, list[dict[str, Any]]] = {}
    for run in runs:
        per_task.setdefault(str(run.get("task_id")), []).append(run)
    for task in sorted(per_task):
        items = per_task[task]
        credits = [axis_credit(run, axes) for run in items]
        scored = [r["score"] for r in items if isinstance(r.get("score"), int)]
        row = [
            task,
            str(len(items)),
            num(mean_or_none([float(s) for s in scored]), ".2f"),
        ]
        for axis in AXES:
            row.append(pct(mean_or_none([c[axis] for c in credits if c[axis] is not None])))
        row.append(num(mean_or_none([c for c in (candidate_cost(r) for r in items) if c is not None]), ".3f"))
        row.append(num(mean_or_none([m for m in (wall_minutes(r) for r in items) if m is not None]), ".0f"))
        row.append(num(mean_or_none([float(d) for d in (tool_calls(r) for r in items) if d is not None]), ".0f"))
        lines.append("| " + " | ".join(row) + " |")
    lines.append("")

    lines.append("### How each expectation was assigned")
    lines.append("")
    lines.append("| Task | " + " | ".join(AXIS_LABEL[a] for a in AXES) + " |")
    lines.append("| --- | --- | --- | --- | --- |")
    for task in sorted(axes):
        grouped = {axis: [] for axis in AXES}
        for ident, axis in sorted(axes[task].items(), key=lambda kv: int(kv[0][1:])):
            grouped[axis].append(ident)
        cells = [", ".join(grouped[axis]) or "–" for axis in AXES]
        lines.append(f"| {task} | " + " | ".join(cells) + " |")
    return lines


def main() -> None:
    parser = argparse.ArgumentParser(
        allow_abbrev=False,
        description="Render the multi-axis leaderboard from published result.json files.",
    )
    parser.add_argument(
        "--write",
        action="store_true",
        help=f"splice into {INDEX_PATH.relative_to(ROOT)} between the generated markers",
    )
    parser.add_argument("--json", action="store_true", help="emit the per-run axis values instead of a table")
    args = parser.parse_args()

    axes = rubric_axes()
    runs = load_runs()
    if not runs:
        fail(2, "no_published_results -- evals/results holds no result.json")

    if args.json:
        emit_json(
            {
                "axis_assignment": axes,
                "runs": [
                    {
                        "campaign": run["_campaign"],
                        "task_id": run.get("task_id"),
                        "score": run.get("score"),
                        "axes": axis_credit(run, axes),
                        "candidate_usd": candidate_cost(run),
                        "wall_minutes": wall_minutes(run),
                        "tool_calls": tool_calls(run),
                        "interventions": run.get("intervention_count"),
                    }
                    for run in runs
                ],
            }
        )
        return

    table = render(runs, axes)
    if not args.write:
        print("\n".join(table))
        return

    if not INDEX_PATH.is_file():
        fail(2, f"missing_index -- create {INDEX_PATH.relative_to(ROOT)} with the generated markers")
    text = INDEX_PATH.read_text(encoding="utf-8")
    block = "\n".join([BEGIN_MARKER, *table, END_MARKER])
    if BEGIN_MARKER not in text or END_MARKER not in text:
        fail(2, f"dimensions_markers_missing -- add {BEGIN_MARKER} and {END_MARKER} to {INDEX_PATH.relative_to(ROOT)}")
    head, _, rest = text.partition(BEGIN_MARKER)
    _, _, tail = rest.partition(END_MARKER)
    INDEX_PATH.write_text(head + block + tail, encoding="utf-8")
    emit_json({"ok": True, "path": str(INDEX_PATH.relative_to(ROOT)), "runs": len(runs)})


if __name__ == "__main__":
    main()
