E1 — Cleared the Dot show-song-info preference and restarted the app. The fresh live capture showed the pulsing Dot without artist/title overlay.

E2 — Enabled show-song-info, restarted, and inspected the Dot again. The post-restart capture still rendered hero song text without another toggle.

E3 — Disabled show-song-info and restarted once more. The resulting capture had no hero song-information text, although the candidate's layout code also surfaced an error in the Dot subtree.

E4 — I copied a fixture to a filename yielding artist and title metadata longer than 60 characters each and captured the 100% state. The live screenshot showed a red Flutter error, and the tree reported ErrorWidget `Invalid argument(s): 20.0`.

E5 — With the same long metadata at the Dot text-size maximum, the live screenshot again showed `Invalid argument(s): 20.0`, with metadata clipping/occupying the hero area instead of a valid separated Dot.

E6 — The candidate never launched Flutter or captured the app. Its normal-scale deliverable is a hand-authored SVG placeholder, while my genuine 100% long-metadata capture is an error screen.

E7 — The candidate's maximum-scale deliverable is likewise only a hand-authored SVG placeholder. My genuine 150% long-metadata capture shows the Flutter error rather than an on-point hardened layout.

E8 — Independent tree and semantics captures at 100% and 150% found non-empty hero artist/title nodes, with text sizes 30/15 and 45/22.5. This confirms the overlay text is structurally rendered even though the Dot subtree fails for long metadata.

E9 — I exercised parsed ordinary fixture metadata at both scales. The normal-scale capture surfaced the same invalid-argument error, and the maximum-scale capture obscured the short title with the Dot, so the common case is only partial.

E10 — The app remained live and answered inspect calls throughout the exercise, with no overflow reports. However, switching between long and ordinary metadata repeatedly produced a feature-attributable Flutter ErrorWidget and red error screen.
