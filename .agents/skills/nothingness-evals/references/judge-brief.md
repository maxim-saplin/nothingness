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

## Turn discipline — the single most common way a judge loses its run

`judge-run.py start` takes **2–5 minutes** before the candidate is live. It is not stuck. Give it the
longest tool timeout your harness allows (10 minutes or more). It always starts a fresh run; never attach to an existing run.

**`observe` is a poll, not a wait.** It returns within about two minutes with
`"still_running": true` and the candidate's elapsed/budget, or earlier if the run reaches a terminal
phase. Call it in the **foreground**, look at what it returns, then call it again. That loop is the
whole supervision model: every return hands control back to you to check the clock and decide.

**Never background `observe`, and never raise `--timeout-seconds` to cover the whole run.** A call
that outlives your control of the session takes you out of the loop — the process keeps streaming into a log nobody
reads, and the candidate can run into its deadline with no one able to act. Three runs have been
lost exactly that way.

`candidate awaiting judge` means the candidate is **blocked**, burning its timeout until you call
`judge-control.py finish`. `judge-run.py observe` returns the moment that happens.

## Watch the clock — never let a candidate hit its deadline

**You do not have to wait for `awaiting_judge`.** `finish` has no phase guard: call it while the
candidate is still mid-turn and the run completes normally with `timed_out: false` and a
`judge_finish:` reason, which is exactly what `classify-run.py` needs to score it. The only effect of
finishing outside `awaiting_judge` is that the run cannot score `pass` — correct, since the candidate
never finished — but `partial` and `fail` are fully available.

A candidate killed at the wall is a different story: it never reaches `judge_finish:`, so the run is
`unassigned` and **scores nothing at all**. Record the operational failure as a retry and start the task fresh; never attach another judge to this run.

So: if the candidate is approaching its budget, **finish it yourself and score what exists**. Losing
the `pass` ceiling costs a candidate that was never going to pass nothing; losing the whole run costs
you the data point.

**`observe`'s `elapsed_seconds` is not wall clock — it tracks the last event's timestamp.** While a
candidate sits in a hung tool call it freezes, and `observe` returns instantly instead of polling for
~2 minutes. One judge saw 323s reported against an 1800s budget when ~11 real minutes had passed;
trusting it means believing you have 25 minutes of headroom when you have 13. Track the deadline from
`started_at` yourself.

The harness has its own deadline guard that auto-finishes at ~90% with `timed_out: false` and a
`judge_finish:` reason, so a run it catches still scores. If your own `finish` then returns
`judge_control_unavailable`, that means "already terminated" — success, not a blocker. Check the phase
before retrying.

You will not have to watch for this. **`judge-run.py observe` returns on its own at 90% of budget**
with `"deadline_warning": true` and a `next` that tells you to finish. When you see that, do not call
`observe` again hoping for `awaiting_judge` — call `judge-control.py finish` immediately, then page
events, then evidence/decide/publish as normal. Two campaigns each lost a run because a judge sat in
`observe` waiting for a handshake that the deadline arrived before.

## Evidence plumbing

- **Drive through `judge-verify.py` / `judge-inspect.py`, not raw `docker exec`.** Only those produce
  citable observation ids. Poking the container directly is fine for orientation, but anything you
  intend to cite has to be captured through the scripts or you will redo it.
- **Launch the app before capturing evidence.** `judge-run.py evidence` run while the app is not live
  yields only the screenshot lens with `runtime`/`tree`/`semantics` false, and `decide` then fails
  with `inspection_lenses_missing`. Launch first, then `judge-verify.py` per state, then
  `judge-inspect.py --runtime --git --processes`.
- Cite exactly **one** events observation per sequence range; the cited chain must be contiguous from
  sequence 0 to `terminal_event_sequence`. Skip zero-length batches. `judge-control.py finish`
  appends events, so page events again **after** finishing.
- **`decide_flags` can contain one events batch too many, as well as too few.** A zero-length batch
  turns up in it, and citing that breaks the chain with `event_coverage_not_contiguous`. Drop it.
- `judge-events.py` returns its own `observation_id` — cite that.
- **There is no judge takeover path.** If another judge or the parent was interrupted, record a retry
  and start the task fresh. Never attach to the old run or reuse its evidence.
- **`decide_flags` from `judge-run.py evidence` is a snapshot, not a running total.** It lists only
  the observations that existed when `evidence` ran. Rubrics whose "Drive:" lines require a capture
  per screen or per state mean several more `judge-verify.py --label ...` calls afterwards, and every
  one of those observation ids must be appended to `decide --observation-id ...` yourself. Miss one
  and `classify-run.py` fails with `cited_observation_unverified`. Keep your own list as you go.
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
- **`getSemantics` answers fully on this Linux build, and reaches nodes the tree truncates past.**
  Prefer it as your default lens, not just for the settings sheet. Call it as
  `ext.nothingness.getSemantics` via `drive.py call` — the bare name fails.
- **`settings open` returns before the sheet has painted, and `shoot` will rasterize the previous
  frame.** Same one-state lag on `settings close`. Sleep ~1s between any navigation and a `shoot`, and
  **open the resulting PNG** — checking its byte size proves nothing. (This is also a trap candidates
  fall into on their own; it is legitimate task difficulty, not something to warn them about.)
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
  **A key placed directly on the `GestureDetector` does not help** — one candidate added exactly that
  and `kind=touch` still moved nothing across four reproductions. This is not only the
  missing-`includeSelf` ancestor walk; do not go hunting for a better anchor.
- Use real X11 input via **XTEST** (`libXtst` is in the image, ~30 lines of `ctypes`). Holding the
  button down after the motion captures a genuine mid-gesture instant. Concrete geometry, so you do
  not rederive it: the Flutter client area sits at X11 offset **+1, +20**, the void hero spans
  y ≈ 0–228, and a press at **(450, 135)** lands on it.
- **`seek` is a no-op while PAUSED.** It replies `ok` with the requested `positionMs` while the
  reported position does not move (32170 → 32266 after a 0:45 seek). Seek only lands while playing.
  Two judges hit this; one nearly filed a false failure against a working implementation, because a
  paused seek reading unchanged looks exactly like "the gesture redraws but never seeks". Never freeze
  position by pausing before a seek test.
- **`SoLoudInvalidParameterException` on seeks that clamp to 0 or past the end is pre-existing.** A
  plain `drive.py seek 0` with no gesture reproduces it. It lands in the run log looking like a
  candidate-introduced crash. Do not charge it to a candidate.
- **Seek from mid-track, and expect the clamp.** A judge reported that leftward swipes never move
  the seek target back. The fixture's math is symmetric — `start + (accumDx / width) * duration`,
  clamped to `[0, duration]` — so the usual cause is starting near 0, where a backward swipe pins to
  0 and looks inert. Seek from a position well inside a long track before concluding anything
  directional, and say which position you started from.
- **Hold for at least 6 seconds if you want a mid-gesture capture.** `judge-verify.py` takes roughly
  3.5s to gather its whole bundle (screenshot + tree + semantics + settings + runtime), so a 1.5-2.5s
  hold lands *after* release and quietly captures the settled state instead. Call verify immediately,
  with no sleep before it, and give the hold room to outlast the bundle.
- Sliders cannot be activated by **synthetic** pointers at all — but they *are* reachable with XTEST.
  For the dot text-size slider: `settings open`, wheel button 5 about 18 notches, then a real click at
  the track's right end for 150% or its midpoint for 100%; the row's own value confirms where it
  landed. If you cannot reach a slider some other way, say so in your notes rather than scoring the
  candidate down for your own blind spot.
- **These docs describe harness HEAD; you are driving the pinned fixture.** Confirm any widget key
  with `git show <fixture-commit>:<path>` before relying on it.

## Metadata staging

`drive.py play` and `setQueue` build an `AudioTrack` from the bare filename with **no artist**
(`playTrackByPath`). To get real artist metadata, go through the library browser: `drive.py nav
<folder>`, then tap the `void-file:<path>` row. A judge who stages "long metadata" the easy way will
test the wrong case. To stage long metadata specifically, copy a fixture opus to
`"<long artist> - <long title>.opus"` and tap its browser row — the filename parser resolves both
fields.

Two transport quirks that will mislead you about what you are looking at:

- **`setQueue` starts playback by itself** (`isPlaying` true, spectrum non-zero, position already
  advancing). A candidate that never issued a `play` call may still have played audio for real; do not
  read a missing `play` as missing playback.
- **`playTrackByPath` does not sync `currentIndex` to the played track's queue position.** After
  playing queue-position 3, `currentIndex` still read 5, so the next `next` advanced to 6, not 4.
  Pre-existing; it will confuse anyone predicting the target track.

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
- **Any read that asserts the ABSENCE of a playback-gated affordance must capture `isPlaying` and
  `songInfo` in the same bundle as the semantics read.** One judge's "affordance absent" probe was
  really a fixture track that had ended mid-probe, silently turning it into a nothing-is-playing
  observation and nearly a false `unmet`.
- `decide` scores but does **not** publish. Run `decide`, then `publish` into your own sandbox. Do
  **not** run `finalize` — the manager does that.
- **`publish` writes to the repo root of the script you invoke, not your working directory.** Running
  the top-level `.agents/skills/.../judge-run.py` from inside your sandbox still publishes into the
  *shared* results tree, which is exactly what the sandbox exists to prevent. Invoke your sandbox's own
  copy of `judge-run.py`, then confirm your accepted task landed under your sandbox and not the shared repo.
- Write a `notes.md` on what the model actually did and what you verified; the report reads it.
