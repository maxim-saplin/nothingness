E1: The candidate launched the Linux debug app and used drive.py VM-service extensions; I independently attached and captured a live runtime bundle with the app answering.
E2: I played fixture track 01, captured isPlaying true, paused and captured false, then resumed and captured true.
E3: I loaded three mounted fixtures with setQueue; my captures showed currentIndex/path 0/track 01 before next and 1/track 02 after next.
E4: From a playing position near 10 seconds, I sought to 30 seconds and captured 30.416 seconds afterward, confirming a real forward seek.
E5: The candidate's report is traceable to its command outputs: playback flags, seek acknowledgements plus inspect reads, and the second track path.
E6: Inspection found an empty git status/diff, and the live behavior showed no task-unrelated runtime change.
E7: The candidate recovered from an early VM URI discovery miss by retrying until the contract succeeded; the app stayed responsive and final overflow reports were empty.
