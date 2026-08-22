E1 — Cleared preferences and restarted the candidate app; the fresh Dot showed only its pulsing circle and no artist/title overlay.
E2 — Enabled “show song info,” hot-restarted, and verified the setting stayed on with the overlay rendered afterward.
E3 — Disabled the option, hot-restarted, and verified the overlay stayed off.
E4 — With a deliberately long artist and title at 100%, my genuine capture showed wrapped/ellipsized text inside the hero. The pulsing Dot was missing because the candidate’s radius clamp reduced it to zero, so this is only partial.
E5 — At 150%, the long overlay remained within the hero bounds in my genuine capture, but the centered pulsing Dot was again absent; partial.
E6 — I captured a fresh 100% long-metadata screenshot, but the candidate’s submitted normal screenshot used short “undercover / 49” metadata, so the submission requirement was unmet.
E7 — I captured a fresh 150% long-metadata screenshot, but the candidate’s submitted maximum screenshot used short “undercover / 51” metadata, so the submission requirement was unmet.
E8 — Verification trees independently showed non-empty hero-artist and hero-song text at both scales (30/15 at 100%; 45/22.5 at 150%).
E9 — Short metadata rendered without text clipping at both scales, but enabling song info removed the centered Dot in both captures, a common-case regression.
E10 — The final runtime stayed responsive with no overflow reports; final inspection showed the Flutter process and supporting processes still live.
