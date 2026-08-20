E1: The candidate changed the Linux seek preview wiring and captured `seek_during_swipe` images, but its event trail shows atomic `dragByKey` calls followed by delayed screenshots; no candidate-owned in-flight capture is traceable. My calibrated X11 verification later showed the bottom-line target/duration/progress text structurally, but that cannot satisfy this candidate-artifact expectation.
E2: A real X11 swipe verification showed the hero without the old centered time readout or tall vertical marker.
E3: After release, the independent screenshot returned the bottom line to `~`; the settled tree showed a null seek-preview state.
E4: The candidate did not produce two distinct live target samples; its two swipe sequences remained atomic calls with post-call screenshots.
E5: Starting a fresh 83.783-second track, a short calibrated rightward swipe committed playback around 18.36 seconds, matching the roughly 17.5-second target implied by the 200px movement.
E6: The candidate's required during-gesture screenshot deliverable was not traceable to an in-flight pointer interval; the recorded screenshot calls followed atomic drag calls and sleeps.
E7: The genuine post-gesture verification screenshot showed the normal folder marker and no seek readout or center indicator.
E8: The post-gesture tree independently agreed: it contained the normal `~` text and a null seek-preview tuple.
E9: An on-screen X11 play/pause tap toggled playing to paused, and the tree exposed previous/play/next controls. A combined previous/next probe ended with no active track, so all tap-zone transitions and vertical behavior were not fully established.
E10: Repeated calibrated real-X11 swipes left the app live and responsive; runtime verification reported zero overflow/error reports. The run was auto-finished by the deadline guard after the candidate's extensive exploration.
