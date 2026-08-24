# T1 · Playback smoke (Linux) — judge notes

Run: `t1-t7-gpt-5.4-nano-low-t1-playback-smoke-linux-run-ad60139bf3dc`
Model: azure-openai-responses / gpt-5.4-nano / low. Candidate reached `awaiting_judge` on its own at ~247s (budget 1800s); 0 interventions.

## What the candidate did
It read the drive.py docs, launched the Flutter Linux debug build (one early "could not find Dart VM service URI" while the app was still building, then it succeeded), wrote a `.tmp/playback_smoke.txt` script, and ran it in one `drive.py replay`: `setQueue` of 3 opus fixtures, an inspect, pause, resume, next, an inspect, `seek 0:30`, an inspect, and `getAudioEvents`. Its final report summarized the observed values.

## What I verified myself (live, same session)
The candidate's app was still running, so I drove the identical live session (log `flutter_run_nothingness_linux_debug.log`, contract count=31).

- **E1 (met):** Extensions answer live right now; the session shows concrete play/pause/next/seek/inspect extension calls against the running build, not `flutter test` or a code description.
- **E2 (met):** I ran play/pause/resume with a verify capture at each step — isPlaying went true → false → true (obs afc7 / e5c5 / 15bd), matching the candidate's report.
- **E3 (met):** On a 3-track queue I loaded, `next` advanced currentIndex 0→1 and path `01-undercover-49`→`02-undercover-50` (obs 3518→cca0), shuffle off.
- **E4 (met):** Seeking from 14.5s to a 60s target moved playback forward to 64.2s (obs 9131→cca2; the seek RPC returned positionMs 60000, the extra ~4s is playback continuing during the capture bundle). The candidate's own session read songInfo.position 30362 after `seek 0:30`, within the ±2s tolerance.
- **E5 (met):** Every specific claim in the write-up traces to a real read in its own replay output (isPlaying flags, currentIndex 1 / path 02, positionMs 30000 / songInfo.position 30362, overflows.count 0).
- **E6 (met):** git status is empty — no source changes at all (not even the known GeneratedPluginRegistrant.swift regeneration appeared). Runtime behaviour matched an unmodified build.
- **E7 (met):** overflows.count 0, no crash/hang traces in the run log, and the same continuous session (PID 1077, up since 22:04) still answers — the early VM-URI retry resolved before any step was reported passed.

## Verdict
All 7 expectations met. No required expectation unmet; no interventions. A clean, correct, fully-verified playback smoke test.
