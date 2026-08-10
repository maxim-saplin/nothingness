"""Detect trials that are running with nobody attached, and say so loudly.

The one thing that broke unattended operation in the first campaign: a judge
ended its turn mid-trial (a Bash timeout shorter than the run silently
backgrounds `observe`), leaving the candidate live, burning budget, with no
judge watching. Nothing notified anyone -- it was caught only because a human
happened to look. Everything else in the loop resumes itself.

One line per state change on stdout, so any harness that can stream a
long-running command will surface it -- or just run it in another terminal:

    uv run python .agents/skills/nothingness-evals/scripts/watchdog.py <campaign-id>

Exits when every task in the campaign has a scored result.
"""

from __future__ import annotations

import json
import subprocess
import sys
import time

from datetime import UTC, datetime

from common import RUNS_ROOT, container_name, emit_json, fail, read_json

CAMPAIGNS_ROOT = RUNS_ROOT / "campaigns"
STALL_SECONDS = 600.0
# `start` legitimately spends 2-5 minutes in prepare/preflight before the
# candidate exists, so this has to clear that without sitting on a real stall.
PREPARE_STALL_SECONDS = 480.0
POLL_SECONDS = 30.0


def container_uptime(run_id: str) -> float | None:
    """Seconds since this run's container started, or None if it is not running.

    Uptime, not the run directory's mtime: prepare writes files continuously, so
    the directory never looks old and a stall there was invisible.
    """
    result = subprocess.run(
        ["docker", "inspect", "-f", "{{.State.Running}} {{.State.StartedAt}}", container_name(run_id)],
        capture_output=True, text=True, check=False,
    )
    parts = result.stdout.split()
    if result.returncode or len(parts) != 2 or parts[0] != "true":
        return None
    started = parts[1].replace("Z", "+00:00")
    # Docker reports nanoseconds; datetime handles at most microseconds.
    if "." in started:
        head, _, tail = started.partition(".")
        fraction, sign, offset = tail.partition("+")
        started = f"{head}.{fraction[:6]}{sign}{offset}" if sign else f"{head}.{fraction[:6]}"
    try:
        return (datetime.now(UTC) - datetime.fromisoformat(started)).total_seconds()
    except ValueError:
        return None


def judge_attached(run_id: str) -> bool:
    """Is a judge actually watching this run right now?

    Checked by looking for its `observe` process, not by how recently
    `judge-observations.jsonl` was touched. That file is written when `observe`
    pages new events, not on a heartbeat, so a judge can be attached and correct
    while the log sits still for ten minutes -- which raised a false alarm on a
    perfectly healthy trial and sent me chasing it.
    """
    result = subprocess.run(
        ["pgrep", "-f", f"judge-run.py observe {run_id}"],
        capture_output=True, text=True, check=False,
    )
    return bool(result.stdout.strip())


def live_progress(run_id: str) -> dict | None:
    """The candidate's progress as it stands right now, read from the container.

    Not `artifacts/progress.json` on the host: that copy is made by `collect`,
    after the run is over. Watching the host path meant the phase checks could
    only ever see a finished run -- `awaiting_judge` and near-deadline, the two
    states worth interrupting for, were unobservable while they were true.
    """
    result = subprocess.run(
        ["docker", "exec", container_name(run_id), "cat", "/run/nothingness/progress.json"],
        capture_output=True, text=True, check=False,
    )
    if result.returncode:
        return None
    try:
        return json.loads(result.stdout)
    except json.JSONDecodeError:
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
            uptime = container_uptime(run)
            if uptime is None:
                continue
            live_any = True
            progress = live_progress(run)
            if progress is None:
                # No progress.json means the candidate has not been launched yet:
                # we are inside `start`'s prepare/preflight, which runs 2-5
                # minutes and is *the* phase where judges lose their turn to a
                # short Bash timeout. Skipping the run here left the watchdog
                # blind exactly when it was most needed -- a judge dropped out
                # mid-prepare and the container sat up for 13 minutes unnoticed.
                if uptime > PREPARE_STALL_SECONDS and not judge_attached(run):
                    say(f"{run}:prepare", f"STUCK-IN-START {run}: container up but no candidate launched after {PREPARE_STALL_SECONDS / 60:.0f} min -- judge likely ended its turn inside judge-run.py start; re-attach it")
                continue
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
            if phase not in {"completed", "awaiting_judge"} and observations.is_file() and not judge_attached(run):
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
