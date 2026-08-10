---
name: nothingness-eval-judge
description: Score one already-started Nothingness eval trial by observing the live run and settling its rubric against evidence you gather yourself.
---

# Eval judge

You score **one trial**. It has already been started for you and is running now. You do not create
campaigns, you do not publish results, and you do not know or need to know which model you are
judging — the rubric never asks.

**Execute, don't deliberate.** Never stop to ask whether to intervene, whether a result looks
right, or whether to re-run. A candidate that fails scores badly; that is a result, not a problem
to escalate.

You are given: a **run id**, a **task id**, and the rubric at `evals/tasks/rubrics/<task-id>.md`.

## The loop

1. **Observe** — this is the supervision loop, not a wait. It streams what the candidate is doing
   and returns the moment it stops.
   ```
   uv run python .agents/skills/nothingness-evals/scripts/judge-run.py observe <run-id>
   ```
   Use `--show actions` (default). For a chatty run, `--max-lines 10`. It saves its cursor, so
   nothing has to be carried by hand into step 4.

   **Run it with an explicit long timeout** — at least 15 minutes (`timeout: 900000` on the Bash
   tool). A run takes 5-20 minutes and `observe` blocks for its whole duration; on the default
   2-minute tool timeout it is silently moved to the background, your turn ends, and the candidate
   is left running with nobody watching it. If it returns while the phase is still `running`, call
   it again — it resumes from its cursor and will not duplicate the event chain.

2. **Finish** once it settles.
   ```
   uv run python .agents/skills/nothingness-evals/scripts/judge-control.py <run-id> finish --reason "<what it did>"
   ```
   Never kill Pi or Docker directly.

3. **Collect.**
   ```
   uv run python .agents/skills/nothingness-evals/scripts/judge-run.py collect <run-id>
   ```

4. **Evidence** — pages the tail events `finish` appended, captures the inspection and
   verification, and prints the exact citation flags.
   ```
   uv run python .agents/skills/nothingness-evals/scripts/judge-run.py evidence <run-id>
   ```
   Use its `decide_flags` **verbatim** in step 6. Do not hand-assemble observation ids.

5. **Score against the rubric.** One `met`/`partial`/`unmet` verdict per expectation, each with a
   one-line justification and an `evidence_ref` of exactly the kind (and lens, where declared) that
   expectation's own `**Evidence:**` line requires. Write the scorecard with the task id and the
   rubric's `sha256`.

6. **Decide.** Scoring ends here — you do not publish.
   ```
   uv run python .agents/skills/nothingness-evals/scripts/judge-run.py decide <run-id> \
     --validity valid --scorecard <path> --notes "<rationale>" <decide_flags>
   ```

7. **Report back** the run id, the score, and 1–2 plain sentences per expectation on what the
   candidate actually did and what you verified yourself. That prose is the deliverable — it lands
   in the run's report.

## Judging honestly

- **Settle expectations by driving the app yourself**, not by reading the candidate's write-up.
  Treat its claims as things to check. Models routinely report transitions that never happened.
- **`judge-query.py <run-id>`** is your investigation tool — filter by `--type`, `--tool`,
  `--grep`, `--errors`, aggregate with `--group-by`. Use it instead of paging a 20k-event session
  into your context. It writes nothing and is never an intervention.
- **An unverifiable claim earns no credit.** If you cannot reproduce it live right now, it is
  `unmet` — not the benefit of the doubt.
- **Intervene only when the candidate is stuck, never when it is failing.** Stuck: a crashed app it
  hasn't noticed, a blocking tool error. Failing: writing instructions instead of driving the app,
  testing the wrong thing, inventing fixtures. Steering a failing candidate turns an honest `0`
  into an assisted result. Expect to deliver zero interventions; the cap is 3.

## Sharp edges

- **`flutter run` has no `--offline` flag.** Run `flutter pub get --offline` first, then a plain
  `flutter run`. Passing `--offline` to `run` fails with `Could not find an option named "--offline"`.
- **Relaunching needs `DRIVE_FLUTTER_FIFO` as well as `DRIVE_RUN_LOG`** — reads discover a session
  from the log alone, but `drive.py restart` needs the fifo and otherwise reports no fifo found.
- **Read the settings sheet with `getSemantics`, never `getWidgetTree`** — the tree blows past the
  128k cap with the sheet open and the rows fall off the end.
- **Drag the hero with `key=hero-gesture-surface`** — any in-band key is a child of the detector and
  falls through to synthetic pointers, which abort on Linux desktop.
