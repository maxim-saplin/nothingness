E1 — The live Linux app exposed the existing “jump to now-playing folder” action while browsing /opt/nothingness with 06-undercover-54 playing; tapping it navigated to /opt/nothingness/media and left the playing row visible.

E2 — In /opt/nothingness/media, the playing 54 row was outside the viewport at scrollPosition 151.6 while the new “jump to now-playing track” action was present. Tapping it kept the folder path unchanged and moved the list to scrollPosition 0.0 with row 54 visible.

E3 — After the same-folder jump, row 54 was fully inside the viewport, but the semantics capture still exposed the active “jump to now-playing track” action. This violates the requirement that a fully visible row have no active action.

E4 — A no-playing verification showed isPlaying false and songInfo null, and no jump action appeared in the semantics tree.

E5 — The active same-folder action was accessible through semantics with the distinguishing label “jump to now-playing track” and a tap action.

E6 — The candidate captured a genuine before PNG showing the browser collapsed and the playing row absent; my live pre-jump verification also captured the off-screen-row state with the action present.

E7 — The candidate’s genuine after PNG shows the same /opt/nothingness/media folder with rows through 54 visible, and my live post-jump screenshot confirmed row 54 visible after activation.

E8 — The candidate’s replay recorded playback, folder state, activation, and screenshots, but did not capture semantics or explicitly exercise the same-folder scrolled case; those claims were verified during judging rather than being fully traceable in its own session.

E9 — An actual folder-row tap navigated into /opt/nothingness/media, and pause/resume remained responsive. The candidate did not perform a complete ordinary playback-control sweep, and next/previous had no queued transition to demonstrate.

E10 — Repeated jump activations and live inspection left the app responsive; overflow reports remained empty and no feature-attributable crash surfaced.
