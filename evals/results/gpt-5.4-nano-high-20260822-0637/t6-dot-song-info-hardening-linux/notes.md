E1: I cleared all preferences, hot-restarted, and selected Dot. The fresh screenshot showed only the pulsing dot, and runtime reported songInfo null.

E2: I enabled show song info, paused before restart, hot-restarted, then replayed a track with 60+ character artist and title metadata. The overlay was still rendered after restart, proving persistence.

E3: I disabled show song info, paused and restarted, then replayed the same long-metadata track. The post-restart screenshot had no overlay and retained the pulsing dot.

E4: My fresh 100% long-metadata screenshot showed the artist and title fully inside the hero, with the pulsing dot visibly separated below.

E5: My fresh 150% screenshot kept the long text inside the hero with legible ellipsis/wrapping and no text/dot overlap. However, the structural tree and screenshot show the new layout collapsed the dot to 0x0, so the required pulsing dot is missing at this scale.

E6: I captured a new 100% screenshot after staging the long metadata and compared it with the candidate's submitted normal screenshot. Both were genuine, legible, and showed contained text without overlap.

E7: I captured a new 150% screenshot and compared it with the candidate's submitted max screenshot. Both showed the claimed long metadata and no clipping, but both also showed the dot absent because it was laid out at zero size.

E8: The normal and maximum verification bundles contained non-empty long artist/title semantics and tree structure. The maximum tree independently exposed the zero-size dot geometry.

E9: I replayed an ordinary fixture at 100% and 150%. The 100% view was clean with a dot, while at 150% the dot again disappeared, an obvious regression in the common case.

E10: I repeatedly toggled the option, restarted, changed scales, and switched long/short tracks. Final runtime inspection showed the app live and responsive with zero overflow reports.
