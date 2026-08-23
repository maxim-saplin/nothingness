E1: The candidate left Dot show-song-info off by default; after clearing preferences and restarting, I verified a clean Dot-only hero.

E2: I enabled the setting and restarted; settings semantics still reported it on, and the overlay rendered once a track with artist/title metadata was playing.

E3: I toggled the setting off and restarted; retained track metadata produced no song-info overlay.

E4: I staged a filename-parsed track with artist and title each over 60 characters. At 100%, my fresh screenshot showed both wrapped text blocks fully inside the hero and separated from the pulsing dot.

E5: At 150% with that same track, my fresh screenshot showed Flutter's red ArgumentError page; the changed DotHero clamp used an invalid 20.0 lower bound for the available radius.

E6: A fresh normal-scale long-metadata capture was on-point, but the candidate's submitted normal screenshot visibly used only 01-undercover-49.opus short metadata.

E7: The candidate's submitted maximum screenshot likewise used short metadata and showed the red ArgumentError page, not the required long-metadata success state.

E8: Normal and maximum structural trees independently contained non-empty hero-artist and hero-song text, with sizes 30/15 and 45/22.5 respectively.

E9: The short fixture was clean at 100%, but the same enabled option at maximum scale triggered the ArgumentError, indicating a common-case regression.

E10: Runtime probes worked during most checks, but repeated Invalid argument(s): 20.0 errors appeared in the Flutter log and the app later died during restart, so the exercise was not crash-free.
