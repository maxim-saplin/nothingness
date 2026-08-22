E1 — I cleared `screen_config_dot` and the legacy screen config, restarted, selected Dot, and captured a genuine fresh state. The screenshot shows the centered dot alone with no artist/title overlay.

E2 — I played a fixture through the library browser, enabled show song info, paused, and hot-restarted. The post-restart capture still renders `undercover` and `49` without retoggling.

E3 — I toggled show song info off, paused, and hot-restarted again. The loaded track remains present, but the post-restart Dot hero has no overlay.

E4 — I staged a filename with artist and title both over 60 characters and captured it at the confirmed 100% scale while playing. The text is inside the hero, but the structural capture reports the candidate's centered dot as a 0x0 container, so the dot was removed rather than kept clear of the text.

E5 — At confirmed 150%, the long artist/title text remains inside the hero. The max-scale tree and screenshot still show a 0x0/absent dot, which does not preserve the centered pulsing dot required by the task.

E6 — My own 100% screenshot is genuine and on-point. The candidate session never executed `drive.py shoot` (only `shoot --help`), and no candidate screenshot artifact exists.

E7 — My own 150% screenshot is genuine and on-point. The candidate did not provide a max-scale screenshot artifact.

E8 — The normal and max verification trees show non-empty hero artist/title text; the text sizes are 30/15 at normal and 45/22.5 at max.

E9 — The ordinary `undercover`/`49` fixture renders cleanly at both scales, but the same 0x0 dot regression is visible in both captures, so this is only partial.

E10 — I exercised toggles, restarts, both scales, long and short tracks, and cleared/read overflow reports. The final runtime/inspection was live and responsive, with active playback and zero overflow reports.
