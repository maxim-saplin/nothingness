"""Create and remove the isolated worktree a judge scores from.

A judge must be able to write a result without being able to read anyone else's,
so it works in a git worktree with `evals/results/` deleted. Nothing it can see
carries another run's score, so it cannot anchor on one.

This used to be a two-command recipe in the manager's skill
(`git worktree add ... && rm -rf .../evals/results`), which is how both of its
failure modes got hit for real:

* A worktree is pinned to the commit it was created at. Made before a harness
  change, it silently runs stale scripts -- one such judge published a run
  without the `notes.md` its own skill told it to write, and the omission only
  surfaced as a blank section in the report. `create` refuses when the harness
  has uncommitted changes, because the sandbox would not contain them.
* `RUNS_ROOT` is derived from the repository root, so a judge in a worktree
  looks for its run under `<worktree>/.tmp/evals/` -- a path no script creates.
  Every judge spawned this way died on its first command. `create` returns the
  environment that repoints it, so the caller does not have to know this.
"""

from __future__ import annotations

import argparse
import shutil
import subprocess
from pathlib import Path

from common import ROOT, RUNS_ROOT, command, emit_json, fail

# Everything a judge executes. Uncommitted edits here would not exist in a
# worktree pinned to HEAD, so the judge would run code that is already gone.
HARNESS_PATHS = (".agents/skills/nothingness-evals", ".agents/skills/nothingness-eval-judge", "evals/image", "evals/tasks")


def dirty_harness_paths() -> list[str]:
    result = command(["git", "-C", str(ROOT), "status", "--porcelain", "--", *HARNESS_PATHS], stdout=subprocess.PIPE)
    return sorted({line[3:].strip() for line in result.stdout.splitlines() if line.strip()})


def create(arguments: argparse.Namespace) -> None:
    path = Path(arguments.path).expanduser()
    absolute = path if path.is_absolute() else ROOT / path
    if absolute.exists():
        fail(2, f"judge_sandbox_exists:{path} -- remove it first: judge-sandbox.py remove {path}")
    dirty = dirty_harness_paths()
    if dirty and not arguments.allow_dirty:
        files = ",".join(dirty[:5]) + ("..." if len(dirty) > 5 else "")
        fail(2, f"harness_uncommitted:{files} -- a worktree is pinned to HEAD and would not contain these; commit them, or pass --allow-dirty to score with the committed harness on purpose")
    command_result = command(["git", "-C", str(ROOT), "worktree", "add", "--detach", str(absolute), "HEAD"], stdout=subprocess.PIPE, stderr=subprocess.PIPE)
    if command_result.returncode != 0:
        fail(3, f"judge_sandbox_create_failed:{command_result.stderr.strip().splitlines()[-1] if command_result.stderr.strip() else 'unknown'}")
    shutil.rmtree(absolute / "evals" / "results", ignore_errors=True)
    remaining = sorted(item.name for item in (absolute / "evals" / "results").iterdir()) if (absolute / "evals" / "results").is_dir() else []
    if remaining:
        fail(3, f"judge_sandbox_not_blind:{','.join(remaining)}")
    head = command(["git", "-C", str(absolute), "rev-parse", "HEAD"], stdout=subprocess.PIPE).stdout.strip()
    emit_json(
        {
            "ok": True,
            "action": "create",
            "sandbox": str(absolute),
            "head": head,
            "results_visible": len(remaining),
            # The judge must run every harness command with this set, or it
            # cannot find the run it is scoring.
            "environment": {"NOTHINGNESS_EVAL_RUNS_ROOT": str(RUNS_ROOT)},
            "judge_working_directory": str(absolute),
        }
    )


def remove(arguments: argparse.Namespace) -> None:
    path = Path(arguments.path).expanduser()
    absolute = path if path.is_absolute() else ROOT / path
    command(["git", "-C", str(ROOT), "worktree", "remove", "--force", str(absolute)], stdout=subprocess.PIPE, stderr=subprocess.PIPE)
    shutil.rmtree(absolute, ignore_errors=True)
    command(["git", "-C", str(ROOT), "worktree", "prune"], stdout=subprocess.PIPE, stderr=subprocess.PIPE)
    emit_json({"ok": True, "action": "remove", "sandbox": str(absolute), "exists": absolute.exists()})


def main() -> None:
    parser = argparse.ArgumentParser(allow_abbrev=False, description=__doc__)
    subparsers = parser.add_subparsers(dest="action", required=True)
    create_parser = subparsers.add_parser("create", allow_abbrev=False)
    create_parser.add_argument("path", help="worktree path, e.g. .tmp/judge-t1")
    create_parser.add_argument("--allow-dirty", action="store_true", help="create even though the harness has uncommitted changes the sandbox will not contain")
    remove_parser = subparsers.add_parser("remove", allow_abbrev=False)
    remove_parser.add_argument("path")
    arguments = parser.parse_args()
    {"create": create, "remove": remove}[arguments.action](arguments)


if __name__ == "__main__":
    main()
