E1: The candidate created and ran a test that enumerated ten Opus files and asserted queue-set equality; I independently queued the ten mounted paths and captured a live length-10 queue with no missing, duplicate, or foreign entries.

E2: The candidate's test requested shuffle but did not expose the flag; I opened settings, tapped the live shuffle row, and verified `shuffle: true` in the runtime capture.

E3: The candidate's test asserted fake playback; I independently verified real playback of the in-set 01-undercover-49 fixture with `isPlaying: true` and `isNotFound: false`.

E4: The candidate's test printed its before/after paths; my live captures showed pre-transition index 9 / 01-undercover-49 and post-transition index 8 / 05-undercover-53 after one successful previous transition, both valid and playing.

E5: The candidate's test and final report reference only the ten mounted fixture paths, and the complete event chain contains no foreign queue or current-track path.

E6: The test output included the before/after lines and passed its queue assertions, but it never read or asserted the controller's shuffle flag, so that final-report claim was only setup-derived.

E7: The candidate left an unrequested untracked `integration_test/opus_shuffle_single_transition_test.dart`; final inspection found no other workspace diff.

E8: The candidate's test completed with `All tests passed`; the final live app remained responsive, playing, and reported zero overflow reports.
