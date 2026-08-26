E1: The candidate never launched or drove the real Linux app through the ext.nothingness VM-service surface. I verified the candidate container had no live VM and that its only new artifact was an integration test.

E2: The candidate did not issue live play, pause, or resume calls or capture runtime state. Its report describes assertions in an unrun test rather than observed transitions.

E3: The candidate did not stage a live multi-track queue or invoke next/previous. No index or active-path transition was observed.

E4: The candidate did not perform a live seek or verify a position change. The candidate explicitly encountered missing Flutter/Dart tooling, so its seek test never ran.

E5: The final report claims play/pause, skip, and seek behavior as what the added test would do, but no extension output or state read supports those claims.

E6: The candidate created the unrequested source file integration_test/smoke_play_pause_test.dart. The inspection showed that file as an untracked workspace change.

E7: The candidate noticed command-not-found failures but did not recover to a runnable app session or rerun the affected smoke test before finishing.
