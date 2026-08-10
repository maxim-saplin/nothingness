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
            payload["_model_dir"] = path.parents[2].name
            results.append(payload)
    return results


def model_label(result: dict[str, Any]) -> str:
    model = result.get("selected_model") or result.get("requested_model") or {}
    name = str(model.get("model") or result["_model_dir"])
    thinking = str(model.get("thinking") or "").strip()
    return f"{name} ({thinking})" if thinking and thinking != "off" else name


def cell(result: dict[str, Any] | None) -> str:
    if result is None:
        return "–"
    if result.get("validity") != "valid":
        return "invalid"
    return f"{result.get('score')} {OUTCOME_MARK.get(str(result.get('outcome')), str(result.get('outcome')))}"


def render(results: list[dict[str, Any]]) -> list[str]:
    if not results:
        return ["_No published results yet._"]
    models = sorted({model_label(item) for item in results})
    tasks = sorted({str(item["task_id"]) for item in results})
    best: dict[tuple[str, str], dict[str, Any]] = {}
    for item in results:
        key = (str(item["task_id"]), model_label(item))
        # Highest scored valid trial wins the cell; per-trial detail lives in the
        # model's own report, not in a comparison table.
        current = best.get(key)
        if current is None or (item.get("score") or 0) > (current.get("score") or 0):
            best[key] = item

    lines = [f"| Task | {' | '.join(models)} |", f"| --- | {' | '.join('---' for _ in models)} |"]
    for task in tasks:
        lines.append(f"| `{task}` | {' | '.join(cell(best.get((task, model))) for model in models)} |")

    totals, costs, valid_counts = [], [], []
    for model in models:
        scored = [item for item in best.values() if model_label(item) == model and item.get("validity") == "valid"]
        total = sum(item.get("score") or 0 for item in scored)
        spend = sum((item.get("cost_usd") or {}).get("combined") or 0 for item in scored)
        totals.append(f"**{total}/{len(scored) * 3}**" if scored else "–")
        costs.append(f"${spend:.4f}" if scored else "–")
        valid_counts.append(str(len(scored)))
    lines.append(f"| **Total score** | {' | '.join(totals)} |")
    lines.append(f"| **Tasks scored** | {' | '.join(valid_counts)} |")
    lines.append(f"| **Spend** | {' | '.join(costs)} |")
    lines.append("")
    lines.append("Each cell is `score outcome` for that model's best valid trial (0-3; any unmet `required` expectation caps at 2). Regenerate with `leaderboard.py --write`; do not hand-edit.")
    return lines


def main() -> None:
    parser = argparse.ArgumentParser(allow_abbrev=False, description="Render the cross-model results table from published result.json files.")
    parser.add_argument("--write", action="store_true", help=f"splice into {INDEX_PATH.relative_to(ROOT)} between the generated markers")
    arguments = parser.parse_args()
    results = load_results()
    table = render(results)
    if not arguments.write:
        emit_json({"ok": True, "models": sorted({model_label(item) for item in results}), "results": len(results), "table": table})
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
    emit_json({"ok": True, "wrote": str(INDEX_PATH.relative_to(ROOT)), "models": sorted({model_label(item) for item in results}), "results": len(results)})


if __name__ == "__main__":
    main()
