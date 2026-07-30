from __future__ import annotations

import argparse
import sys
import time
from datetime import UTC, datetime

from campaign_common import TERMINAL_STATUSES, campaign_elapsed_seconds, load_campaign_state


def money(value: object) -> str:
    return "unknown" if not isinstance(value, (int, float)) else f"${value:.4f}"


def integer(value: object) -> str:
    return f"{int(value):,}" if isinstance(value, (int, float)) else "unknown"


def duration(seconds: int) -> str:
    hours, remainder = divmod(max(0, seconds), 3600)
    minutes, seconds = divmod(remainder, 60)
    return f"{hours:02d}:{minutes:02d}:{seconds:02d}"


def age(value: object) -> str:
    if not isinstance(value, str):
        return "unknown"
    try:
        moment = datetime.fromisoformat(value.replace("Z", "+00:00"))
    except ValueError:
        return "unknown"
    seconds = max(0, int((datetime.now(UTC) - moment).total_seconds()))
    return f"{seconds}s ago" if seconds < 60 else f"{seconds // 60}m ago"


def render(campaign_id: str) -> tuple[str, bool]:
    state = load_campaign_state(campaign_id)
    current = state["current"]
    budget = state["budget"]
    task_index = int(current.get("task_index", 0)) + 1
    lines = [
        f"Campaign {campaign_id}",
        f"Status: {state['status']}",
        f"Task: {task_index}/7 {current.get('task_id', '—')} attempt {current.get('attempt', '—')}",
        f"Phase: {current.get('phase', '—')}",
        f"Run: {current.get('run_id') or '—'}",
        f"Elapsed: {duration(campaign_elapsed_seconds(state))}",
        f"Cleanup: {current.get('cleanup_status') or '—'}",
        "",
        "Budget",
        f"  Combined: {money(budget.get('combined_cost_usd'))} / {money(budget.get('candidate_admission_cost_ceiling_usd'))}",
        f"  Tokens: {integer(budget.get('tokens'))} / {integer(budget.get('token_ceiling'))}",
        f"  Unknown cost: {budget.get('unknown_cost')}",
        f"  Invalid attempts: {state.get('invalid_attempt_count', 0)}",
        "",
        "Tasks",
    ]
    for task in state["tasks"]:
        attempts = task.get("attempts") or []
        last = attempts[-1] if attempts else {}
        lines.append(
            f"  {task['ordinal']}. {task['id']}: {task['status']} "
            f"attempts={len(attempts)} validity={last.get('validity', '—')} outcome={last.get('outcome', '—')}"
        )
    if state["status"] in TERMINAL_STATUSES:
        lines.extend(["", "Terminal", f"  Reason: {state['status']}"])
    terminal = state["status"] in TERMINAL_STATUSES
    return "\n".join(lines), terminal


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("--campaign", required=True)
    parser.add_argument("--refresh", type=float, default=2.0)
    parser.add_argument("--once", action="store_true")
    arguments = parser.parse_args()
    while True:
        snapshot, terminal = render(arguments.campaign)
        sys.stdout.write(snapshot + "\n")
        sys.stdout.flush()
        if arguments.once or terminal:
            return
        time.sleep(max(0.5, arguments.refresh))


if __name__ == "__main__":
    main()
