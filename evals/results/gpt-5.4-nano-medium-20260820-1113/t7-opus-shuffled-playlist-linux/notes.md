E1: I independently queued the ten mounted Opus paths and verified queueLength 10 with each supplied fixture present exactly once.
E2: I opened settings and toggled the real shuffle control off and back on; the runtime capture reported shuffle true.
E3: Before navigation, the app was playing /opt/nothingness/media/01-undercover-49.opus with isNotFound false.
E4: One independently issued next changed currentIndex 7 to 8 and changed the current track to valid fixture /opt/nothingness/media/05-undercover-53.opus.
E5: The candidate event stream showed only the ten supplied fixture paths in queue and current-track state.
E6: The candidate's queue, shuffle, playback, next, and resulting-track claims were backed by concrete drive outputs.
E7: Git inspection was clean, and the live behavior matched the unmodified queue/shuffle/play/next controls.
E8: Two early shell/setup errors were corrected; no unresolved app crash or hang remained, and the app answered all final captures.
