E1: The candidate preserved the default-off setting; after clearing preferences and restarting, I verified a live Dot screen with only the pulsing dot and no song-info overlay (verification-9d5b5c43aa564f59bfb678d2b016c61f).

E2: I enabled show song info, restarted, and verified the setting remained on and the overlay rendered afterward (verification-37a937da61a241a79f2a035af2aefd61).

E3: I toggled the option off, restarted, and verified the overlay stayed absent (verification-c0115d0bed124b3d8b6bbe280df40412).

E4: I created a filename-resolved track with artist and title longer than 60 characters and captured it at 100%; the black pulsing dot visibly intersects the artist text (verification-700d906ba05e4b0eba3401885eb05270).

E5: At the real 150% Dot text-size setting, the long-metadata capture shows a Flutter “Invalid argument(s): 20.0” error banner and the pulsing dot is not rendered (verification-7dcb53a7e7f848c8927e4aa1b7a332a1).

E6: The candidate’s submitted “normal” PNG is a Settings sheet at 3.00x rather than a 100% long-metadata hero screenshot; my own 100% capture also shows overlap (verification-700d906ba05e4b0eba3401885eb05270).

E7: The candidate’s submitted “max” PNG is a Settings sheet at 1.00x rather than a 150% long-metadata hero screenshot; my own 150% capture shows the rendering error (verification-7dcb53a7e7f848c8927e4aa1b7a332a1).

E8: The live normal- and maximum-scale bundles independently show the long artist/title strings in tree and semantics, confirming that the overlay text is genuinely rendered (verification-7dcb53a7e7f848c8927e4aa1b7a332a1).

E9: With ordinary fixture metadata, the overlay rendered at both scales, but the normal capture still overlaps the dot and the maximum-scale state retains the Invalid argument error (verification-41009560fab14f318d4bdbec483259e0).

E10: The app remained responsive and final inspection reported no recorded overflow reports, but exercising the maximum-scale layout visibly surfaced a new Flutter Invalid argument rendering error (verification-7dcb53a7e7f848c8927e4aa1b7a332a1).
