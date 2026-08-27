E1: From `/opt/nothingness`, I activated the labeled action and verified that the browser returned to `/opt/nothingness/media` with row 54 on screen.

E2: I played row 54 while its parent was already open and the row was off screen, then tapped the glyph with XTEST; the path stayed `/opt/nothingness/media` and row 54 became visible.

E3: In that same-folder post-jump screenshot, row 54 is fully visible but the active jump glyph remains at bottom right.

E4: After pausing and hot restarting, runtime reported `songInfo: null`; the captured idle semantics had no active jump action.

E5: The active semantics node says “jump to now-playing track in browser,” so the glyph has a meaningful accessible identity.

E6: The candidate supplied genuine before captures whose named playing rows are absent from the visible browser list.

E7: The candidate's submitted after captures still omit the named playing rows, despite the claimed successful jump.

E8: The candidate did drive the app and capture state, but its final screenshot claim conflicts with the submitted after images.

E9: I used real on-screen taps to navigate up and back into `media`, then confirmed play, pause, and resume still responded.

E10: The live app remained responsive after repeated jumps and playback/navigation checks, with no overflow reports.
