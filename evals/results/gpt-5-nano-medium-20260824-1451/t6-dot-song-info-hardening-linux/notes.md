E1: I cleared the preference and restarted the candidate build; the Dot hero showed only the pulsing dot with no artist/title overlay.
E2: I enabled show-song-info and restarted; the overlay remained visible, proving the enabled preference persisted.
E3: I disabled show-song-info and restarted; the overlay stayed absent, proving the disabled state persisted too.
E4: With deliberately long artist and title metadata at 100%, my genuine screenshot showed the overlay text intersecting the centered pulsing dot.
E5: At 150%, the same long metadata still ran through the pulsing dot, so the requested hardening was not achieved.
E6: The candidate did not launch the app or submit a normal-scale screenshot; my fresh 100% capture documents the failing overlap.
E7: The candidate did not submit a maximum-scale screenshot; my fresh 150% capture documents the failing overlap.
E8: Probes and tree/semantics captures at normal and maximum scale showed non-empty artist/title text with non-zero sizes, including 30/15px and 45/22.5px text.
E9: Short fixture metadata rendered at both scales, but the artist text was visibly covered by the pulsing dot, indicating a common-case layout problem.
E10: I toggled the option, switched scales, and switched between long and short tracks repeatedly; the final runtime inspection found the app live with no overflow reports.
