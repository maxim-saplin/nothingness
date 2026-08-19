The candidate launched the Linux debug app, queued the ten mounted Opus fixtures once, opened settings and tapped the shuffle row, then called next once. I re-did that path on the still-live app rather than trusting the write-up.

E1: After my setQueue, inspect showed queueLength 10 and exactly the ten `/opt/nothingness/media/*-undercover-*.opus` paths, each once.

E2: I tapped `void-settings-status-shuffle` off (shuffle false) then on; the e2 verification bundle then read shuffle true.

E3/E4: Before next, isPlaying was true on `01-undercover-49.opus` (in-set, not-found false). One `next` moved currentIndex 8→9 and the current path to `02-undercover-50.opus`, still in-set.

E5: Session inspect/setQueue/next payloads only ever named those ten fixture paths as queued or current. `/sdcard/*.mp3` strings are from docs, not the queue.

E6: The final report’s before/after paths and indexes match the candidate’s own getPlaybackState reads (01 at index 8, then 06 at index 9 after next), and the shuffle tap is in the same session.

E7: Workspace git status/diff empty. No source edits.

E8: An early inspect against `/tmp/flutter_run.log` failed; the candidate switched to the tagged log, finished the drive, and overflows stayed empty. No crash left unrecovered.
