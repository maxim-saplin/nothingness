"""The one cross-model table, derived from published results.

Every other view is per-model: `evals/results/<model>/README.md` is written by
whoever ran that campaign, and `consolidate.py` aggregates trials of a single
task in a single suite. Nothing produced a comparison across models, so the
top-level index was hand-maintained prose -- fine for one model, guaranteed to
drift the moment there are three.

This walks the published `result.json` files, which are the machine-readable
truth `decide` writes, and renders a task x model matrix plus per-model totals.
It is regenerated, never edited: `--write` splices it into `evals/README.md`
between markers so the index cannot silently disagree with the results tree.

Only `valid` runs are scored. An `invalid_infrastructure` run is shown as `--`
rather than counted, because it says nothing about the model.
"""

from __future__ import annotations

import argparse
from pathlib import Path
from typing import Any

from common import ROOT, emit_json, fail, read_json

RESULTS_ROOT = ROOT / "evals" / "results"
INDEX_PATH = ROOT / "evals" / "README.md"
BEGIN_MARKER = "<!-- BEGIN GENERATED LEADERBOARD -->"
END_MARKER = "<!-- END GENERATED LEADERBOARD -->"
OUTCOME_MARK = {"pass": "pass", "partial": "partial", "fail": "fail"}


def load_results() -> list[dict[str, Any]]:
    results = []
    for path in sorted(RESULTS_ROOT.glob("*/*/trial-*/result.json")):
        payload = read_json(path)
        if isinstance(payload, dict) and payload.get("task_id"):
            payload["_run_dir"] = path.parents[2].name
            results.append(payload)
    return results


def cell(result: dict[str, Any] | None) -> str:
    if result is None:
        return "–"
    if result.get("validity") != "valid":
        return "invalid"
    return f"{result.get('score')} {OUTCOME_MARK.get(str(result.get('outcome')), str(result.get('outcome')))}"


def render(results: list[dict[str, Any]]) -> list[str]:
    """One row per run, because a run is a run: the same model tomorrow, or
    judged by someone else, is a separate line rather than a cell that
    overwrites yesterday's. Cost and $/point sit beside the score -- a model
    that scores well for ten times the money is not the same result."""
    if not results:
        return ["_No published results yet._"]
    runs: dict[str, list[dict[str, Any]]] = {}
    for item in results:
        runs.setdefault(item["_run_dir"], []).append(item)

    lines = ["| Model | Thinking | Date | Judge | Score | Tokens (in/out) | Cost | $/point | Report |",
             "| --- | --- | --- | --- | --- | --- | --- | --- | --- |"]
    for name in sorted(runs, reverse=True):
        items = runs[name]
        model = items[0].get("selected_model") or items[0].get("requested_model") or {}
        scored = [item for item in items if item.get("validity") == "valid"]
        score = sum(item.get("score") or 0 for item in scored)
        spend = sum((item.get("cost_usd") or {}).get("combined") or 0 for item in items)
        tokens = {axis: sum(((item.get("candidate") or {}).get("usage") or {}).get("aggregate", {}).get("tokens", {}).get(axis) or 0 for item in items) for axis in ("input", "output")}
        judges = sorted({str(item.get("judge") or "unrecorded") for item in items})
        date = str(items[0].get("classified_at") or "")[:10]
        lines.append(
            f"| `{model.get('model', '?')}` | {model.get('thinking', '?')} | {date} | {', '.join(judges)} "
            f"| **{score}/{len(scored) * 3}** | {tokens['input'] / 1000:.0f}k / {tokens['output'] / 1000:.0f}k "
            f"| ${spend:.4f} | {f'${spend / score:.4f}' if score else '–'} | [detail](results/{name}/README.md) |"
        )
    lines += ["", "Score is the sum across the suite's tasks (0-3 each; any unmet `required` expectation caps a task at 2). Regenerate with `leaderboard.py --write`; do not hand-edit."]
    return lines


def main() -> None:
    parser = argparse.ArgumentParser(allow_abbrev=False, description="Render the cross-model results table from published result.json files.")
    parser.add_argument("--write", action="store_true", help=f"splice into {INDEX_PATH.relative_to(ROOT)} between the generated markers")
    arguments = parser.parse_args()
    results = load_results()
    table = render(results)
    if not arguments.write:
        emit_json({"ok": True, "runs": sorted({item["_run_dir"] for item in results}), "results": len(results), "table": table})
        return
    text = INDEX_PATH.read_text(encoding="utf-8")
    block = "\n".join([BEGIN_MARKER, *table, END_MARKER])
    if BEGIN_MARKER in text and END_MARKER in text:
        head, _, rest = text.partition(BEGIN_MARKER)
        _, _, tail = rest.partition(END_MARKER)
        text = head + block + tail
    else:
        fail(2, f"leaderboard_markers_missing -- add {BEGIN_MARKER} and {END_MARKER} to evals/README.md where the table belongs")
    INDEX_PATH.write_text(text, encoding="utf-8")
    emit_json({"ok": True, "wrote": str(INDEX_PATH.relative_to(ROOT)), "runs": sorted({item["_run_dir"] for item in results}), "results": len(results)})


if __name__ == "__main__":
    main()
