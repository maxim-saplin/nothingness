E1: The candidate preserved the existing cross-folder crumb action. I drove it from /opt/nothingness and verified it navigated to /opt/nothingness/media with track 47 visible.

E2: In the already-correct media folder, I scrolled track 47 out of the viewport and saw the new accessible action. Activating it kept the folder unchanged and moved the list from scrollPosition 421.4 to 288.7, revealing row 47.

E3: I placed track 50 fully within the list viewport and captured its bounds as 0.0-37.6 within a 0.0-37.6 viewport. The active jump button was still exposed, so the visibility condition is too broad.

E4: After stopping playback, runtime reported isPlaying false and songInfo null, and the semantics tree contained no jump action.

E5: The active action was present in the semantics tree as a tappable button labeled “show now-playing track in browser”.

E6: The candidate supplied before_manual_2.png, but it shows the playing 49 row already visible rather than an offscreen pre-jump state.

E7: The candidate supplied after_manual_2.png, but it is pixel-identical to the before image and does not document a transition.

E8: Candidate inspect/getSemantics calls recorded the active label, paths, scroll positions, and row states, making the behavioral claims traceable to session observations.

E9: A real folder-row tap navigated correctly; pause/resume toggled playback and next/prev returned normally without destabilizing the app.

E10: Repeated live actions left the app responsive and final runtime/process inspection succeeded. Two RenderFlex overflow reports appeared during tiny-window testing, but no feature crash or new error was observed.
