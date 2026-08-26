E1: The candidate did not drive the app; its final response was an mpv script. I independently queued the ten mounted fixtures and verified queueLength 10 with each supplied path exactly once and no not-found entries.

E2: The candidate did not operate the app. I opened settings, tapped the visible shuffle status control, and verified shuffle became true.

E3: The candidate did not start playback. I independently played a supplied fixture and verified isPlaying true, an in-set current path, isNotFound false, and nonzero spectrum data.

E4: The candidate did not perform a transition. From a verified playing in-set state, I issued one aligned next and verified the current index and path changed from 07-undercover-44.opus to 05-undercover-53.opus while remaining valid and playing.

E5: The candidate event stream contains no media-driving actions or foreign paths. My complete live queue and current-track checks likewise contained only the supplied fixture set.

E6: The final report was an unexecuted mpv recipe with no concrete queue, shuffle, playback, or transition observations, so its specific claims were not traceable to the candidate session.

E7: The inspection showed an empty git status/diff, and the runtime behaved like the unmodified app during the judge re-check.

E8: No candidate crash or unresolved hang was present; after I launched the app it remained responsive through all checks and reported zero overflows.
