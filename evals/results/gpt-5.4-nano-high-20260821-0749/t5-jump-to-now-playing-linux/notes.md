E1: I staged a playing track while browsing /opt/nothingness, confirmed the labeled jump action in semantics, tapped it, and verified the browser moved to /opt/nothingness/media with row 50 visible.
E2: I staged track 10/47, re-entered its already-current /opt/nothingness/media folder so the row was off-screen, and verified that no jump action appeared and the row stayed absent.
E3: I played track 05/53 and verified its entire row was visible within the list viewport; the semantics had no active jump action.
E4: I ended playback and verified isPlaying was false with songInfo null; no jump action was present in the semantics.
E5: In the active cross-folder state I verified the affordance was a real semantics button labeled “jump to now-playing folder,” not an unlabeled glyph.
E6: My stable before capture showed /opt/nothingness with the playing media row absent and the jump glyph visible.
E7: My stable after capture showed /opt/nothingness/media with the playing row 50 visible and highlighted.
E8: The candidate never produced a final write-up, so there were no behavioral claims needing traceability beyond the captured session events.
E9: I tapped the on-screen up and media folder rows and verified both folder transitions, then exercised pause, resume, next, and previous with a live two-track queue.
E10: After the navigation, playback, and jump checks, the live runtime still responded and reported no overflow entries.
