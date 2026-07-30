from __future__ import annotations

import re
from pathlib import Path
from typing import Any

from campaign_common import (
    EXPECTED_TASK_IDS,
    campaign_results_root,
    load_suite,
    publication_root,
)
from common import ROOT, read_json, sha256


def money(value: object) -> str:
    return "unknown" if not isinstance(value, (int, float)) else f"${value:.4f}"


def integer(value: object) -> str:
    return f"{int(value):,}" if isinstance(value, (int, float)) else "unknown"


def href_from_repo(path: Path) -> str:
    try:
        return path.relative_to(ROOT).as_posix()
    except ValueError:
        return path.relative_to(publication_root()).as_posix()


def href_from_evals(path: Path) -> str:
    try:
        return path.relative_to(ROOT / "evals").as_posix()
    except ValueError:
        return href_from_repo(path)


def href_from_model_results(path: Path, model_id: str) -> str:
    model_root = ROOT / "evals" / "results" / model_id
    try:
        return path.relative_to(model_root).as_posix()
    except ValueError:
        return href_from_repo(path)


def report_link(path: str | None, model_id: str | None = None) -> str:
    if not path:
        return "—"
    resolved = Path(path)
    if model_id:
        href = href_from_model_results(resolved, model_id)
    else:
        href = href_from_repo(resolved)
    return f"[report]({href}/report.md)"


def attempt_report_markdown(*, result: dict[str, Any], campaign_id: str, task_id: str, attempt: int) -> str:
    validity = result.get("validity", "unknown")
    outcome = result.get("outcome", "unknown")
    score = result.get("score")
    notes = result.get("notes", "")
    cost = result.get("cost_usd", {})
    candidate_cost = cost.get("candidate") if isinstance(cost, dict) else None
    admission_cost = cost.get("admission") if isinstance(cost, dict) else None
    combined_cost = cost.get("combined") if isinstance(cost, dict) else None
    intervention_count = result.get("intervention_count", 0)
    unassisted = result.get("unassisted")
    lines = [
        f"# {task_id} trial 1 attempt {attempt}",
        "",
        f"Campaign: `{campaign_id}`",
        f"Run: `{result.get('run_id', 'unknown')}`",
        "",
        "## Outcome",
        "",
        f"- Validity: **{validity}**",
        f"- Outcome: **{outcome}**",
        f"- Score: **{score if score is not None else 'n/a'}**",
        f"- Unassisted: **{unassisted}**",
        f"- Interventions: **{intervention_count}**",
        "",
        "## Cost and usage",
        "",
        f"- Admission: {money(admission_cost)}",
        f"- Candidate: {money(candidate_cost)}",
        f"- Combined: {money(combined_cost)}",
        "",
        "## Rationale",
        "",
        notes or "_No notes recorded._",
        "",
        "## Evidence",
        "",
        "- `result.json` canonical outcome",
        "- `evidence/` compact runtime, git, and process artifacts",
        "- `cleanup.json` resource teardown verification",
        "",
    ]
    return "\n".join(lines)


def campaign_report_markdown(state: dict[str, Any]) -> str:
    campaign_id = state["campaign_id"]
    model_id = state["model"]["path_id"]
    budget = state["budget"]
    lines = [
        f"# Campaign {campaign_id}",
        "",
        f"Status: **{state['status']}**",
        f"Suite: `{state['suite']['id']}`",
        f"Model: `{state['model']['model']}` ({state['model']['thinking']})",
        "",
        "## Budget",
        "",
        f"- Ceiling: {money(budget['candidate_admission_cost_ceiling_usd'])} / {integer(budget['token_ceiling'])} tokens",
        f"- Consumed: {money(budget['combined_cost_usd'])} / {integer(budget['tokens'])} tokens",
        f"- Unknown cost: **{budget['unknown_cost']}**",
        f"- Invalid attempts: **{state.get('invalid_attempt_count', 0)}**",
        "",
        "## Tasks",
        "",
        "| # | Task | Status | Attempts | Validity | Outcome | Score | Report |",
        "| - | ---- | ------ | -------- | -------- | ------- | ----- | ------ |",
    ]
    for task in state["tasks"]:
        attempts = task.get("attempts") or []
        last = attempts[-1] if attempts else {}
        report_path = task.get("published_path")
        if report_path:
            report_cell = report_link(report_path, state["model"]["path_id"])
        elif last.get("archive_path"):
            report_cell = report_link(last["archive_path"], state["model"]["path_id"])
        else:
            report_cell = "—"
        lines.append(
            "| {ordinal} | `{task_id}` | {status} | {attempts} | {validity} | {outcome} | {score} | {report} |".format(
                ordinal=task["ordinal"],
                task_id=task["id"],
                status=task["status"],
                attempts=len(attempts),
                validity=last.get("validity", "—"),
                outcome=last.get("outcome", "—"),
                score=last.get("score", "—"),
                report=report_cell,
            )
        )
    lines.extend(
        [
            "",
            "## Scope",
            "",
            "One scored isolated trial per task (T1–T7). Candidate failures remain task outcomes.",
            "This campaign is not the three-trial-per-task reliability cohort.",
            "",
        ]
    )
    if state["status"] == "paused_budget":
        lines.extend(
            [
                "## Budget pause",
                "",
                "Campaign paused before the next task because a ceiling was reached or required cost is unknown.",
                "Resume only after explicit operator review.",
                "",
            ]
        )
    return "\n".join(lines)


def write_campaign_report(state: dict[str, Any]) -> Path:
    destination = campaign_results_root(state["campaign_id"], state["model"]["path_id"]) / "campaign.md"
    destination.parent.mkdir(parents=True, exist_ok=True)
    destination.write_text(campaign_report_markdown(state), encoding="utf-8")
    if should_update_readme_indexes() and any(task.get("status") == "published" for task in state["tasks"]):
        update_readme_indexes(state)
    return destination


def campaign_progress(state: dict[str, Any]) -> tuple[int, int]:
    published = sum(1 for task in state["tasks"] if task.get("status") == "published")
    return published, len(state["tasks"])


def campaign_report_href(state: dict[str, Any]) -> str:
    path = campaign_results_root(state["campaign_id"], state["model"]["path_id"]) / "campaign.md"
    return href_from_evals(path)


def should_update_readme_indexes() -> bool:
    return publication_root().resolve() == (ROOT / "evals").resolve()


def model_display_name(model_id: str) -> str:
    known = {"gpt-5.4-nano": "GPT-5.4 Nano"}
    return known.get(model_id, model_id.replace("--", "/").replace("gpt-", "GPT-"))


def model_readme_campaign_section(state: dict[str, Any]) -> str:
    published, total = campaign_progress(state)
    campaign_id = state["campaign_id"]
    suite = state["suite"]
    budget = state["budget"]
    report_href = href_from_model_results(
        campaign_results_root(state["campaign_id"], state["model"]["path_id"]) / "campaign.md",
        state["model"]["path_id"],
    )
    lines = [
        f"## Seven-task campaign (`{suite['id']}`)",
        "",
        f"Campaign ID: `{campaign_id}`",
        f"Suite manifest: `{suite['manifest_sha256']}`",
        f"Status: **{state['status']}** ({published}/{total} tasks published)",
        f"Report: [{report_href}]({report_href})",
        "",
        f"Budget: {money(budget['combined_cost_usd'])} consumed of {money(budget['candidate_admission_cost_ceiling_usd'])} / {integer(budget['tokens'])} of {integer(budget['token_ceiling'])} tokens.",
        "",
        "| # | Task | Outcome | Score | Report |",
        "| - | ---- | ------- | ----- | ------ |",
    ]
    for task in state["tasks"]:
        attempts = task.get("attempts") or []
        last = attempts[-1] if attempts else {}
        if task.get("published_path"):
            trial_href = href_from_model_results(Path(task["published_path"]), state["model"]["path_id"])
            report_cell = f"[report]({trial_href}/report.md)"
        else:
            report_cell = "—"
        lines.append(
            "| {ordinal} | `{task_id}` | {outcome} | {score} | {report} |".format(
                ordinal=task["ordinal"],
                task_id=task["id"],
                outcome=last.get("outcome", "—"),
                score=last.get("score", "—"),
                report=report_cell,
            )
        )
    lines.extend(
        [
            "",
            "One scored isolated trial per task (T1–T7). Candidate failures remain task outcomes.",
            "This campaign is not the three-trial-per-task reliability cohort below.",
            "",
        ]
    )
    return "\n".join(lines)


def replace_marked_section(content: str, marker: str, section: str) -> str:
    begin = f"<!-- {marker}:start -->"
    end = f"<!-- {marker}:end -->"
    block = f"{begin}\n{section.rstrip()}\n{end}"
    pattern = re.compile(re.escape(begin) + r".*?" + re.escape(end), re.DOTALL)
    if pattern.search(content):
        return pattern.sub(block, content, count=1)
    return content.rstrip() + "\n\n" + block + "\n"


def default_model_readme_header(state: dict[str, Any]) -> str:
    model = state["model"]
    return "\n".join(
        [
            f"# {model_display_name(model['path_id'])}",
            "",
            f"Provider: `{model['provider']}`  ",
            f"Thinking level: `{model['thinking']}`  ",
            f"Cohort: `linux-isolated-baseline`",
            "",
        ]
    )


def update_model_readme(state: dict[str, Any]) -> Path:
    path = ROOT / "evals" / "results" / state["model"]["path_id"] / "README.md"
    path.parent.mkdir(parents=True, exist_ok=True)
    existing = path.read_text(encoding="utf-8") if path.is_file() else default_model_readme_header(state)
    updated = replace_marked_section(existing, "campaign-index", model_readme_campaign_section(state))
    path.write_text(updated, encoding="utf-8")
    return path


def evals_readme_model_summary(state: dict[str, Any]) -> str:
    published, total = campaign_progress(state)
    model_id = state["model"]["path_id"]
    name = model_display_name(model_id)
    href = f"results/{model_id}/README.md"
    report_href = campaign_report_href(state)
    status = state["status"]
    suite_id = state["suite"]["id"]
    reliability = (ROOT / "evals" / "results" / model_id / "t1-playback-smoke-linux" / "trial-1" / "result.json").is_file()
    if published == total and status == "completed":
        campaign_detail = f"completed seven-task campaign `{suite_id}`"
    else:
        campaign_detail = f"campaign `{suite_id}` {status} ({published}/{total} tasks)"
    detail = campaign_detail
    if reliability:
        detail += "; T1 reliability cohort `1/3` trials"
    return f"- [{name}]({href}): {detail}; [campaign report]({report_href})."


def update_evals_readme(state: dict[str, Any]) -> Path:
    path = ROOT / "evals" / "README.md"
    content = path.read_text(encoding="utf-8")
    summary = evals_readme_model_summary(state)
    model_id = state["model"]["path_id"]
    model_href = f"results/{model_id}/README.md"
    content = re.sub(rf"^- \[.*?\]\({re.escape(model_href)}\):.*(?:\n|$)", "", content, flags=re.MULTILINE)
    marker = "## Current Results"
    if marker not in content:
        raise RuntimeError("evals_readme_missing_current_results")
    content = content.replace(marker, f"{marker}\n\n{summary}", 1)
    path.write_text(content, encoding="utf-8")
    return path


def update_readme_indexes(state: dict[str, Any]) -> tuple[Path, Path]:
    return update_evals_readme(state), update_model_readme(state)


def parse_campaign_status(campaign_md: str) -> str | None:
    match = re.search(r"Status: \*\*([a-z_]+)\*\*", campaign_md)
    return match.group(1) if match else None


def state_from_campaign_results(campaign_id: str, model_id: str = "gpt-5.4-nano") -> dict[str, Any]:
    suite_path = ROOT / "evals" / "suites" / "t1-t7-gpt-5.4-nano-medium.json"
    suite = load_suite(suite_path)
    model = dict(suite["requested_model"])
    root = campaign_results_root(campaign_id, model_id)
    if not root.is_dir():
        raise FileNotFoundError(campaign_id)
    campaign_md = (root / "campaign.md").read_text(encoding="utf-8") if (root / "campaign.md").is_file() else ""
    state: dict[str, Any] = {
        "campaign_id": campaign_id,
        "status": parse_campaign_status(campaign_md) or "prepared",
        "suite": {
            "id": suite["id"],
            "manifest_sha256": sha256(suite_path),
        },
        "model": {**model, "path_id": model_id},
        "budget": {
            "candidate_admission_cost_ceiling_usd": 1.0,
            "token_ceiling": 5_000_000,
            "combined_cost_usd": 0.0,
            "tokens": 0,
            "unknown_cost": False,
        },
        "tasks": [],
        "invalid_attempt_count": 0,
    }
    for ordinal, task_id in enumerate(EXPECTED_TASK_IDS, start=1):
        trial_dir = root / task_id / "trial-1"
        task: dict[str, Any] = {
            "id": task_id,
            "ordinal": ordinal,
            "status": "queued",
            "attempts": [],
            "published_path": None,
        }
        if trial_dir.is_dir() and (trial_dir / "result.json").is_file():
            result = read_json(trial_dir / "result.json")
            task["status"] = "published"
            task["published_path"] = str(trial_dir)
            task["attempts"] = [
                {
                    "validity": result.get("validity"),
                    "outcome": result.get("outcome"),
                    "score": result.get("score"),
                }
            ]
            cost = result.get("cost_usd", {})
            if isinstance(cost, dict) and isinstance(cost.get("combined"), (int, float)):
                state["budget"]["combined_cost_usd"] = round(
                    float(state["budget"]["combined_cost_usd"]) + float(cost["combined"]),
                    8,
                )
        state["tasks"].append(task)
    published, total = campaign_progress(state)
    if published == total:
        state["status"] = "completed"
    elif published and state["status"] not in {"completed", "blocked_infrastructure", "aborted_operator", "failed_evaluator"}:
        state["status"] = parse_campaign_status(campaign_md) or "prepared"
    return state


def index_campaign_results(campaign_id: str, model_id: str = "gpt-5.4-nano") -> tuple[Path, Path, Path]:
    state = state_from_campaign_results(campaign_id, model_id)
    campaign_path = write_campaign_report(state)
    evals_path, model_path = update_readme_indexes(state)
    return campaign_path, evals_path, model_path


def write_attempt_report(path: Path, markdown: str) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(markdown, encoding="utf-8")
