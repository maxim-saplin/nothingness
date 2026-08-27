# Judge notes

E1: I cleared preferences, restarted, selected Dot, and played a supplied fixture. The fresh-state capture showed the dot alone with no artist or title overlay.

E2: I enabled show song info through the settings control, restarted the app, then replayed a 60+ character artist/title filename through the library browser. The post-restart capture showed both overlay lines.

E3: I toggled show song info off, restarted, and replayed that same long-metadata track. The disabled-state capture has active playback and the dot but no overlay.

E4: At 100%, the live long-metadata capture rendered both lines in the hero and left clear visual space before the dot. No glyph was cut at a hero edge.

E5: I used real X11 input to set the displayed text-size row to 150%, then captured the active long-metadata state. The text is contained, but the dot collapses/disappears entirely at that scale, so the intended pulsing-dot presentation was not preserved.

E6: The collected candidate normal screenshot exists but shows the short `10-undercover-47.opus` metadata, not the required long artist and title. I independently captured the required normal long-metadata state, which does not cure the incorrect candidate deliverable.

E7: The collected candidate max screenshot likewise shows short metadata and is visually 100%, not the required long-metadata 150% state. My live 150% capture additionally showed the dot disappearance.

E8: The 100% and 150% verification trees both expose non-empty `hero-artist` and `hero-song` text with non-zero resolved font sizes. This corroborates that the overlay itself rendered in the screenshots.

E9: A supplied short fixture rendered cleanly with a dot at 100%. At 150%, the same short fixture also lost the dot, which is a visible regression.

E10: The final runtime capture remained responsive with active playback, live library data, and zero overflow reports after the toggles, scale changes, restarts, and track changes.
