The candidate inspected the source for about two minutes, then stalled for roughly eight minutes in a recursive grep after `rg` was unavailable. It made no source changes, never launched the app, and submitted no screenshots; I finished the run as a scored judge finish and reproduced the relevant states in the unchanged checkout.

E1: I cleared all preferences, hot-restarted, selected Dot, and captured a fresh state. The screenshot contains only the pulsing dot, while runtime has no active song and the tree has no hero song overlay.

E2: I enabled show song info through the real settings row and hot-restarted. The resulting Dot screenshot shows the idle “nothingness” headline that is absent when the option is off, demonstrating the enabled preference survived restart.

E3: I toggled the option off, restarted again, and captured the result. The idle headline disappeared and the tree no longer contained HeroTitleBlock, confirming the disabled round trip.

E4: I copied a fixture to a filename producing artist and title strings longer than 60 characters, played it through the browser, and captured at 100%. The artist and title render at the top while the large pulsing dot occupies the same region, so the required separation fails.

E5: I moved the Dot text-size slider to 150% with real X11 input and captured the same long-metadata track. The larger artist/title still intersect the pulsing dot and the artist visibly ellipsizes, so maximum-scale hardening is absent.

E6: The candidate produced no normal-scale screenshot or other deliverable. My own verified 100% capture is genuine and shows the failure, but it cannot turn the missing candidate screenshot into a met expectation.

E7: The candidate produced no maximum-scale screenshot or other deliverable. My own verified 150% capture is genuine and shows the failure, but it cannot turn the missing candidate screenshot into a met expectation.

E8: Verified tree and semantics captures at normal and maximum scale contain non-empty hero-artist and hero-song text; sizes change from 30/15 to 45/22.5, independently corroborating both screenshots.

E9: I played the supplied short “undercover / 49” fixture at both scales. The artist text is also covered by the pulsing dot, so this unchanged implementation does not provide a clean common-case overlay.

E10: I repeatedly switched the option, scales, long fixture, and short fixtures. The final live runtime answered normally and reported zero overflow entries.
