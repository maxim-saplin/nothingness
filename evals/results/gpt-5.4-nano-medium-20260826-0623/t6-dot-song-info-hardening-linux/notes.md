E1: I cleared preferences and cold-relaunched the Linux app; Dot showed no song-info overlay in the fresh state.
E2: I enabled the live settings toggle, restarted, and replayed a 68-character artist/title fixture; the overlay still rendered.
E3: I disabled that toggle, restarted, replayed the fixture, and the overlay stayed absent.
E4: My 100% long-metadata capture was contained and clear of the dot.
E5: My 150% long-metadata capture showed a yellow RenderFlex warning: bottom overflowed by 6.9 pixels.
E6: The candidate's normal screenshot exists, but its artist and title are only about 30 characters, not the required long case.
E7: The candidate's max screenshot has the same too-short metadata; the proper long-case reproduction overflowed.
E8: No successful structural text read was available at both scales.
E9: I checked 01-undercover-49 at 100% and 150%; both short-metadata captures were clean.
E10: The long 150% exercise surfaced the new RenderFlex overflow; later short-fixture checks remained responsive.
