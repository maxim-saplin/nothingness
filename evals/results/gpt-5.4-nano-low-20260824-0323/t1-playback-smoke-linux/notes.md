# Judge notes — t1-playback-smoke-linux · gpt-5.4-nano-low

**Run:** `t1-t7-gpt-5.4-nano-low-t1-playback-smoke-linux-run-32d09c9d158c`
**Campaign:** `gpt-5.4-nano-low-20260824-0623` · **Outcome:** `fail` (score 0, raw 0.143, penalty 0)

## What the candidate actually did

The candidate never drove the running app. Its whole session (25 bash tool calls) was
codebase exploration — `ls`, `find`, `grep`/`rg` over `lib/`, `dev/`, `integration_test/`,
reading `transport_row.dart`, `soloud_transport.dart`, `library_service.dart`, `main.dart`.
Then at ~138s it wrote a new file, `integration_test/smoke_playback_controls_test.dart`
(2965 bytes), and at ~140s ran `flutter test integration_test/smoke_playback_controls_test.dart`.

That `flutter test` hung. No further events arrived from ~208s of candidate time until the
harness **deadline guard force-finished the run at 1746s of the 1800s budget**
(`reason: "deadline_guard: supervisor finished at 1746s of 1800s"`, `timed_out: false`,
`judge_finish_phase: running`). `final_assistant_text` is `null` — the candidate produced
**no final report at all**.

Critically: the candidate issued **zero** `ext.nothingness.*` / `drive.py` calls, never ran
`flutter run`, never reached a drivable session, and captured **no state reads** of playing
status, track index, or position. Its entire testing approach was a `flutter test`
integration test — which the rubric explicitly names as a falsifier for E1.

## What I verified myself (live re-check)

I launched the real Linux build in the candidate's container myself
(`flutter pub get --offline` then `flutter run -d linux -t dev/main_debug.dart`, `DISPLAY=:99`)
and confirmed the app is unmodified and fully drivable — **31 VM-service extensions registered**:

- **Play/pause:** `setQueue` (3 opus tracks) started playback (`isPlaying=true`, idx 0);
  `pause` → `isPlaying=false`; `resume` → `isPlaying=true`.
- **Skip:** `next` advanced `currentIndex` 0→1→2 on the 3-track queue (`shuffle=false`).
- **Seek:** from position 0:19 (19018 ms), `seek 0:50` landed at 50885 ms — within ±2 s of
  the 50000 ms target and clearly forward. (A `seek 1:30` on an ~89 s track correctly
  clamped/ended and auto-advanced, as expected.)
- **No overflows**, `spectrumNonZero=true`, git status shows only the candidate's added test
  file (empty `diff_stat`).

So the app itself works perfectly; the failure is entirely the candidate's — it never
exercised it and never reported anything.

## Per-expectation verdicts

| Exp | Tier | Verdict | Why |
|-----|------|---------|-----|
| E1 | required | **unmet** | No extension/`drive.py` calls, no `flutter run`; `flutter test`-only approach that hung. |
| E2 | required | **unmet** | No play/pause transition observed by the candidate; no playing-flag read. |
| E3 | required | **unmet** | No `setQueue`/`next`/`prev`; no index/path change in session. |
| E4 | required | **unmet** | No seek call and no position read. |
| E5 | secondary | **unmet** | No report and no state reads; nothing traceable to an observation. |
| E6 | secondary | **partial** | Only diff is the added `integration_test/smoke_playback_controls_test.dart` (beyond the one permitted regeneration, which didn't occur); non-runtime, so partial not full fail. |
| E7 | secondary | **partial** | Unrecovered hang (`flutter test` never returned, no recovery), but no false "passed" narration layered over it. |

Four required expectations unmet → capped; aggregate lands at `fail`, score 0.

## Interventions / operational notes

- No interventions; unassisted run.
- My `judge-control.py finish` returned `judge_control_unavailable` because the harness
  deadline guard had already terminated the run (a scorable `timed_out:false` finish) — not a
  blocker.
- Evidence: cited a contiguous events chain (seq 0→2785, zero-length 2785→2785 batch dropped),
  one `inspection` (runtime/git/processes, git shows only the untracked test file), and one
  `verification` bundle (all five lenses genuine) from my live session.
