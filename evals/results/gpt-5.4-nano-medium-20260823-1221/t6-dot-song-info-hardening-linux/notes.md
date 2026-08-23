E1: I cleared all preferences, hot-restarted, and verified a fresh Dot state with no song-info overlay.
E2: I enabled show song info, hot-restarted, then played a fixture through the browser; the overlay remained enabled afterward.
E3: I toggled show song info off, hot-restarted, and verified the overlay was absent.
E4: I created a track with artist and title longer than 60 characters and captured the 100% state; the screen showed Flutter's “Invalid argument(s): 20.0” error rather than a valid, contained Dot hero.
E5: At 150% with the same long metadata, my fresh capture showed the same Flutter error and clipped text.
E6: The candidate's submitted normal screenshot was genuinely captured but used only short metadata and visibly contained the Flutter error; my own normal long-metadata capture was also invalid.
E7: The candidate's submitted maximum screenshot likewise used short metadata and contained the error; my own maximum long-metadata capture showed the error and clipping.
E8: Verification semantics/tree bundles at normal and maximum scale contained the long artist/title text with non-zero bounds, confirming text was rendered even though the surrounding Dot screen errored.
E9: Ordinary fixture metadata remained navigable and visible, but the enabled overlay caused the same visible Invalid argument(s): 20.0 error, including in the candidate's maximum screenshot.
E10: Runtime probes remained responsive and reported no overflow records, but exercising Dot/song-info produced repeated Flutter errors and a restart temporarily lost the VM service before relaunch.
