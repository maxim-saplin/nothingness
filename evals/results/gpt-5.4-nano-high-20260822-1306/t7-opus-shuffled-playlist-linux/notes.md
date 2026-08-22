E1: The candidate inspected source and wrote an integration test but did not run the requested queue flow. My live capture showed all ten supplied Opus paths exactly once and all entries resolvable.

E2: The candidate never toggled shuffle in the app. I opened settings, tapped the real shuffle status control, and verified shuffle=true in runtime state.

E3: The candidate did not establish playback through the driver. My live pre-transition capture showed active playback of fixture 01-undercover-49.opus with isNotFound=false.

E4: The candidate's test remained unresolved with no transition report. I performed one next transition and verified the index/path changed to fixture 02-undercover-50.opus, still valid and playing.

E5: The candidate event chain contains no foreign queue or current-track paths, and my live re-check used only the ten supplied fixtures.

E6: The candidate was stopped before producing a final report, so it made no candidate-specific claims that could be traced to observations.

E7: Inspection found the unrequested untracked integration_test/shuffle_opus_fixture_transition_test.dart file; runtime behavior otherwise remained the unmodified app behavior.

E8: The candidate left its second integration test in a long-running tool call. I relaunched the Linux app separately, confirmed it answered live calls, and observed zero overflow reports.
