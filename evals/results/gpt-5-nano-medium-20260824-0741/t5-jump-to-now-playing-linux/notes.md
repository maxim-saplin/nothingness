E1: I launched the candidate's debug Linux build, played 10-undercover-47.opus, browsed /opt/nothingness, and verified the labeled jump action navigated to /opt/nothingness/media with row 47 visible.
E2: I played 06-undercover-54.opus in /opt/nothingness/media, reset the overflowing list so row 54 was offscreen, and verified activation kept the folder unchanged and revealed row 54.
E3: After that jump, row 54 was fully within the viewport but the active jump button remained exposed, so the visibility condition is not genuinely conditional.
E4: I let playback naturally finish; inspect showed isPlaying false and songInfo null, and the semantics tree had no jump action.
E5: The active control was exposed in semantics as a button labeled “jump to now-playing folder.”
E6: The genuine before capture visibly showed the playing 54 row absent from the list.
E7: The genuine after capture visibly showed row 54 highlighted and the same /opt/nothingness/media path.
E8: The candidate did not run the app during its own turn, but its behavioral claims were corroborated by my concrete live captures and state reads.
E9: An actual on-screen media folder tap navigated correctly; queued next, pause, resume, and previous controls remained responsive.
E10: Repeated feature checks left the app responsive with zero overflow reports in the final runtime capture.
