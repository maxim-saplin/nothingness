"""Detect trials that are running with nobody attached, and say so loudly.

The one thing that broke unattended operation in the first campaign: a judge
ended its turn mid-trial (a Bash timeout shorter than the run silently
backgrounds `observe`), leaving the candidate live, burning budget, with no
judge watching. Nothing notified anyone -- it was caught only because a human
happened to look. Everything else in the loop resumes itself.

One line per state change, so it works as a `Monitor` command:

    uv run python .agents/skills/nothingness-evals/scripts/watchdog.py <campaign-id>

Exits when every task in the campaign has a scored result.
"""

from __future__ import annotations

import json
import subprocess
import sys
import time

from common import RUNS_ROOT, container_name, emit_json, fail, read_json

CAMPAIGNS_ROOT = RUNS_ROOT / "campaigns"
STALL_SECONDS = 600.0
POLL_SECONDS = 30.0


def container_is_up(run_id: str) -> bool:
    result = subprocess.run(
        ["docker", "ps", "--filter", f"name=^{container_name(run_id)}$", "--format", "{{.Names}}"],
        capture_output=True, text=True, check=False,
    )
    return bool(result.stdout.strip())


def maybe_json(path) -> dict | None:
    if not path.is_file():
        return None
    try:
        return json.loads(path.read_text())
    except (OSError, json.JSONDecodeError):
        return None


def campaign_state(campaign_id: str) -> tuple[list[str], dict[str, list[str]]]:
    """Tasks the suite demands, and the runs registered against each so far.

    Both halves matter: a task with no runs yet is *pending*, not done. Deriving
    "done" from the run list alone reports a campaign complete the moment it is
    created, before a single trial exists.
    """
    state_path = CAMPAIGNS_ROOT / campaign_id / "campaign.json"
    if not state_path.is_file():
        fail(4, "campaign_not_found")
    state = read_json(state_path)
    return list(state.get("tasks", [])), dict(state.get("runs", {}))


def main() -> None:
    if len(sys.argv) != 2:
        fail(2, "usage:watchdog_campaign_id")
    campaign_id = sys.argv[1]
    announced: set[str] = set()

    def say(key: str, message: str) -> None:
        """One alert per condition per run, ever.

        Keyed on the condition, never the text: an earlier version compared
        whole messages, and because the stall message carried a live minute
        count it re-fired on every poll -- a watchdog that cries every 30
        seconds is one you stop reading.
        """
        if key not in announced:
            announced.add(key)
            print(message, flush=True)

    while True:
        tasks, runs_by_task = campaign_state(campaign_id)
        # A task is done only when one of its runs carries a scored result --
        # the same rule campaign.py next uses, so the two never disagree.
        pending = [t for t in tasks if not any((RUNS_ROOT / r / "result.json").is_file() for r in runs_by_task.get(t, []))]
        unscored = [r for t in pending for r in runs_by_task.get(t, []) if not (RUNS_ROOT / r / "result.json").is_file()]
        live_any = False
        for run in unscored:
            progress = maybe_json(RUNS_ROOT / run / "artifacts" / "progress.json")
            if progress is None or not container_is_up(run):
                continue
            live_any = True
            phase = str(progress.get("phase", "unknown"))
            elapsed = float(progress.get("elapsed_seconds") or 0)
            budget = float(progress.get("timeout_seconds") or 0)

            if phase == "awaiting_judge":
                say(f"{run}:awaiting", f"BLOCKED {run}: candidate is awaiting_judge; it burns budget until a judge calls judge-control.py finish")
            elif budget and elapsed > budget * 0.9:
                say(f"{run}:wall", f"NEAR-DEADLINE {run}: {elapsed:.0f}s of {budget:.0f}s used -- tell the judge to call judge-control.py finish NOW and score what exists; a run killed at the wall is unscoreable, while finishing early only forfeits the pass ceiling")

            # Only meaningful while the candidate can still burn budget. After
            # `judge_finish` the phase is `completed` and a silent judge is just
            # composing its scorecard and notes -- neither writes an observation,
            # so the quiet clock would cry wolf on every single run.
            observations = RUNS_ROOT / run / "judge-observations.jsonl"
            if phase not in {"completed", "awaiting_judge"} and observations.is_file():
                quiet = time.time() - observations.stat().st_mtime
                if quiet > STALL_SECONDS:
                    say(f"{run}:stall", f"UNATTENDED {run}: candidate still {phase} but no judge observation for over {STALL_SECONDS / 60:.0f} min -- judge likely ended its turn; re-attach it")

        if not pending:
            emit_json({"ok": True, "campaign_id": campaign_id, "state": "done", "detail": f"all {len(tasks)} task(s) have a scored result"})
            return
        if not live_any:
            say("idle", f"IDLE {campaign_id}: {len(pending)} task(s) pending, no candidate container running -- the next task needs starting")
        time.sleep(POLL_SECONDS)


if __name__ == "__main__":
    main()
