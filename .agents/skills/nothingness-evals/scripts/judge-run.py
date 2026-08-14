from __future__ import annotations

import argparse
import shutil
import subprocess
import sys
import time
import uuid
from pathlib import Path

from common import ROOT, RUNS_ROOT, SCRIPT_DIR, command, emit_json, fail, load_suite, read_json, run_dir, utc_now, validate_run_id, write_json

# Phases where the candidate has stopped and is waiting on the judge.
TERMINAL_PHASES = ("awaiting_judge", "completed", "timed_out", "failed")
# Fraction of the candidate's budget after which `observe` hands control back so
# the judge can finish the run itself rather than let it die at the wall.
DEADLINE_FRACTION = 0.9
PROGRESS_IN_CONTAINER = "/run/nothingness/progress.json"
OBSERVE_CURSOR_FILE = "observe-cursor.json"
# A poll interval, not a run length. `observe` used to default to the whole
# candidate budget, so it always outlasted the caller's 600s tool cap, always
# had to be backgrounded, and the agent's turn always ended -- after which
# nobody read its output and nobody could act on the deadline. Returning inside
# two minutes keeps the judge awake by construction: every call is a foreground
# call that comes back, and the judge takes a turn and decides again.
OBSERVE_DEFAULT_TIMEOUT = 120
OBSERVE_POLL_INTERVAL = 5.0


def invoke(name: str, *arguments: str) -> dict[str, object]:
    result = command([sys.executable, str(SCRIPT_DIR / name), *arguments], stdout=subprocess.PIPE, stderr=subprocess.PIPE)
    if result.returncode:
        detail = result.stderr.strip().splitlines()[-1] if result.stderr.strip() else "unknown"
        fail(result.returncode, f"{name}_failed:{detail}")
    try:
        return __import__("json").loads(result.stdout)
    except __import__("json").JSONDecodeError:
        fail(3, f"{name}_invalid_output")
    raise AssertionError("unreachable")


def retry_cost(run_id: str) -> float | None:
    run = run_dir(run_id)
    summary = run / "summary.json"
    if summary.is_file():
        value = read_json(summary).get("cost_usd", {}).get("combined")
        if isinstance(value, (int, float)):
            return float(value)
    admission = run / "admission.json"
    if admission.is_file():
        value = read_json(admission).get("normalized_usage", {}).get("cost_usd", {}).get("total")
        if isinstance(value, (int, float)):
            return float(value)
    return 0.0 if run.exists() else None


def start(arguments: argparse.Namespace) -> None:
    suite_path = arguments.suite.resolve()
    suite = load_suite(suite_path)
    run_id = f"{suite['id']}-{arguments.task_id}-run-{uuid.uuid4().hex[:12]}"
    validate_run_id(run_id)
    retry = 0
    registered = False
    if arguments.campaign:
        registration = invoke("campaign.py", "add-run", arguments.campaign, arguments.task_id, run_id)
        retry = int(registration["retry"])
        registered = True
    prepare_arguments = [arguments.task_id, run_id, "--suite", str(suite_path), "--retry", str(retry)]
    if arguments.judge:
        prepare_arguments.extend(("--judge", arguments.judge))
    if arguments.campaign:
        prepare_arguments.extend(("--campaign", arguments.campaign))
    try:
        prepared = invoke("prepare-run.py", *prepare_arguments)
        preflight = invoke("preflight.py", run_id)
        launch = invoke("launch-candidate.py", run_id)
    except BaseException:
        failed_cost = retry_cost(run_id)
        if (run_dir(run_id) / "run.json").is_file():
            try:
                invoke("cleanup.py", run_id)
            except BaseException:
                pass
        elif run_dir(run_id).exists():
            shutil.rmtree(run_dir(run_id), ignore_errors=True)
        if registered:
            try:
                retry_arguments = ["campaign.py", "retry", arguments.campaign, arguments.task_id, "--run-id", run_id, "--reason", "start_failed"]
                if failed_cost is not None:
                    retry_arguments.extend(("--cost-usd", str(failed_cost)))
                invoke(*retry_arguments)
            except BaseException:
                pass
        raise
    result = {"ok": True, "action": "start", "run_id": run_id, "suite_id": suite["id"], "task_id": arguments.task_id, "retry": retry, "requested_model": preflight["requested_model"], "selected_model": preflight["selected_model"], "identity_verified": preflight["identity_verified"], "novnc_url": prepared["novnc_url"], "preflight": preflight["ok"], "launch": launch["ok"], "judge_events_command": f"uv run python {SCRIPT_DIR.relative_to(ROOT)}/judge-events.py {run_id}", "started_at": utc_now()}
    if arguments.campaign:
        result["campaign_id"] = arguments.campaign
    write_json(run_dir(run_id) / "judge-start.json", result)
    emit_json(result)


def collect(arguments: argparse.Namespace) -> None:
    run = run_dir(arguments.run_id)
    if not (run / "run.json").is_file():
        fail(3, "run_not_prepared")
    completion = command(["docker", "exec", read_json(run / "run.json")["container"], "cat", "/run/nothingness/candidate-completion.json"], stdout=subprocess.PIPE, stderr=subprocess.DEVNULL)
    if completion.returncode:
        fail(4, "judge_must_finish_or_abort_candidate_before_collection")
    collected = invoke("collect.py", arguments.run_id)
    summary = invoke("summarize-run.py", arguments.run_id)
    emit_json({"ok": True, "action": "collect", "run_id": arguments.run_id, "collected": collected["ok"], "summary": summary})


def decide(arguments: argparse.Namespace) -> None:
    classify = [arguments.run_id, "--validity", arguments.validity]
    if arguments.scorecard:
        classify.extend(("--scorecard", arguments.scorecard))
    if arguments.notes:
        classify.extend(("--notes", arguments.notes))
    for observation_id in arguments.observation_id:
        classify.extend(("--observation-id", observation_id))
    invoke("classify-run.py", *classify)
    result = read_json(run_dir(arguments.run_id) / "result.json")
    # Deciding stops here. Publishing is the manager's, deliberately: the results
    # store stays single-writer, and a judge that cannot write it also cannot read
    # its way to another run's verdict before forming its own.
    emit_json({"ok": True, "action": "decide", "run_id": arguments.run_id, "result": result, "next": "manager runs publish-run.py"})


def publish(arguments: argparse.Namespace) -> None:
    """Manager-side. Moves a judged run into the committed results tree."""
    publish_arguments = [arguments.run_id]
    if arguments.scorecard:
        publish_arguments.extend(("--scorecard", arguments.scorecard))
    if arguments.force:
        publish_arguments.append("--force")
    emit_json({"ok": True, "action": "publish", "run_id": arguments.run_id, "published": invoke("publish-run.py", *publish_arguments)})


# What a judge needs to see to tell a working run from a failing one. Everything
# else pi emits -- turn_start/turn_end, tool_execution_end, streaming deltas --
# is protocol bookkeeping that multiplies line count without adding signal: a
# 36-second run with 4 tool calls emitted 730 events, so echoing all of them
# would bury the judge (and, for an agent judge, its context) in noise.
NOTABLE_EVENTS = frozenset({"tool_execution_start", "message_end", "retrying", "error", "agent_end", "agent_settled"})
TEXT_EXCERPT_CHARS = 200


def event_line(item: dict[str, object]) -> tuple[str, str] | None:
    payload = item.get("event") if isinstance(item.get("event"), dict) else {}
    kind = payload.get("type")
    if not isinstance(kind, str) or not kind:
        return None
    if kind == "tool_execution_start":
        # candidate.py records the tool under `toolName`; `name` is never set.
        return kind, str(payload.get("toolName") or payload.get("name") or "")
    if kind == "message_end":
        message = payload.get("message") if isinstance(payload.get("message"), dict) else {}
        blocks = message.get("content") if isinstance(message.get("content"), list) else []
        for block in blocks:
            if isinstance(block, dict) and block.get("type") == "text" and block.get("text"):
                return kind, " ".join(str(block["text"]).split())[:TEXT_EXCERPT_CHARS]
    return kind, ""


def event_digest(events: list[dict[str, object]], show: str, max_lines: int) -> list[str]:
    """A bounded, judge-controlled view of one batch.

    Evidence and display are deliberately different volumes: every event is
    still paged and hashed into the observation ledger (the coverage chain
    depends on it), but only what distinguishes a working run from a failing one
    is printed, collapsed and capped so a burst cannot flood the judge."""
    if show == "summary":
        return []
    selected = [item for item in events if show == "all" or (isinstance(item.get("event"), dict) and item["event"].get("type") in NOTABLE_EVENTS)]
    lines: list[str] = []
    for item in selected:
        parsed = event_line(item)
        if parsed is None:
            continue
        kind, detail = parsed
        # Collapse consecutive identical tool calls ("read x7") -- agents fan out
        # dozens of reads in a row and each one on its own line says nothing new.
        label = f"{kind}: {detail}" if detail else kind
        if lines and lines[-1][1] == label:
            lines[-1][2] += 1
        else:
            lines.append([item.get("sequence"), label, 1])
    rendered = [f"  [{sequence}] {label}" + (f" x{count}" if count > 1 else "") for sequence, label, count in lines]
    if len(rendered) > max_lines:
        hidden = len(rendered) - max_lines
        rendered = [*rendered[:max_lines], f"  ... +{hidden} more notable events (raw stream preserved in the observation ledger)"]
    return rendered


def live_progress(run: Path, metadata: dict[str, object]) -> dict[str, object] | None:
    """`progress.json` is written by the candidate *inside* its container and
    only reaches the host when `collect.py` archives it. Polling the run
    directory for it therefore never sees a live run at all -- the loop stays
    silent while the candidate works and never notices it finish. Read the
    archived copy if collection already happened, otherwise the container."""
    archived = run / "artifacts" / "progress.json"
    if archived.is_file():
        return read_json(archived)
    result = command(["docker", "exec", str(metadata["container"]), "cat", PROGRESS_IN_CONTAINER], stdout=subprocess.PIPE, stderr=subprocess.DEVNULL)
    if result.returncode:
        return None
    try:
        progress = __import__("json").loads(result.stdout)
    except __import__("json").JSONDecodeError:
        return None
    return progress if isinstance(progress, dict) else None


def observe(arguments: argparse.Namespace) -> None:
    """Watch a live run: page new events as they arrive, print what the
    candidate is actually doing, and return when it stops.

    This is the supervision loop, not a sleep. Blocking blindly until the
    candidate settles throws away the whole point of a judge -- seeing a run go
    wrong while it can still be steered -- and hand-rolled polling is how a
    finished candidate sits unnoticed burning its timeout. Paging here also
    means the cited event coverage is contiguous by construction, which is
    otherwise the single most error-prone part of deciding.

    Only pages when `progress.json` says new events exist: an empty batch still
    lands in the observation ledger and a zero-length range breaks the
    contiguity walk at decide time."""
    run = run_dir(arguments.run_id)
    metadata = read_json(run / "run.json")
    deadline = time.monotonic() + max(arguments.timeout_seconds, 1)
    # Resume where a previous invocation stopped. Observing is interruptible --
    # a judge that has to re-attach would otherwise re-page the stream from 0,
    # leaving two overlapping chains in the ledger and a contiguity walk that
    # cannot be satisfied by citing either one cleanly.
    saved = read_json(run / OBSERVE_CURSOR_FILE) if (run / OBSERVE_CURSOR_FILE).is_file() else {}
    cursor = saved.get("event_sequence") or 0
    observation_ids = list(saved.get("event_observation_ids") or [])
    phase = None
    while time.monotonic() < deadline:
        progress = live_progress(run, metadata)
        if isinstance(progress, dict):
            phase = progress.get("phase")
            sequence = progress.get("event_sequence")
            if isinstance(sequence, int) and sequence > cursor:
                batch = invoke("judge-events.py", arguments.run_id, "--after", str(cursor))
                events = batch.get("events") if isinstance(batch.get("events"), list) else []
                observation_ids.append(batch.get("observation_id"))
                cursor = batch.get("next_sequence") if isinstance(batch.get("next_sequence"), int) else cursor
                # Save after every poll, not only at the end: a watcher that is
                # interrupted mid-run is exactly the case resuming exists for, and
                # a cursor written only on the terminal path is never there when
                # it is needed.
                write_json(run / OBSERVE_CURSOR_FILE, {"event_sequence": cursor, "event_observation_ids": observation_ids})
                if not arguments.quiet:
                    header = f"[{phase} {progress.get('elapsed_seconds')}s tools={progress.get('tool_calls')} retries={progress.get('retries')} cost={progress.get('cost_usd')} seq={cursor}]"
                    print("\n".join([header, *event_digest(events, arguments.show, arguments.max_lines)]), file=sys.stderr, flush=True)
            budget = progress.get("timeout_seconds")
            elapsed = progress.get("elapsed_seconds")
            if (
                phase not in TERMINAL_PHASES
                and isinstance(budget, (int, float))
                and isinstance(elapsed, (int, float))
                and budget
                and elapsed > budget * DEADLINE_FRACTION
            ):
                # Finish the run here rather than advise someone to. Three runs
                # have now been lost this way: the candidate reaches its
                # deadline, never enters `awaiting_judge`, and `classify-run.py`
                # refuses to score a timed-out run at all, so a run with real
                # work in it becomes no data point.
                #
                # Advising did not work. `observe` returns its warning to a
                # process, and that process is typically a backgrounded shell
                # whose agent turn has already ended -- the last loss printed a
                # deadline warning into a log nobody was reading, while the
                # candidate sat hung on a single bash call it had given a
                # timeout as long as its whole budget.
                #
                # Finishing costs only the `pass` ceiling (classify refuses
                # `pass` unless the candidate reached `awaiting_judge` on its
                # own), which a candidate still mid-turn at this point was not
                # going to earn. Losing the run costs everything.
                # Deliberately not `invoke`: that aborts on a non-zero exit, and
                # the one case where finishing fails is a candidate already gone,
                # where crashing the watcher helps nobody. Degrade instead.
                control = command(
                    [sys.executable, str(SCRIPT_DIR / "judge-control.py"), arguments.run_id, "finish",
                     "--reason", f"deadline_guard: auto-finished at {elapsed:.0f}s of {budget:.0f}s to keep the run scoreable"],
                    stdout=subprocess.PIPE, stderr=subprocess.PIPE,
                )
                write_json(run / OBSERVE_CURSOR_FILE, {"event_sequence": cursor, "event_observation_ids": observation_ids})
                emit_json({
                    "ok": True, "action": "observe", "run_id": arguments.run_id, "phase": phase,
                    "deadline_warning": True, "auto_finished": control.returncode == 0,
                    "elapsed_seconds": elapsed, "timeout_seconds": budget,
                    "tool_calls": progress.get("tool_calls"), "cost_usd": progress.get("cost_usd"),
                    "event_sequence": cursor, "event_observation_ids": observation_ids,
                    "next": "The candidate was auto-finished at the deadline guard to keep this run scoreable -- it did NOT reach awaiting_judge on its own, so it cannot score `pass`. Page events again now (finish appends them), then evidence/decide/publish as normal, and say in your notes that the run was terminated by the guard.",
                })
                return
            if phase in TERMINAL_PHASES:
                # Persist the hand-off instead of asking a judge to copy a number
                # between two commands: a cursor read off the streaming digest
                # rather than this result is how a chain ends up non-contiguous.
                write_json(run / OBSERVE_CURSOR_FILE, {"event_sequence": cursor, "event_observation_ids": observation_ids})
                emit_json({"ok": True, "action": "observe", "run_id": arguments.run_id, "phase": phase, "elapsed_seconds": progress.get("elapsed_seconds"), "tool_calls": progress.get("tool_calls"), "cost_usd": progress.get("cost_usd"), "event_sequence": cursor, "event_observation_ids": observation_ids, "next": "judge-control.py finish, then judge-run.py evidence (cursor is saved; no flags needed)"})
                return
        time.sleep(arguments.poll_seconds)
    # Expiry is a normal poll result, not an error. Failing here made every
    # bounded call look like a broken one, which is why judges reached for a
    # single blocking call instead -- and then slept through the run.
    progress = live_progress(run, metadata) or {}
    write_json(run / OBSERVE_CURSOR_FILE, {"event_sequence": cursor, "event_observation_ids": observation_ids})
    emit_json({
        "ok": True, "action": "observe", "run_id": arguments.run_id, "phase": phase,
        "still_running": True,
        "elapsed_seconds": progress.get("elapsed_seconds"), "timeout_seconds": progress.get("timeout_seconds"),
        "tool_calls": progress.get("tool_calls"), "cost_usd": progress.get("cost_usd"),
        "event_sequence": cursor, "event_observation_ids": observation_ids,
        "next": "Candidate is still working. Call observe again to keep watching -- the cursor is saved, so polling costs nothing and never double-pages. Do not background it and do not walk away: each call returning is your turn to check the clock and finish if the candidate is close to its budget.",
    })


def evidence(arguments: argparse.Namespace) -> None:
    """Assemble the full citation set for `decide`, after `finish`.

    Deciding needs a contiguous event chain through the terminal sequence plus
    an inspection carrying all three lenses and a verification -- assembling
    that by hand is fiddly enough to have rejected real decisions twice over
    citation mechanics rather than judgement. `finish` itself appends events,
    so this pages the tail first, then captures the two remaining kinds, and
    prints the exact flags to pass."""
    run = run_dir(arguments.run_id)
    progress = live_progress(run, read_json(run / "run.json")) or {}
    saved = read_json(run / OBSERVE_CURSOR_FILE) if (run / OBSERVE_CURSOR_FILE).is_file() else {}
    cursor = arguments.after if arguments.after else (saved.get("event_sequence") or 0)
    observation_ids = list(arguments.event_observation_id) or list(saved.get("event_observation_ids") or [])
    # Page until the stream stops advancing, not once. judge-events.py caps a
    # batch at --limit, so a single call on a long run lands mid-stream and the
    # contiguity check rejects the chain -- leaving the judge to hand-walk
    # `--after` until it reaches the terminal sequence, which is exactly the
    # fiddliness this command exists to remove.
    while True:
        batch = invoke("judge-events.py", arguments.run_id, "--after", str(cursor))
        next_sequence = batch.get("next_sequence")
        if not isinstance(next_sequence, int) or next_sequence <= cursor:
            break
        observation_ids.append(batch.get("observation_id"))
        cursor = next_sequence
    inspection = invoke("judge-inspect.py", arguments.run_id, "--runtime", "--git", "--processes")
    verification = invoke("judge-verify.py", arguments.run_id, "--label", arguments.label)
    cited = [*observation_ids, inspection.get("observation_id"), verification.get("observation_id")]
    flags = " ".join(f"--observation-id {value}" for value in cited if value)
    emit_json({"ok": True, "action": "evidence", "run_id": arguments.run_id, "event_sequence": cursor, "observation_ids": cited, "decide_flags": flags, "verification_availability": verification.get("availability")})


def finalize(arguments: argparse.Namespace) -> None:
    """Manager-side. Merge the judge's published runs in, then aggregate.

    The judge publishes into its own sandbox, which only ever holds its own run,
    so it can write a result without being able to read anyone else's. Merging
    and aggregating are the manager's, and doing them in one command removes the
    class of bug where a campaign is "finished" but the index still says
    otherwise because someone forgot a step."""
    campaign_summary = invoke("campaign.py", "complete", arguments.campaign)
    campaign_manifest = read_json(RUNS_ROOT / "campaigns" / arguments.campaign / "campaign.json")
    merged = []
    current = command(["git", "-C", str(ROOT), "rev-parse", "HEAD"], stdout=subprocess.PIPE).stdout.strip()
    # One sandbox per judge, so a whole suite arrives as several -- accept a list
    # (and shell globs, e.g. `--from-sandbox .tmp/judge-*`) rather than making
    # the caller run finalize once per task and hope they remember all of them.
    for given in arguments.from_sandbox:
        sandbox = Path(given).expanduser().resolve()
        if not (sandbox / ".git").exists():
            fail(2, f"judge_sandbox_not_found:{given} -- create it: judge-sandbox.py create {given}")
        # A worktree is pinned to the commit it was created at, so a sandbox made
        # before a harness change silently runs stale scripts -- which is how a
        # judge published a run without the notes.md its own skill told it to
        # write. Refuse rather than merge results produced by unknown code.
        head = command(["git", "-C", str(sandbox), "rev-parse", "HEAD"], stdout=subprocess.PIPE).stdout.strip()
        if head and current and head != current:
            fail(2, f"judge_sandbox_stale:{head[:7]}_vs_{current[:7]} -- recreate it: judge-sandbox.py remove {given} && judge-sandbox.py create {given}")
        source_root = sandbox / "evals" / "results"
        if not source_root.is_dir():
            continue
        destination_root = ROOT / "evals" / "results"
        for run_directory in sorted(source_root.iterdir()):
            if not run_directory.is_dir():
                continue
            target = destination_root / run_directory.name
            for item in sorted(run_directory.rglob("*")):
                if not item.is_file():
                    continue
                landing = target / item.relative_to(run_directory)
                landing.parent.mkdir(parents=True, exist_ok=True)
                shutil.copy2(item, landing)
            target_campaign = target / "campaign.json"
            if not target_campaign.exists():
                write_json(target_campaign, campaign_manifest)
            merged.append(run_directory.name)
    reports = [invoke("report.py", str((ROOT / "evals" / "results" / name).relative_to(ROOT)), "--write") for name in sorted(set(merged) | set(arguments.run_directory))]
    board = invoke("leaderboard.py", "--write")
    emit_json({"ok": True, "action": "finalize", "campaign": campaign_summary, "merged": merged, "reports": [item.get("wrote") for item in reports], "index": board.get("wrote")})


def cleanup(arguments: argparse.Namespace) -> None:
    run = run_dir(arguments.run_id)
    if not (run / "result.json").is_file() and not arguments.force:
        fail(2, "judge_decision_required_before_cleanup")
    result = invoke("cleanup.py", arguments.run_id)
    emit_json({"ok": True, "action": "cleanup", "run_id": arguments.run_id, "cleanup": result})


def main() -> None:
    parser = argparse.ArgumentParser(allow_abbrev=False)
    subparsers = parser.add_subparsers(dest="action", required=True)
    start_parser = subparsers.add_parser("start", allow_abbrev=False)
    start_parser.add_argument("suite", type=Path)
    start_parser.add_argument("task_id")
    start_parser.add_argument("--judge", default="", help="who will score this run; recorded in run.json and result.json")
    start_parser.add_argument("--campaign", default="", help="campaign to record this run against, so the dashboard sees it without a second command")
    collect_parser = subparsers.add_parser("collect", allow_abbrev=False)
    collect_parser.add_argument("run_id")
    decide_parser = subparsers.add_parser("decide", allow_abbrev=False)
    decide_parser.add_argument("run_id")
    decide_parser.add_argument("--validity", required=True, choices=("valid", "invalid_infrastructure", "unassigned"))
    decide_parser.add_argument("--scorecard")
    decide_parser.add_argument("--notes", required=True)
    decide_parser.add_argument("--observation-id", action="append", default=[])
    observe_parser = subparsers.add_parser("observe", allow_abbrev=False)
    observe_parser.add_argument("run_id")
    observe_parser.add_argument("--timeout-seconds", type=int, default=OBSERVE_DEFAULT_TIMEOUT)
    observe_parser.add_argument("--poll-seconds", type=float, default=OBSERVE_POLL_INTERVAL)
    observe_parser.add_argument("--show", choices=("summary", "actions", "all"), default="actions", help="summary: rollup only; actions: tool calls, model text, retries and terminals (default); all: every event")
    observe_parser.add_argument("--max-lines", type=int, default=20, help="cap on digest lines per poll, so a burst cannot flood the judge")
    observe_parser.add_argument("--quiet", action="store_true", help="suppress the live digest entirely")
    evidence_parser = subparsers.add_parser("evidence", allow_abbrev=False)
    evidence_parser.add_argument("run_id")
    evidence_parser.add_argument("--after", type=int, default=0, help="last sequence already cited by observe")
    evidence_parser.add_argument("--event-observation-id", action="append", default=[], help="event observation ids observe already recorded")
    evidence_parser.add_argument("--label", default="post-run-state")
    publish_parser = subparsers.add_parser("publish", allow_abbrev=False)
    publish_parser.add_argument("run_id")
    publish_parser.add_argument("--scorecard")
    publish_parser.add_argument("--force", action="store_true")
    finalize_parser = subparsers.add_parser("finalize", allow_abbrev=False)
    finalize_parser.add_argument("--campaign", required=True, help="campaign to complete and finalize")
    finalize_parser.add_argument("--from-sandbox", action="append", default=[], help="judge worktree whose evals/results should be merged in first; repeatable, and accepts a shell glob")
    finalize_parser.add_argument("--run-directory", action="append", default=[], help="results directory name to (re)report, e.g. gpt-5.4-nano-medium-20260810")
    cleanup_parser = subparsers.add_parser("cleanup", allow_abbrev=False)
    cleanup_parser.add_argument("run_id")
    cleanup_parser.add_argument("--force", action="store_true")
    arguments = parser.parse_args()
    if hasattr(arguments, "run_id"):
        validate_run_id(arguments.run_id)
    {"start": start, "observe": observe, "evidence": evidence, "collect": collect, "decide": decide, "publish": publish, "finalize": finalize, "cleanup": cleanup}[arguments.action](arguments)


if __name__ == "__main__":
    main()