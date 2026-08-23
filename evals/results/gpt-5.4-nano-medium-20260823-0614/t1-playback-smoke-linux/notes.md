# Judge notes

## E1
The candidate launched the debug Linux app and exercised it through `drive.py` and the `ext.nothingness.*` VM extensions. I independently confirmed the live extension session and playback state.

## E2
The candidate's queue was playing, then its pause and resume calls returned and recorded `isPlaying=false` and `isPlaying=true`. My own captures reproduced the playing → paused → playing transition.

## E3
The candidate loaded two fixture tracks and reported `currentIndex=1` with the second path after `next`. My independent next capture showed the same index and path change while still playing.

## E4
The candidate sought forward and captured a later position, and my independent test sought while playing from 5,258 ms to 30,000 ms. The frozen post-seek capture read 30,693 ms, within tolerance and clearly ahead of the starting position.

## E5
The candidate's final report's queue, transport, seek, skip, and final-state claims are backed by its own `drive.py` action responses and inspect snapshots. The event chain contains the corresponding calls and reads.

## E6
The accepted run's workspace git status and diff were clean. The live replay showed only the requested playback behavior and no task-unrelated settings or runtime change.

## E7
The first VM readiness probe encountered a startup/readiness failure, then the candidate corrected the log discovery and reached a live extension session before repeating the smoke test. No unresolved crash or hang remained, and the final overflow count was zero.
