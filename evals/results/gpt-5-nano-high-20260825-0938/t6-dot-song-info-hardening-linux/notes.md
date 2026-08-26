E1: Candidate preserved the default-off behavior. I cleared `screen_config_dot`, restarted, and verified the live Dot screenshot showed only the dot.

E2: The option persisted on restart. I enabled it, restarted, resumed the long-metadata track through the browser, and verified the overlay rendered.

E3: The option also persisted off. I disabled it, restarted, resumed the track, and verified the live hero had no overlay.

E4: At 100% with artist and title both over 60 characters, my fresh screenshot showed the overlay occupying the pulsing dot's region. This is unmet despite the text being visible.

E5: At 150%, my fresh screenshot showed both dot overlap and the title's lower line cut at the hero boundary.

E6: I captured a fresh normal-scale screenshot, but the candidate submitted no screenshot artifact; the fresh reproduction also fails the no-overlap criterion.

E7: I captured a fresh maximum-scale screenshot, but the candidate submitted no screenshot artifact; the fresh reproduction fails overlap and clipping criteria.

E8: Live tree/probe reads at both scales showed non-empty hero-artist and hero-song text with non-zero sizes (normal 30/15px and max 45/22.5px).

E9: The short fixture rendered at both scales without clipping, but the artist text was still visibly intersected by the centered dot, so this is only partial.

E10: After repeated toggles, restarts, scale changes, and long/short track switches, the app remained responsive; overflow reports were empty and final runtime inspection succeeded.
