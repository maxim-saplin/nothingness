E1: The candidate did not drive the app, but my live verification queued all ten mounted fixtures and confirmed queueLength 10 with each path exactly once.
E2: The candidate never enabled shuffle in-app; I opened settings and tapped the real shuffle status control, and the runtime then reported shuffle=true.
E3: My live pre-transition capture showed active playback (isPlaying=true, nonzero spectrum) on fixture 02-undercover-50.opus with isNotFound=false.
E4: I issued exactly one next from index 1/current fixture 02-undercover-50.opus; the current track changed to fixture 09-undercover-46.opus at index 2 and remained valid and playing.
E5: The candidate event stream only lists the ten supplied fixture paths in its generated shuffle list and attempted playback; no foreign path appears.
E6: The candidate's report is not traceable to app observations: it used shell/ffplay only and never called drive.py inspect, setQueue, shuffle, or next.
E7: Live behavior matched the baseline, but inspection found an extra untracked escaped run_fixture_shuffle.sh artifact beyond the allowed registrant regeneration.
E8: No unresolved app crash or hang was present; the candidate corrected its initial script-path failure, and my final runtime capture showed zero overflow reports.
