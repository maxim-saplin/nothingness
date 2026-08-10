"""Generate the per-run report skeleton, with the numbers already filled in.

The judge narrates; it does not retype arithmetic. Every figure here already
exists in the published `result.json` files, so a hand-written report can only
drift from the truth -- the earlier ones did, while also padding themselves with
environment boilerplate and task descriptions that live in `evals/README.md` and
`evals/tasks/`.

What survives is what a reader cannot get elsewhere: what scored what, what it
cost, what the model actually did, and whether anyone helped it. Cost is not a
footnote -- score alone says nothing about whether a model is worth running, so
tokens, spend and $/point sit in the main table.

The `<!-- judge: ... -->` placeholders are the only prose, and they are the
judge's job: one or two plain sentences per task on what actually happened.
"""

from __future__ import annotations

import argparse
from pathlib import Path
from typing import Any

from common import ROOT, emit_json, fail, read_json

RESULTS_ROOT = ROOT / "evals" / "results"


def usage_of(result: dict[str, Any]) -> dict[str, Any]:
    candidate = result.get("candidate") or {}
    aggregate = (candidate.get("usage") or {}).get("aggregate") or {}
    return aggregate.get("tokens") or {}


def spend_of(result: dict[str, Any]) -> float:
    return (result.get("cost_usd") or {}).get("combined") or 0.0


def per_point(spend: float, score: int | None) -> str:
    return f"${spend / score:.4f}" if score else "–"


def thousands(value: Any) -> str:
    return f"{int(value or 0) / 1000:.1f}k"


def build(directory: Path) -> list[str]:
    paths = sorted(directory.glob("*/trial-*/result.json"))
    notes = {}
    for path in paths:
        note = path.with_name("notes.md")
        if note.is_file():
            notes[read_json(path).get("task_id")] = note.read_text(encoding="utf-8").strip()
    results = [read_json(path) for path in paths]
    if not results:
        fail(2, f"no_published_results_in:{directory.relative_to(ROOT)}")
    first = results[0]
    model = first.get("selected_model") or first.get("requested_model") or {}
    scored = [item for item in results if item.get("validity") == "valid"]
    total_score = sum(item.get("score") or 0 for item in scored)
    total_spend = sum(spend_of(item) for item in results)
    # Sum the billable axes separately: `total` folds in cacheRead, which here runs
    # 20x the real input and turns a $0.70 run into a headline "21M tokens".
    totals = {name: sum((usage_of(item).get(name) or 0) for item in results) for name in ("input", "output", "reasoning", "cacheRead")}
    interventions = sum(item.get("intervention_count") or 0 for item in results)
    judges = sorted({str(item.get("judge") or "unrecorded") for item in results})

    lines = [
        f"# {model.get('model', '?')} · {model.get('thinking', '?')} reasoning · {str(first.get('classified_at') or '')[:10]}",
        "",
        f"**{total_score}/{len(scored) * 3}** across {len(scored)} scored tasks · "
        f"**${total_spend:.4f}** · {thousands(totals['input'])} in / {thousands(totals['output'])} out · "
        f"{'unassisted' if interventions == 0 else f'{interventions} interventions'} · "
        f"judge: {', '.join(judges)}",
        "",
        "<!-- judge: one paragraph — what was run and the single most important thing it showed. -->",
        "",
        "| Task | Score | Outcome | In | Out | Reasoning | Cache | Cost | $/point |",
        "| --- | --- | --- | --- | --- | --- | --- | --- | --- |",
    ]
    for item in results:
        tokens = usage_of(item)
        spend = spend_of(item)
        lines.append(
            f"| `{item.get('task_id')}` | {item.get('score') if item.get('validity') == 'valid' else '–'} "
            f"| {item.get('outcome')} | {thousands(tokens.get('input'))} | {thousands(tokens.get('output'))} "
            f"| {thousands(tokens.get('reasoning'))} | {thousands(tokens.get('cacheRead'))} | ${spend:.4f} | {per_point(spend, item.get('score'))} |"
        )
    lines += [
        f"| **Total** | **{total_score}/{len(scored) * 3}** | | {thousands(totals['input'])} | {thousands(totals['output'])} "
        f"| {thousands(totals['reasoning'])} | {thousands(totals['cacheRead'])} | **${total_spend:.4f}** | **{per_point(total_spend, total_score)}** |",
        "",
        "## What happened",
        "",
    ]
    for item in results:
        account = notes.get(item.get("task_id")) or "<!-- judge wrote no notes.md for this task -->"
        lines.append(f"**{item.get('task_id')}** ({item.get('score')}) — {account}")
        lines.append("")
    lines += [
        "## Interventions",
        "",
        "None — fully unassisted." if interventions == 0 else f"<!-- judge: {interventions} delivered — what was said to the candidate, and why it was stuck rather than merely failing. -->",
        "",
        "## What surprised us",
        "",
        "<!-- judge: up to 3 bullets. Only things the table does not already say. -->",
        "",
    ]
    return lines


def main() -> None:
    parser = argparse.ArgumentParser(allow_abbrev=False, description="Render a run's report skeleton from its published results.")
    parser.add_argument("run_directory", help="e.g. evals/results/gpt-5.4-nano-medium-20260810")
    parser.add_argument("--write", action="store_true", help="write README.md into the run directory")
    arguments = parser.parse_args()
    directory = (ROOT / arguments.run_directory).resolve() if not Path(arguments.run_directory).is_absolute() else Path(arguments.run_directory)
    if not directory.is_dir() or not directory.is_relative_to(RESULTS_ROOT):
        fail(2, f"not_a_results_directory:{arguments.run_directory}")
    lines = build(directory)
    if not arguments.write:
        emit_json({"ok": True, "directory": str(directory.relative_to(ROOT)), "report": lines})
        return
    (directory / "README.md").write_text("\n".join(lines), encoding="utf-8")
    emit_json({"ok": True, "wrote": str((directory / "README.md").relative_to(ROOT)), "placeholders": sum(1 for line in lines if "<!-- judge:" in line)})


if __name__ == "__main__":
    main()
