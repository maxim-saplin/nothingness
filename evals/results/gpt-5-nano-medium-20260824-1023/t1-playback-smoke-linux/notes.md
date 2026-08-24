E1: The candidate inspected and edited source but never issued drive.py/ext.nothingness playback calls. I independently launched the debug Linux app and verified the extension surface was reachable.

E2: Independent live captures showed fixture playback with isPlaying=true, then pause with isPlaying=false, then resume with isPlaying=true. The candidate did not perform or observe this sequence.

E3: I loaded three fixture tracks and verified next changed currentIndex/path from 0/01-undercover-49.opus to 1/02-undercover-50.opus. The candidate did not drive the queue.

E4: While playing, I requested seek to 30 seconds and captured the active position at about 35 seconds, within tolerance. This was an independent judge action, not candidate evidence.

E5: The candidate's report asserted an automated sequence but supplied no state-read observations, and its event trail contains no corresponding drive calls.

E6: The independent app behavior was normal, but the candidate made an unrequested 39-line change to lib/main.dart. The final inspection records that source diff.

E7: The candidate's Flutter commands failed with command-not-found and it never recovered by launching a live app before reporting completion. The live app used for verification was launched by the judge.
