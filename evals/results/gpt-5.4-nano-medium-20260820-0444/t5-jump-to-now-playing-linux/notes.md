E1: I played 10-undercover-47.opus, browsed /opt/nothingness, and activated the accessible jump action. The live post-jump capture showed /opt/nothingness/media with row 47 fully visible.

E2: I reset the browser to /opt/nothingness/media with the playing row offscreen at scroll position 0. The live semantics capture showed no active jump action, and tapping the expected key failed, so the same-folder hardening was not present.

E3: After the successful cross-folder jump, row 47 was fully inside the list viewport and no active jump action was exposed.

E4: I checked idle states in both the media folder and its parent; runtime reported isPlaying false and songInfo null, with no jump affordance.

E5: In the active different-folder state, the semantics tree exposed a tappable action labeled “jump to now-playing track.”

E6: I retrieved and opened the candidate’s genuine before screenshot; the playing row was absent from the visible list while the media path remained shown. My own pre-jump verification reproduced an offscreen row state.

E7: I retrieved and opened the candidate’s genuine after screenshot; the target row was visible in the same media folder. My own post-jump verification showed the same visible-row result.

E8: The candidate’s event stream contains concrete inspect, semantics, screenshot, tap, and post-action state reads supporting the feature claims.

E9: An actual folder-row tap navigated correctly, and pause/resume/next worked with a queued browser-played track. Repeated previous checks did not change queue index 5, so ordinary playback coverage was only partial.

E10: The app stayed live throughout the feature and control checks. Overflows reported zero entries and the final runtime capture showed normal playback with no errors.
