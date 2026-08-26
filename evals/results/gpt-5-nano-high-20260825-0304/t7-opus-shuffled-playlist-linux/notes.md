E1: The candidate did not drive the app, but my live verification queued exactly the ten supplied Opus paths once each and every entry was valid.
E2: I opened Settings and tapped the real shuffle status control; the subsequent runtime capture reported shuffle=true.
E3: I explicitly played a supplied fixture and verified isPlaying=true, a supplied current path, and isNotFound=false.
E4: From a live queue at index 0, one next command moved playback to index 1 and the resulting supplied fixture remained valid and playing.
E5: The candidate's own shell transcript listed only supplied fixture paths for its shuffle/ffplay script; no foreign path appeared.
E6: The candidate's report was not traceable to app state observations because it never launched or drove Flutter; it only ran an ffplay shell script.
E7: The app source behavior was unmodified, but the candidate created the functional untracked file opus_queue_and_one_transition.sh, which is outside the allowed non-functional artifacts.
E8: The live app stayed responsive and the final verification showed zero overflow reports; no unresolved candidate fault was present.
