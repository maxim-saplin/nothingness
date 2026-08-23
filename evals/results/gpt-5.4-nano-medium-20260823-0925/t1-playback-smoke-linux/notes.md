# T1 · Playback smoke (Linux) — judge notes

**Run:** `t1-t7-gpt-5.4-nano-medium-t1-playback-smoke-linux-run-ac909e508369`
**Model:** gpt-5.4-nano (thinking: medium) · **Outcome:** pass · **Score:** 3 (raw 1.0, no interventions)

## What the candidate did
It launched the real Linux build (after a few early relaunches where `flutter run` hadn't yet
printed the VM-service URI), attached the `ext.nothingness.*` extension surface, then drove a full
smoke test via `drive.py`: `setQueue` of all 10 fixture tracks at index 0, `play`, `pause`,
`resume`, `next`, and `seek 00:01:00`. It read `getPlaybackState`/`inspect` after each step and
reported the observed flags/positions rather than assuming them.

## What I verified myself (live, same container session)
I confirmed the session is still live — `drive.py contract` returned 31 registered extensions — and
reproduced every transition myself, capturing a `judge-verify.py` bundle at each state:

- **E1 (met):** Live isolate answering; extensions enumerable; full verification bundle captured
  (`verification-4f84c89e`). Not a `flutter test` run, not a code reading.
- **E2 (met):** Runtime lens read isPlaying=true at idx0 (`verification-4f84c89e`), isPlaying=false
  after `pause` (`verification-67499e34`), isPlaying=true after `resume` (`verification-fa6b6bda`).
  The full play→pause→resume transition, observed not assumed.
- **E3 (met):** On a queue at index 0 (01-undercover-49.opus), `next` advanced currentIndex 0→1 and
  the active path to 02-undercover-50.opus, still playing (`verification-3891951800`).
- **E4 (met):** From a pre-seek position of 25760ms on track02, `seek 0:50` landed at 50565ms —
  within +0.6s of the 50000ms target and clearly forward (`verification-f601eb50`). This is the
  exact failure the rubric warns about (a claimed FF that never moved), and here it genuinely moved.
- **E5 (met):** Every specific claim in the final report (queued:10, play true, pause false +
  spectrumNonZero false, resume true, next ok, seek positionMs:60000, final currentIndex:1
  pos 62698) traces to a `getPlaybackState`/`inspect` capture in the session's own event stream.
- **E6 (met):** Inspection git lens shows empty status and empty diff_stat — no source changes at
  all — and my live re-check behaved exactly like an unmodified build.
- **E7 (met):** The early VM-URI launch misses were recovered by relaunching until the isolate
  registered; `drive.py overflows` returned 0 reports and the run log had no crash/exception traces.
  The same session answers live now.

## Verdict
Clean, honest smoke test. All four required expectations met and all three secondary met → pass, 3.
