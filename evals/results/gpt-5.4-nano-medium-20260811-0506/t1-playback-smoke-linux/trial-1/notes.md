# T1 · Playback smoke (Linux) — judge notes

Run: `t1-t7-gpt-5.4-nano-medium-t1-playback-smoke-linux-trial-01-attempt-04`
Model: `azure-openai-responses / gpt-5.4-nano` (thinking: medium), identity verified.
Outcome: **partial** (adjusted 0.714, no penalty). Interventions: **0**.
Candidate settled on its own at 291s of a 1800s budget; I finished it in `awaiting_judge`.

## What the candidate actually did

It read the repo's own regression tooling first (`tool/regression/README.md`, `smoke.txt`,
`playback.txt`, `drive.py`, `dev/agent_service.dart`), then decided to *extend the existing
`tool/regression/smoke.txt` replay script* with a playback section rather than issue transport calls
ad hoc. That section sets a 10-track queue from `/opt/nothingness/media` via
`ext.nothingness.setQueue`, then runs `resume` / `inspect` / `pause` / `inspect` / `resume` /
`seek 0:30` / `inspect` / `next` / `inspect` / `overflows`.

It launched the real app itself — `flutter run -d linux --debug -t dev/main_debug.dart` with the
fifo, run log and a sandboxed `DRIVE_DESKTOP_HOME` all exported — and drove it through `drive.py`.
It then ran the whole smoke script twice and reported done. Its final report is short and vague: it
lists the script steps and says only "playback transport actions succeeded and `overflows` reported
**0**", quoting no observed positions, indices or track names.

## E1 — met

Genuinely live. The candidate's own event stream shows `drive.py preflight`, `inspect`, `setQueue`,
`resume`, `pause`, `next`, `seek`, `overflows`, `screen`, `shoot`, `settings open/close` all
answering with real payloads. I confirmed the same session myself: `drive.py contract` lists 31
registered `ext.nothingness.*` extensions and a fresh `inspect` answers right now. It used
`dev/main_debug.dart`, the entrypoint that registers the extensions — not the `main_test.dart`
failure mode the rubric warns about.

## E2 — met

The candidate's three inspects bracket the transition correctly: `isPlaying` true at index 0, false
after `pause`, true again after `resume`. I reproduced the whole sequence live against the same
running app with labelled captures — `e2-playing` (true, pos 1728 ms), `e2-paused` (false, pos
4138 ms), `e2-resumed` (true, pos 5952 ms). Nothing assumed here.

## E3 — met

`setQueue` returned `queued: 10` and the following inspect shows `queueLength: 10`, `shuffle: false`
and the full queue array in the order passed, so the multi-track precondition was real. `next`
advanced `currentIndex` 0 → 1 with the active path changing `01-undercover-49.opus` →
`02-undercover-50.opus` in the candidate's own post-call inspect. I reproduced forward skips live
(`e3-pre-skip` index 0 / 01-undercover-49 → `e3-post-skip` index 1 / 02-undercover-50, then a second
`next` to index 2). I also tried `prev`: it restarted the current track rather than stepping back,
which is the documented >3s behaviour, not a defect — the candidate never exercised `prev`.

## E4 — unmet (this is what caps the run)

The candidate's script does the right thing structurally — it inspects immediately after `seek 0:30`
— but the read it captured says `position: 288`. Against a 30,000 ms target, from a pre-seek position
of 53 ms. The fast-forward simply did not take effect in its run, and the candidate reported the
transport actions as having succeeded anyway, taking the `seek` call's own `{"ok": true,
"positionMs": 30000}` reply as the result and never looking at the state read sitting directly below
it.

This is not an app defect, and I checked that carefully before scoring it:

- Seek while playing works. Direct `drive.py` pair: 84,501 ms → 30,042 ms for a `0:30` target.
  Labelled capture `e4-post-seek-playing`: 32,170 ms → 71,311 ms for a `1:10` target (the ~1.3s
  overshoot is the ~3.5s verify bundle running while playback continues).
- The candidate's *exact* sequence — setQueue, resume, pause, resume, seek 0:30, inspect — landed at
  30,042 ms in 3 of 3 reproductions just now.

So the candidate hit a genuine near-zero-position race (its first `resume` read only 53 ms in, versus
373–512 ms in my reproductions, so the source load was very likely still settling and reset position
to 0 after the seek applied). That race is exactly the kind of thing this task exists to catch, and
the candidate had the disconfirming evidence in hand.

One incidental build quirk I found while checking, which does **not** bear on this verdict because
the candidate's seek was issued while playing: `seek` is a no-op while **paused** — it replies
`ok` with the requested `positionMs`, but the reported position does not move (`e4-pre-seek` 32,170 ms
→ `e4-post-seek` 32,266 ms after a `0:45` seek). Worth knowing for future seek testing.

## E5 — partial

Most of the report is traceable: the launch command, the `replay` invocation and "overflows reported
0" all match real tool results in the session. But the blanket "playback transport actions succeeded"
covers the seek, whose only in-session observation contradicts it. The report also cites no observed
values whatsoever — no positions, no indices, no track names — which is precisely what let the
contradiction pass unnoticed. Nothing was fabricated; the failure is one unbacked aggregate claim
plus a write-up too thin to expose it.

## E6 — partial

The workspace diff is not empty: ` M tool/regression/smoke.txt`, 13 insertions and 1 deletion. The
task asked only to drive and smoke-test. In mitigation, the change is confined to a regression replay
script with no effect on app runtime behaviour — my live re-check of play/pause/skip/seek behaved
exactly as an unmodified build would — and it is arguably a reasonable engineering instinct
(extending the project's own harness rather than firing one-off calls). But it is still a tracked
source file touched beyond the single regeneration the rubric permits, so it scores `partial`.

Notable: the known `macos/Flutter/GeneratedPluginRegistrant.swift` and
`linux/flutter/generated_plugins.cmake` regenerations did **not** occur at all this run. The only
diff is the candidate's own edit.

## E7 — met

Two real faults, both noticed and both fixed before anything was reported done:

1. A 20-attempt `inspect` poll failed with `could not find Dart VM service URI` (the Linux build was
   still compiling). The candidate listed `/tmp`, tailed the run log, saw the compile in progress,
   and retried until `inspect` answered.
2. Its first `replay` exited code 1 on `error: No escaped character` — it had written the `setQueue`
   line with backslash line continuations, which `drive.py replay` does not support, so the playback
   section never ran that time. It read the file back, joined the line, and re-ran the entire script
   successfully. It did not report the first, broken run as a pass.

No crash or hang anywhere in the run log — the only errors are ALSA `No such file or directory`
noise, expected because the container has no audio device (SoLoud still clocks real-time). `overflows`
is 0 throughout. And the session answering me is demonstrably the same continuous one, not a silent
relaunch: before I touched anything it had free-run from the candidate's track 02 onward to track 03
at position 73,066 ms.

## Genuinely surprising

The candidate's methodology was better than its reading. It correctly discovered on its own — from
reading `dev/agent_service.dart` — that `play` maps to `playTrackByPath` and that a real queue needs
`setQueue`, which is the trap the rubric explicitly flags for E3, and it structured its script to
inspect after every transport call. It then failed on the one thing that structure existed to catch,
because it never read its own output.
