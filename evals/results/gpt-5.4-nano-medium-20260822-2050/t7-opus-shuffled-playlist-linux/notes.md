E1: The candidate queued the ten mounted Opus fixtures, and my runtime capture confirmed queueLength 10 with each supplied path exactly once and no foreign entries.
E2: The candidate used the visible shuffle status control; after I re-toggled that control, the runtime capture confirmed shuffle true.
E3: I started a supplied fixture explicitly and verified isPlaying true with current path 01-undercover-49.opus and isNotFound false.
E4: From that playing state, I issued exactly one next command; the current path changed to 03-undercover-51.opus at a new index and remained valid and playing.
E5: The candidate event stream and my captures contain only the ten supplied fixture paths for queued/current media; no foreign media was played or queued.
E6: The candidate's final queue, shuffle, playback, and transition claims are supported by its inspect outputs and my independent runtime captures.
E7: Final judge inspection showed an empty git status and no diff, with only the requested runtime behavior exercised.
E8: The candidate encountered command/probe errors while working but recovered and completed against a live app; final verification and inspection showed zero overflow reports.
