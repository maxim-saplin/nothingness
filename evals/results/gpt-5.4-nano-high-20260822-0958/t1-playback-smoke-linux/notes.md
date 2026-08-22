E1: The candidate launched the Linux debug app and used the registered `ext.nothingness.*` VM-service surface. I independently reattached to the live session and captured a genuine runtime/semantics/screenshot bundle.

E2: Candidate state reads reported play=true, pause=false, and resume=true. My captures reproduced the same playing → paused → playing transition.

E3: The candidate issued `next` with an empty queue, which cleared playback, then directly played the second fixture. That is not the required next/prev transition on a multi-track queue, so this expectation is unmet.

E4: The candidate reported seeks to 0:30 and 1:00 with playing state and positions near the targets. I independently sought while playing to 1:00 and froze the resulting runtime capture at 61.301 seconds.

E5: The candidate’s behavioral claims are backed by extension command outputs and subsequent inspect reads in the contiguous event stream, including the failed empty-queue next behavior.

E6: The app behaved as an unmodified build during recheck, and final inspection reported an empty git status/diff. No candidate source edits were present.

E7: The candidate completed without an unresolved app crash or hang; the recheck remained responsive and reported zero overflow reports.
