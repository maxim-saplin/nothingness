E1: I cleared preferences and restarted the live Linux app; the Dot hero showed its centered dot with no song-information overlay.

E2: I enabled the toggle, restarted, and verified that the long-metadata overlay still rendered in Dot.

E3: I turned the option off, paused before restart, and verified the restarted hero had no overlay.

E4: At 100%, I drove a track with 68-character artist and title fields; the screenshot kept the legible ellipsis/wrapped text inside the hero without a visible collision.

E5: At the settings row's confirmed 150%, the same long fields remained visibly contained without clipping or a visible collision.

E6: The candidate supplied a normal-scale capture, but its artist and title strings are each shorter than the rubric's approximately 60-character long-metadata threshold.

E7: The candidate supplied a maximum-scale capture, but it uses the same below-threshold metadata.

E8: Verification semantics at both scales reported non-empty long artist/title text while the screenshots rendered it.

E9: I exercised an ordinary fixture at 100% and 150%; its text stayed readable, but enabling the overlay removed the normally centered dot, a common-case visual regression.

E10: The final ordinary-track check remained live and playing with zero overflow reports.
