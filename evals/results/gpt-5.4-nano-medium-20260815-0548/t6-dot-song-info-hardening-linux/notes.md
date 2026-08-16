E1 — Met. I deleted the isolated desktop config, cold-launched a fresh Linux app, selected Dot, and verified the hero showed only the pulsing dot with no artist/title overlay (verification-767c01d2462b40cfac697653a7ccac6b).

E2 — Met. I persisted show-song-info on, hot-restarted, played a deliberately long filename-derived metadata track, and verified the overlay was still rendered (verification-36e7a1201be0446b85b97a20b2677d10).

E3 — Met. I persisted show-song-info off, restarted, and verified the overlay disappeared (verification-b44b00f4fc954201a38105a0c31e916e).

E4 — Met. My fresh 100% screenshot with artist and title each over 60 characters kept all rendered text inside the hero and separated it above the dot (verification-36e7a1201be0446b85b97a20b2677d10).

E5 — Met. My fresh 150% screenshot showed the same long metadata inside the hero, above and non-overlapping with the centered dot, without clipped glyphs (verification-b71785fcbead4850bce8f092c9d507ab).

E6 — Unmet. The candidate's submitted dot_normal_after.png is genuine but depicts only short metadata, “undercover” and “47”, so it is not the required long-metadata normal-scale screenshot; my own fresh reproduction was on-point but cannot replace that missing candidate deliverable.

E7 — Unmet. The candidate's submitted dot_max_after.png likewise depicts only short metadata at maximum scale, so it is not the required long-metadata max-scale screenshot; my own fresh 150% reproduction was on-point but does not cure the candidate evidence failure.

E8 — Met. The normal and maximum verification bundles' tree reads contain non-empty hero-artist and hero-song text with the long resolved values, including explicit 45px and 22.5px text at max (verification-36e7a1201be0446b85b97a20b2677d10 and verification-b71785fcbead4850bce8f092c9d507ab).

E9 — Met. Fresh short-track checks at both 100% and 150% showed ordinary “undercover / 47” metadata cleanly, without clipping or overlap (verification-8b24896fcf4c41879a74f6973a25b91c and verification-cc9eb35710934028879f1f826fa53b30).

E10 — Met. After toggling, restarting, switching scales, and playing long and short tracks, the app stayed responsive; overflows were empty and the final runtime bundle reported active playback with no overflow reports (verification-cc9eb35710934028879f1f826fa53b30).
