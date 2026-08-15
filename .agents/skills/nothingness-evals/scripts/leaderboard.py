"""Render the cross-model table from published campaign results.

Each campaign is rendered as its own data point, so intentional repeat campaigns
can expose variability for the same model triple. A campaign may use fresh task
retries, but only one accepted result per task contributes to its score and
accepted-task cost. Campaign cost includes accepted runs and retry spend when
the campaign manifest records it.
"""

from __future__ import annotations

import argparse
from pathlib import Path
from typing import Any

from common import ROOT, emit_json, fail, read_json, write_json

RESULTS_ROOT = ROOT / "evals" / "results"
INDEX_PATH = ROOT / "evals" / "README.md"
BEGIN_MARKER = "<!-- BEGIN GENERATED LEADERBOARD -->"
END_MARKER = "<!-- END GENERATED LEADERBOARD -->"
OUTCOME_MARK = {"pass": "pass", "partial": "partial", "fail": "fail"}
ORCHESTRATOR_FILE = "orchestrator.json"


def orchestrator(name: str) -> dict[str, Any]:
    path = RESULTS_ROOT / name / ORCHESTRATOR_FILE
    if not path.is_file():
        return {}
    payload = read_json(path)
    return payload if isinstance(payload, dict) else {}


def load_results() -> list[dict[str, Any]]:
    results = []
    for path in sorted(RESULTS_ROOT.rglob("result.json")):
        if len(path.relative_to(RESULTS_ROOT).parts) < 2:
            continue
        payload = read_json(path)
        if isinstance(payload, dict) and payload.get("task_id"):
            payload["_run_dir"] = path.relative_to(RESULTS_ROOT).parts[0]
            results.append(payload)
    return results


def campaign_manifest(name: str) -> dict[str, Any]:
    path = RESULTS_ROOT / name / "campaign.json"
    if not path.is_file():
        return {}
    payload = read_json(path)
    return payload if isinstance(payload, dict) else {}


def money(value: object) -> str:
    return "unknown" if not isinstance(value, (int, float)) else f"${value:.4f}"


def retry_summary(manifest: dict[str, Any], items: list[dict[str, Any]]) -> str:
    if not manifest:
        return "–"
    values = []
    for item in items:
        value = item.get("retry")
        if isinstance(value, int):
            values.append(value)
    return str(max(values, default=0))


def cell(result: dict[str, Any] | None) -> str:
    if result is None:
        return "–"
    if result.get("validity") != "valid":
        return "invalid"
    return f"{result.get('score')} {OUTCOME_MARK.get(str(result.get('outcome')), str(result.get('outcome')))}"


def render(results: list[dict[str, Any]]) -> list[str]:
    if not results:
        return ["_No published results yet._"]
    runs: dict[str, list[dict[str, Any]]] = {}
    for item in results:
        runs.setdefault(item["_run_dir"], []).append(item)

    columns = ("Model", "Thinking", "Date", "Eval", "Orchestrator/Judge", "Orchestrator/Judge cost", "Retries", "Score", "Assisted", "Tokens (in/out)", "Accepted task cost", "Campaign cost", "$/point", "Report")
    lines = [f"| {' | '.join(columns)} |", f"|{'|'.join([' --- '] * len(columns))}|"]
    for name in sorted(runs, reverse=True):
        items = runs[name]
        manifest = campaign_manifest(name)
        model = items[0].get("selected_model") or items[0].get("requested_model") or {}
        scored = [item for item in items if item.get("validity") == "valid"]
        score = sum(item.get("score") or 0 for item in scored)
        accepted_cost = sum((item.get("cost_usd") or {}).get("combined") or 0 for item in items)
        campaign_cost = ((manifest.get("costs") or {}).get("campaign_usd") if manifest else accepted_cost)
        tokens = {axis: sum(((item.get("candidate") or {}).get("usage") or {}).get("aggregate", {}).get("tokens", {}).get(axis) or 0 for item in items) for axis in ("input", "output")}
        date = str(items[0].get("classified_at") or "")[:10]
        conductor = orchestrator(name)
        who = str(conductor.get("orchestrator") or "unrecorded")
        conducted = conductor.get("cost_usd")
        versions = sorted({str(item.get("eval_version") or "") for item in items} - {""})
        helped = [item for item in items if item.get("assisted")]
        interventions = sum(item.get("intervention_count") or 0 for item in items)
        lines.append(
            f"| `{model.get('model', '?')}` | {model.get('thinking', '?')} | {date} | {', '.join(versions) or '–'} | {who} "
            f"| {f'${conducted:.2f}' if isinstance(conducted, (int, float)) else '–'} | {retry_summary(manifest, items)} "
            f"| **{score}/{len(scored) * 3}** | {'no' if not helped else f'**{interventions}** on {len(helped)}/{len(items)} tasks'} "
            f"| {tokens['input'] / 1000:.0f}k / {tokens['output'] / 1000:.0f}k "
            f"| ${accepted_cost:.4f} | {money(campaign_cost)} | {f'${campaign_cost / score:.4f}' if isinstance(campaign_cost, (int, float)) and score else '–'} | [detail](results/{name}/README.md) |"
        )
    lines += [
        "",
        "`Retries` counts fresh task restarts in the current campaign. `Accepted task cost` uses only the accepted run for each completed task. `Campaign cost` includes accepted runs and retry spend. "
        "`Orchestrator/Judge cost` is supplied separately because those agent sessions are outside the measured containers. Regenerate with `leaderboard.py --write`; do not hand-edit between the markers.",
    ]
    return lines


def main() -> None:
    parser = argparse.ArgumentParser(allow_abbrev=False, description="Render the cross-model results table from published result.json files.")
    parser.add_argument("--write", action="store_true", help=f"splice into {INDEX_PATH.relative_to(ROOT)} between the generated markers")
    parser.add_argument("--set", nargs=3, metavar=("RUN_DIR", "ORCHESTRATOR", "COST_USD"), help="record who conducted a campaign and what that cost")
    arguments = parser.parse_args()
    if arguments.set:
        name, who, cost = arguments.set
        directory = RESULTS_ROOT / name
        if not directory.is_dir():
            fail(2, f"run_directory_not_found:{name}")
        try:
            amount = float(str(cost).lstrip("$").replace(",", ""))
        except ValueError:
            fail(2, f"orchestrator_cost_not_a_number:{cost}")
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
