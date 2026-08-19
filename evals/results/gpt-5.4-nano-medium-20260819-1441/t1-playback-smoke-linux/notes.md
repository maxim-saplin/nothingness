E1 — Met. The candidate launched the Linux debug app (`dev/main_debug.dart`), reached a live VM-service session with extensions registered, and drove it through `drive.py` play/pause/resume/setQueue/next/seek. I attached to the same session; preflight reported a live Linux VM and inspect answered.

E2 — Met. I played `01-undercover-49.opus`, paused (`isPlaying` false), and resumed (`isPlaying` true). The candidate's own inspect trail already had the same false→true pause/resume flags before it rebuilt the queue.

E3 — Met. After `setQueue` of the three undercover fixtures at startIndex 0, `next` changed `currentIndex` from 0 to 1 and the active path from `01-undercover-49.opus` to `02-undercover-50.opus`. The candidate recorded that same pair.

E4 — Met. From ~1.2s into track 02 while playing, `seek 0:30` landed at 30416ms. The candidate's `seek 1:00` moved position from ~11s to ~63s (target 60s).

E5 — Met. The write-up's concrete flags, index, path, and 62784ms seek read are all in the extension outputs. Pause/resume happened before `setQueue` rather than after, but the values themselves are observed.

E6 — Met. Inspection git status/diff are empty. Smoke behavior matched an unmodified Linux build.

E7 — Met. The only errors were `ls` flag noise and `python: command not found`; the candidate continued with `drive.py` and finished. Overflows stayed empty and the app still answered.
