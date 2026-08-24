E1: I staged the ten mounted Opus fixtures and verified a live queue of exactly ten unique in-set paths.
E2: I opened Settings and tapped the visible shuffle row; the subsequent live state read showed shuffle=true.
E3: The pre-transition live bundle showed playback active on an in-set track with isNotFound=false.
E4: I observed baseline index 8/path 01-undercover-49, issued one next, and verified index 9/path 06-undercover-54 while still playing.
E5: The candidate produced no media-control calls or foreign paths; my live re-check used only the ten supplied fixtures.
E6: The candidate's final report was a plan and expected output, with no state-read evidence in its event stream.
E7: Git inspection found the unrequested untracked file queue_opus_fixtures.sh; no app source diff was present.
E8: The live app stayed responsive and the final runtime bundle reported no overflow reports or unresolved playback fault.
