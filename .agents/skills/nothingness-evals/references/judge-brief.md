# Judge brief — pass this file to every judge, verbatim, every time

**Why this is frozen.** In the first campaign the manager learned the environment as it went and fed
each new lesson into the *next* judge's prompt. By the last task a judge received ten hard-won facts
that the first judge never had. Within one model that is merely uneven; across models it silently
breaks the comparison, because model B's t1 judge would be better equipped than model A's t1 judge
was. Every judge gets this same text or the leaderboard is not measuring the models.

Add nothing per-task except the assignment block. When you learn something new, **edit this file** so
the next campaign starts from it — do not paste it into one judge's prompt.

## Assignment (the only part that varies)

`suite_path`, `task_id`, `campaign_id`, `rubric_path`, the sandbox working directory, and
`NOTHINGNESS_EVAL_RUNS_ROOT` from `judge_environment`. Export that variable on **every** harness
command or you will look for your run inside your own worktree, where nothing creates one.

## Turn discipline — the single most common way a judge loses its trial

`judge-run.py start` takes **2–5 minutes** before the candidate is live. It is not stuck.

Give every long call (`start`, `observe`) the **maximum Bash timeout of 600000 ms**, and when one
returns with the trial still live, call it again immediately. A short timeout silently backgrounds
`observe` and ends your turn while the candidate keeps burning budget with nobody attached. That
happened once and needed manual rescue. **Never end your turn while the trial is live.**

`candidate awaiting judge` means the candidate is **blocked**, burning its timeout until you call
`judge-control.py finish`. `judge-run.py observe` returns the moment that happens.

## Watch the clock — never let a candidate hit its deadline

**You do not have to wait for `awaiting_judge`.** `finish` has no phase guard: call it while the
candidate is still mid-turn and the run completes normally with `timed_out: false` and a
`judge_finish:` reason, which is exactly what `classify-run.py` needs to score it. The only effect of
finishing outside `awaiting_judge` is that the run cannot score `pass` — correct, since the candidate
never finished — but `partial` and `fail` are fully available.

A candidate killed at the wall is a different story: it never reaches `judge_finish:`, so the run is
`unassigned` and **scores nothing at all**. In the first campaign that turned a fully-evidenced
`partial` into no data point and burned 45% of the campaign's spend for zero results.

So: if the candidate is approaching its budget (the watchdog warns at 90%), **finish it yourself and
score what exists**. Losing the `pass` ceiling costs a candidate that was never going to pass nothing;
losing the whole run costs you the data point.

## Evidence plumbing

- **Launch the app before capturing evidence.** `judge-run.py evidence` run while the app is not live
  yields only the screenshot lens with `runtime`/`tree`/`semantics` false, and `decide` then fails
  with `inspection_lenses_missing`. Launch first, then `judge-verify.py` per state, then
  `judge-inspect.py --runtime --git --processes`.
- Cite exactly **one** events observation per sequence range; the cited chain must be contiguous from
  sequence 0 to `terminal_event_sequence`. Skip zero-length batches. `judge-control.py finish`
  appends events, so page events again **after** finishing.
- `judge-events.py` returns its own `observation_id` — cite that.
- **Each expectation's `Evidence:` line in the rubric is a hard-enforced contract, not a hint.**
  Citing an `events-` observation where the line says `verification:runtime` is rejected at decide
  time with `evidence_kind_mismatch:<id>:requires_verification`. Read the evidence kind (and lens,
  where declared) off the rubric line before choosing what to cite, not after.

## Driving the Linux app in-container

- Launch needs `DISPLAY=:99` (Xvfb), not `:0`.
- `flutter pub get --offline` first, then a bare `flutter run`. There is no `--offline` flag on
  `flutter run`, and the recipe `drive.py preflight` prints dies on the egress allowlist without the
  pub step.
- Relaunching needs **both** `DRIVE_FLUTTER_FIFO` and `DRIVE_RUN_LOG` exported. Reads work off the
  run log alone, so reads keep working while `restart` breaks.
- **Pause before hot restart.** Hot restart during playback crashed the Linux build once with
  "Callback invoked after it has been deleted" in `libflutter_linux_gtk`. Pausing first is clean.
  Do not attribute that crash to the candidate.
- Time playback via `getAudioEvents`, not `inspect` cadence.

## Reading the UI

- **There is no paging out of this.** On the pinned fixture `getWidgetTree` takes only `depth` and
  truncates at 128,000 chars from the top; `skipLines=`/`maxChars=` are silently ignored (added later
  at harness HEAD). `getSemantics` is the only way to reach the settings rows.
- **Settings sheet: `getSemantics`, never `getWidgetTree`.** The tree exceeds the 128k cap with the
  sheet open and the rows fall past the cutoff. Consecutive `indexInParent` with abutting y-ranges is
  what proves adjacency. Note `drive.py tree N` takes N as a *line* count, not a depth.
- The settings `ListView` only builds ~20 children, so lower rows are unreachable by key. Background
  operating mode shortens the sheet; a real X11 wheel scroll also brings them into view.
- The browser list is a **reverse** `ListView`: wheel button 4 increases the scroll offset, button 5
  no-ops at position 0.

## Input — read this before claiming anything moved

- **Synthetic drags do not work on this build.** `kind=mouse` aborts with a `mouse_tracker.dart`
  assertion. **`kind=touch` returns a success payload while moving nothing.** Never accept a
  `dragByKey` success reply as evidence of movement; confirm against state or a fresh capture.
- Use real X11 input via **XTEST** (`libXtst` is in the image, ~30 lines of `ctypes`). Holding the
  button down after the motion captures a genuine mid-gesture instant.
- Sliders cannot be activated by synthetic pointers at all. Where a screen's only control is a text
  size slider, say so in your notes rather than scoring the candidate down for your own blind spot.
- **These docs describe harness HEAD; you are driving the pinned fixture.** Confirm any widget key
  with `git show <fixture-commit>:<path>` before relying on it.

## Metadata staging

`drive.py play` and `setQueue` build an `AudioTrack` from the bare filename with **no artist**
(`playTrackByPath`). To get real artist metadata, go through the library browser: `drive.py nav
<folder>`, then tap the `void-file:<path>` row. A judge who stages "long metadata" the easy way will
test the wrong case.

## Scoring discipline

- **You do not assert a score.** Write per-expectation verdicts (`met`/`partial`/`unmet`) with notes
  and evidence refs; `classify-run.py` computes `raw`/`penalty`/`adjusted`/band/outcome from those.
- **Judge the evidence separately from whether the code happens to work.** Candidates have shipped
  correct implementations while never launching the app, and have submitted "screenshots" that were
  `PIL.ImageDraw` paintings of a folder absent from the fixture. Check the event stream
  (`judge-query --grep` for `flutter run` / `drive.py`) for whether it ever ran the thing, and confirm
  claimed screenshots are genuine captures.
- Equally: do not punish correct work for the model's failure to prove it, and do not credit unproven
  claims. Score each expectation on its own evidence, against its own rubric line.
- `decide` scores but does **not** publish. Run `decide`, then `publish` into your own sandbox. Do
  **not** run `finalize` — the manager does that.
- Write a `notes.md` on what the model actually did and what you verified; the report reads it.
