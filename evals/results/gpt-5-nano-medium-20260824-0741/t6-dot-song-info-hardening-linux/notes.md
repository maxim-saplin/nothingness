E1 — Cleared all preferences and restarted the live Linux app; the Dot screenshot showed only the pulsing dot and no overlay.

E2 — Enabled the Dot show-song-info toggle, restarted, and verified the overlay remained rendered afterward.

E3 — Disabled the toggle, restarted again, and verified the overlay stayed absent.

E4 — I staged artist and title strings over 60 characters and captured 100%; both overlay lines visibly pass behind/intersect the centered dot.

E5 — At 150%, the fresh screenshot still shows the artist text intersecting the dot, although long text is ellipsized.

E6 — A genuine 100% capture exists from my reproduction, but the candidate delivered no normal-scale screenshot and my capture does not support the claimed no-overlap result.

E7 — A genuine 150% capture exists from my reproduction, but the candidate delivered no max-scale screenshot and my capture shows overlap.

E8 — Live tree captures at normal and maximum scales contain non-empty hero-artist and hero-song Text nodes, corroborating that the overlay renders structurally.

E9 — Short fixture metadata rendered at both scales and the app stayed usable, but the artist text still visibly intersects the dot in both live screenshots.

E10 — After repeated preference toggles, restarts, scale changes, and long/short track switching, runtime inspection remained responsive with zero overflow reports.
