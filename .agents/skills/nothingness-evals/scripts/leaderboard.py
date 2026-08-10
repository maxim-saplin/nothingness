"""The one cross-model table, derived from published results.

Every other view is per-run: `evals/results/<run-dir>/README.md` covers one
campaign. Nothing produced a comparison across runs, so the top-level index was
hand-maintained prose -- fine for one model, and it drifted within a week,
quoting task scores and a total cost that matched nothing on disk.

This walks the published `result.json` files, which are the machine-readable
truth `decide` writes, and renders one row per run. It is regenerated, never
edited: `--write` splices it into `evals/README.md` between markers so the index
cannot silently disagree with the results tree.

A run is one run. Rows are never averaged or pooled: repeating a model is a new
row to compare by eye, not a sample the harness folds into an interval.

Only `valid` runs are scored. An `invalid_infrastructure` run is shown as `--`
rather than counted, because it says nothing about the model.
"""

from __future__ import annotations

import argparse
import re
from pathlib import Path
from typing import Any

from common import ROOT, emit_json, fail, read_json, write_json

RESULTS_ROOT = ROOT / "evals" / "results"
INDEX_PATH = ROOT / "evals" / "README.md"
BEGIN_MARKER = "<!-- BEGIN GENERATED LEADERBOARD -->"
END_MARKER = "<!-- END GENERATED LEADERBOARD -->"
OUTCOME_MARK = {"pass": "pass", "partial": "partial", "fail": "fail"}
# What ran the campaign, and what that cost. The harness cannot see either: the
# orchestrator and judges are agent sessions outside the containers it measures,
# so their spend is invisible to it. This is the one figure a human supplies --
# and it dominates. A campaign whose candidate cost under a dollar can cost fifty
# to conduct, which is the real price of a number and belongs beside it.
ORCHESTRATOR_FILE = "orchestrator.json"
ATTEMPT_PATTERN = re.compile(r"-attempt-(\d+)$")


def orchestrator(name: str) -> dict[str, Any]:
    path = RESULTS_ROOT / name / ORCHESTRATOR_FILE
    if not path.is_file():
        return {}
    payload = read_json(path)
    return payload if isinstance(payload, dict) else {}


def attempts_per_task(items: list[dict[str, Any]]) -> str:
    """Derived, not asked for. A published run id ends in `-attempt-NN`, and only
    the attempt that produced a score gets published, so its number is how many
    tries that task took."""
    counts = sorted({int(match.group(1)) for item in items if (match := ATTEMPT_PATTERN.search(str(item.get("run_id") or "")))})
    if not counts:
        return "?"
    return str(counts[0]) if len(counts) == 1 else f"{counts[0]}–{counts[-1]}"


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

    columns = ("Model", "Thinking", "Date", "Eval", "Orchestrator/Judge", "Orchestrator/Judge cost", "Attempts per task", "Score", "Tokens (in/out)", "Cost", "$/point", "Report")
    lines = [f"| {' | '.join(columns)} |", f"|{'|'.join([' --- '] * len(columns))}|"]
    for name in sorted(runs, reverse=True):
        items = runs[name]
        model = items[0].get("selected_model") or items[0].get("requested_model") or {}
        scored = [item for item in items if item.get("validity") == "valid"]
        score = sum(item.get("score") or 0 for item in scored)
        spend = sum((item.get("cost_usd") or {}).get("combined") or 0 for item in items)
        tokens = {axis: sum(((item.get("candidate") or {}).get("usage") or {}).get("aggregate", {}).get("tokens", {}).get(axis) or 0 for item in items) for axis in ("input", "output")}
        date = str(items[0].get("classified_at") or "")[:10]
        conductor = orchestrator(name)
        who = str(conductor.get("orchestrator") or "unrecorded")
        conducted = conductor.get("cost_usd")
        # One row is one campaign, so a mixed set of versions inside it means the
        # harness changed mid-run -- worth showing rather than picking one.
        versions = sorted({str(item.get("eval_version") or "") for item in items} - {""})
        lines.append(
            f"| `{model.get('model', '?')}` | {model.get('thinking', '?')} | {date} | {', '.join(versions) or '–'} | {who} "
            f"| {f'${conducted:.2f}' if isinstance(conducted, (int, float)) else '–'} | {attempts_per_task(items)} "
            f"| **{score}/{len(scored) * 3}** | {tokens['input'] / 1000:.0f}k / {tokens['output'] / 1000:.0f}k "
            f"| ${spend:.4f} | {f'${spend / score:.4f}' if score else '–'} | [detail](results/{name}/README.md) |"
        )
    lines += [
        "",
        "`Cost` and `$/point` are the model under test. `Orchestrator/Judge cost` is what it cost to *conduct* the run — "
        "agent sessions outside the measured containers, so the harness cannot see it. Record it per run with "
        "`leaderboard.py --set <run-dir> \"<who>\" <cost>`; everything else is read from the run artifacts. "
        "Regenerate with `leaderboard.py --write`; do not hand-edit between the markers.",
    ]
    return lines


def main() -> None:
    parser = argparse.ArgumentParser(allow_abbrev=False, description="Render the cross-model results table from published result.json files.")
    parser.add_argument("--write", action="store_true", help=f"splice into {INDEX_PATH.relative_to(ROOT)} between the generated markers")
    parser.add_argument("--set", nargs=3, metavar=("RUN_DIR", "ORCHESTRATOR", "COST_USD"), help='record who conducted a run and what that cost, e.g. --set gpt-5.4-nano-medium-20260810 "Opus 5 High" 50.56')
    arguments = parser.parse_args()
    if arguments.set:
        name, who, cost = arguments.set
        directory = RESULTS_ROOT / name
        if not directory.is_dir():
            fail(2, f"run_directory_not_found:{name} -- published runs are {', '.join(sorted(item.name for item in RESULTS_ROOT.iterdir() if item.is_dir())) or 'none yet'}")
        try:
            amount = float(str(cost).lstrip("$").replace(",", ""))
        except ValueError:
            fail(2, f"orchestrator_cost_not_a_number:{cost} -- pass a plain amount, e.g. 50.56")
        write_json(directory / ORCHESTRATOR_FILE, {"orchestrator": who, "cost_usd": amount})
        emit_json({"ok": True, "action": "set", "run_dir": name, "orchestrator": who, "cost_usd": amount, "next_step": "leaderboard.py --write"})
        return
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
