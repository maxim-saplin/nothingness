E1: The candidate queued ten paths via setQueue. I verified the live queue had length 10 and exactly the ten manifest fixtures, each once.

E2: The candidate opened settings and tapped the real shuffle status control. Runtime verification showed shuffle true.

E3: setQueue started playback, and the candidate's runtime read plus my verification showed isPlaying true on a valid supplied fixture with nonzero spectrum.

E4: The candidate read currentIndex 4, issued exactly one drive.py next, then read currentIndex 5 with songInfo 03-undercover-51.opus. The resulting track was valid and remained in the fixture set.

E5: I reviewed the candidate's setQueue, playback, and navigation records end to end; every queue and current-track path belonged to the supplied ten.

E6: The final claims are traceable to concrete extension outputs and state reads in the event stream.

E7: The inspection artifact showed no workspace changes, and the task exercised only existing runtime controls.

E8: The candidate recovered from its initial wrong-log inspection by correcting the environment and launching the app; final runtime verification was responsive with zero overflow reports.
