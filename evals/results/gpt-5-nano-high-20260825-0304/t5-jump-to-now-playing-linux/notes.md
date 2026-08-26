E1: I played fixture 10-undercover-47.opus, browsed /opt/nothingness, and activated the semantic jump control. The app returned to /opt/nothingness/media and showed row 47.

E2: With /opt/nothingness/media already open and row 47 off-screen, the jump control was available. Activating it kept the folder unchanged and scrolled row 47 into view.

E3: Once row 47 was fully visible, the same jump button remained active in the semantics tree. This fails the requested visibility conditional.

E4: After pausing and hot restarting, runtime showed isPlaying false and songInfo null. Captures in both the media and parent folders showed no active jump action.

E5: The active control was exposed as a semantic button labeled “jump to now-playing folder” with a tap action.

E6: The candidate’s before.png was inspected and was a generated text card, not a browser screenshot showing an off-screen playing row.

E7: The candidate’s after.png was the same generated text card and did not show the post-jump browser state.

E8: The candidate session did not launch or drive the app, and its concrete behavior and screenshot claims were not backed by live extension observations.

E9: An on-screen folder-row tap navigated correctly, and pause/resume plus next/previous commands responded while exercising playback.

E10: Repeated navigation, playback, and jump checks left the app responsive. Final runtime had no error and overflow reports were empty.
