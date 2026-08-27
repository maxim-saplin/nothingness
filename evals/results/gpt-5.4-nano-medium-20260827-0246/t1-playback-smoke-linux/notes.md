E1: The candidate launched the debug Linux app and issued real `drive.py` extension calls; I confirmed a live extension-backed runtime after completion.
E2: The candidate reported resume then pause, and I independently captured true → false → true playing state around pause/resume.
E3: The candidate reported a ten-track next transition; I loaded three fixture tracks and confirmed index/path changed from 0/01 to 1/02 after next.
E4: The candidate reported a 30-second seek; I independently observed 6421 ms before and a frozen 30608 ms after a playing-state seek to 30000 ms.
E5: The candidate’s final queue, transition, skip, and seek values match its recorded extension-call outputs.
E6: The candidate left no workspace diff or untracked files.
E7: Startup readiness polling had transient no-VM responses, then succeeded; no unresolved runtime crash or hang remained.
