E1: The isolated fresh app state was opened on Dot after preference initialization. The live screenshot showed only the pulsing dot, with no song-information overlay.

E2: I enabled “show song info,” hot-restarted the Linux app, and reopened settings. The post-restart semantics/settings capture still reported the toggle on.

E3: I turned the option off, hot-restarted again, and returned to Dot. The final live capture showed no song-information overlay.

E4: I copied a fixture to a filename yielding artist and title strings over 60 characters, played it through the browser, and captured at 100%. The rendered text visibly occupied the centered dot’s region.

E5: I moved the Dot text-size slider to 150% and verified the row value before returning to the hero. The maximum-scale screenshot still showed the long artist/title text intersecting the dot.

E6: No candidate screenshot deliverables were collected. My fresh 100% screenshot was genuine and on-point for the state, but visibly failed the no-overlap criterion.

E7: No candidate screenshot deliverables were collected. My fresh 150% screenshot was genuine and on-point for the state, but visibly failed the no-overlap criterion.

E8: The 100% and 150% verification bundles contained non-empty hero-artist and hero-song tree/semantics nodes. Their rendered text sizes were 30/15 and 45/22.5 respectively.

E9: I played a supplied short-metadata fixture and captured it at both scales. The ordinary artist text also occupied the pulsing dot’s region, so the requested clean common-case rendering was not observed.

E10: I repeatedly toggled the option, changed scales, and switched long and short tracks. The final live runtime inspection succeeded and reported zero overflow entries.
