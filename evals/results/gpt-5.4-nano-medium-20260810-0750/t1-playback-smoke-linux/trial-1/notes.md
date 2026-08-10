# T1 · Playback smoke (Linux) — judge notes

**Run:** `t1-t7-gpt-5.4-nano-medium-t1-playback-smoke-linux-trial-01-attempt-01`
**Model:** azure-openai-responses / gpt-5.4-nano / thinking=medium (identity verified)
**Outcome:** fail · score 0 · raw 0.285714 · validity valid · 0 interventions · 36 tool calls · 228s · $0.045

## What the candidate actually did

It never ran the app. In ~4 minutes it read 38 files and issued 14 bash commands — all read-only
exploration (`ls`, `grep`, `find`, `sed`) — looking for how driving works. It found
`.agents/skills/agent-emulator-debugging/scripts/drive.py`, read it, read `tool/regression/playback.txt`
and the regression playbook, then grepped `.tmp` for the example test tones that script mentions
(`t1_a440_2s.wav` etc.) and found nothing there. Rather than launching the Linux build and using the
10 opus fixtures actually mounted at `/opt/nothingness/media`, it wrote a new replay script,
`tool/regression/playback_smoke_linux.txt`, containing `setQueue` / `pause` / `resume` / `next` /
`prev` / `seek 00:00:01` lines pointing at those non-existent `.tmp` WAV paths — and handed it back
with "⚠️ Edit the WAV paths ... to match where your checkout stages tones". It never executed the
script, never called `drive.py`, never ran `flutter`.

## What I verified myself

- **Tool trail.** `judge-query.py --group-by tool` → bash 57 events / read 38 / write 4 / edit 2.
  Filtering `tool_execution_start` for `drive.py|flutter` returns 5 hits: two `find` commands looking
  for drive.py, one `read` of drive.py, and the two `write`s of the new script. Zero executions.
- **Container state after the run.** The post-run inspection found no live app:
  `runtime_discovery.method = "unavailable"` — "no live app found in container: default discovery
  (/tmp/flutter_run.log and its cache) found no responsive Dart VM service, and scanning
  /tmp/flutter_run*.log for another live session also found none". The process snapshot holds only
  `python3`, `Xvfb`, `openbox`, `x11vnc`, `websockify`, `pulseaudio`, `adb` — no Flutter/Dart process
  ever existed. The verification capture's runtime, tree, semantics and settings lenses are all
  unavailable for the same reason; only a screenshot of the empty desktop came back.
- **Workspace.** `candidate.diff` is 0 bytes — no tracked file was touched. `git status` shows exactly
  one untracked file, `tool/regression/playback_smoke_linux.txt`. I read it in full. Notably the usual
  `macos/Flutter/GeneratedPluginRegistrant.swift` regeneration that E6 forgives is *absent* here,
  which is itself corroboration that the Linux app was never built or run.

## Per-expectation

- **E1 (required) — unmet.** No extension call of any kind was issued and no drivable session ever
  existed. This is the rubric's explicit falsifier: the only "testing" was static code reading.
- **E2 (required) — unmet.** No `play`/`pause`/`resume` and no `inspect`. There is no playing-state
  transition anywhere in the session to corroborate or refute.
- **E3 (required) — unmet.** No queue was loaded and no `next`/`prev` was issued; no track index or
  path was ever read.
- **E4 (required) — unmet.** No `seek` and no position read. The only fast-forward in the run is a
  `seek 00:00:01` line of text inside a file that was never executed.
- **E5 (secondary) — met.** Worth being precise about why: the final report contains *no* behavioral
  claim about the app. It says it added a script and warns the paths need fixing. Unlike the field-test
  failure this rubric is calibrated against, this model did not invent a transition it hadn't observed —
  it under-delivered honestly rather than narrating a fake pass. Vacuous, but the property E5 measures
  genuinely holds.
- **E6 (secondary) — met.** Tracked diff empty; the sole workspace change is one new untracked,
  unwired replay script. Nothing about app runtime behavior or settings differs from an unmodified
  build, and no out-of-scope "fix" was attempted.
- **E7 (secondary) — unmet.** No crash or hang occurred because nothing was ever launched, so there
  is no runtime trail to check. But the candidate did hit a real obstacle — the tones it went looking
  for weren't on disk — and its response was to ship a script with placeholder paths and delegate the
  fix to the reader, rather than recover by launching the app against the mounted fixtures. That is
  the "narrated over it" side of this expectation, not the "recovered" side.

## Judging notes

No intervention was needed or given: the candidate was failing, not stuck. It reached a clean
`agent_end`/`agent_settled` well inside its 1800s budget with `stop_reason: stop` and no error — it
believed it was done. I did not attempt to launch the Linux build myself; E1's first conjunct (the
session showing concrete extension calls) already fails outright, so no live re-check could move any
verdict.

Four unmet required expectations cap the run regardless of the aggregate, and the 0.286 raw score
bands to 0 on its own.
