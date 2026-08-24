E1: The candidate launched the Linux debug build and drove it through the VM-service extension surface. I independently confirmed a live Linux VM with 35 registered extensions and successful runtime captures.

E2: The candidate queued fixture audio and recorded pause=false and resume=true. My fresh captures showed the same playing → paused → playing transition.

E3: The candidate used a six-track queue and reported next to track 02 and prev to track 01. I independently reproduced next from index 0 to 1 and a clean prev from index 1 to 0, with both path and index changing.

E4: The candidate claimed `seek 1:30`, but its own inspect output recorded only 9770ms on an 84720ms track, so the requested target was not reached. I separately verified that a seek to 0:50 can work when the position is frozen afterward, but that does not rescue the candidate's reported 1:30 result.

E5: The candidate's reported queue, play/pause, skip, seek-position, and overflow values each had corresponding inspect output in its event stream. The seek value was traceable even though it contradicted the requested target.

E6: The candidate made no source changes; run inspection showed empty git status and diff. Fresh playback behavior was otherwise normal.

E7: The candidate encountered VM-discovery, malformed-command, and launch errors, then successfully launched/reconnected and reran the transport sequence before reporting results. No unresolved crash or hang remained.
