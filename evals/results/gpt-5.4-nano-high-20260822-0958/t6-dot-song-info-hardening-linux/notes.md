E1: I cleared the Dot screen preference and reloaded the Dot screen. The fresh screenshot showed the pulsing dot alone with no artist/title overlay.

E2: The option was visibly enabled during the live checks, but the candidate never completed a restart persistence check; its restart FIFO was unavailable after the deadline guard.

E3: I could not complete the required disable-then-restart round trip because the live Flutter restart path was unavailable.

E4: I staged a filename with 60-character artist and title metadata and captured the hero at 100%. The overlay wrapped/ellipsized within the hero and remained separated from the pulsing dot.

E5: At 150%, the fresh long-metadata capture showed both fields inside the hero with no visible clipping or overlap; the implementation reduced the dot to zero extent in this extreme case.

E6: My fresh normal-scale screenshot was genuine and on-point, but the candidate's own recorded screenshot used the short fixture rather than long metadata.

E7: My fresh maximum-scale screenshot was genuine and on-point, but the candidate did not submit a corresponding long-metadata maximum screenshot.

E8: Verification trees at both scales showed non-empty hero-artist and hero-song nodes; their text sizes changed from 30/15 at normal to 45/22.5 at maximum.

E9: Short fixture captures at 100% and 150% rendered cleanly, with the ordinary title and a visible separated dot and no clipping.

E10: The app remained responsive throughout the captures, and runtime inspection reported no overflow/error reports.

Operationally, the candidate was auto-finished by the deadline guard after its implementation and analyzer run; no judge interventions were delivered.
