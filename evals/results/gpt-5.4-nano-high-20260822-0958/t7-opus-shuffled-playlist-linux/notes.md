E1: The candidate inspected the queue implementation and wrote an integration test, but did not execute the requested queue flow. My live capture verified exactly ten supplied Opus paths, each once and all resolvable.

E2: The candidate never toggled shuffle in the app. I opened settings, activated the real shuffle control, and verified runtime shuffle=true.

E3: The candidate did not establish playback through the driver. My live runtime capture showed active playback of 01-undercover-49.opus with isNotFound=false.

E4: The candidate's test was still running when the run was finished, with no completed transition report. I performed one next transition and verified the current index/path changed to another valid supplied fixture.

E5: The candidate event stream contains no foreign queue or current-track paths; my live re-check also used only the ten supplied fixtures.

E6: The candidate produced no final report because it was stopped during a test command, so there are no candidate-specific claims backed by its own observations.

E7: Inspection found the unrequested untracked file integration_test/opus_fixture_shuffle_transition_test.dart, so the workspace was not unchanged.

E8: The candidate left a long-running integration test unresolved. I relaunched the Linux app separately; it responded normally and reported zero overflow records.
