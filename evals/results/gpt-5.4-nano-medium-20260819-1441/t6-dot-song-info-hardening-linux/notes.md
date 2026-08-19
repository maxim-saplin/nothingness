E1 — Met. After wiping prefs and hot-restarting, I played a fixture on Dot with the option still default-off. The hero showed only the pulsing circle; hero-artist/hero-song were absent (verification-73873640904f423fb2bfee1e2eb36433).

E2 — Met. I toggled show song info on, restarted, then played a 62-character artist/title file via the library browser without touching the toggle again. The overlay came back with the long strings (verification-e7fa73012ced4184ad3bc04df3810be6).

E3 — Met. I set the toggle to off, restarted, and replayed undercover/49 while playing. The large pulsing circle returned and probeText reported no hero-artist widget (verification-e82db9a108a54abd92811167b3ed8275).

E4 — Met. At 100% text size the long overlay used maxLines/ellipsis, sat inside the hero, and did not occupy the pulsing circle (verification-cea736467166462e938de578adffa1d2). Tree size was 30px / 15px.

E5 — Met. At 150% (45px / 22.5px) the same long metadata still ellipsized inside the hero without overlapping the circle (verification-9ee697b5a7a044659fcb3274624a7745). The candidate shrinks the dot's max radius when the overlay is on, which is why the circle is small in those shots.

E6 — Unmet. I reproduced the 100% long-metadata state myself, but the candidate's submitted `dot_songinfo_text_normal.png` is a Void browser empty-folder capture of `07-undercover-44.opus`, not long metadata on Dot.

E7 — Unmet. Same gap at max scale: my 150% reproduction is on-point, but `dot_songinfo_text_max.png` is the same short-filename browser shot, not the required long-metadata overlay.

E8 — Met. Structural tree/probe reads exist at both scales with non-empty long hero-artist and hero-song text (100%: verification-cea736467166462e938de578adffa1d2; 150%: verification-6273a8b7cdfe4a77b0186464b8a1e992).

E9 — Met. Fixture track undercover/49 rendered a short overlay cleanly at 100% and 150% with no clipping or circle overlap (verification-e1a770167c5740d1a81b948f39dd419c and verification-2c933e6717b145aaa92a397ad9ff27c8).

E10 — Met. Through toggling, restarts, scale changes, and long/short playback the app stayed responsive; the final verification bundle still had isPlaying true and zero overflow reports (verification-e82db9a108a54abd92811167b3ed8275).
