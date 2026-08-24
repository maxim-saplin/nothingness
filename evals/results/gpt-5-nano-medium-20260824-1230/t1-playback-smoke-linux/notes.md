E1 — The candidate only listed fixtures and wrote/ran a playerctl shell script; its complete event chain contains no live VM-service or ext.nothingness calls. I independently launched the debug Linux app and confirmed 31 extensions, but that was judge verification rather than candidate work.

E2 — The candidate did not test playback. My live captures verified play produced isPlaying=true, pause produced false, and resume restored true on the fixture track.

E3 — The candidate did not test skipping. I loaded three fixture tracks and verified next changed currentIndex/path from 0/01-undercover-49.opus to 1/02-undercover-50.opus while playing.

E4 — The candidate did not test fast-forward. Starting while playing near 10 seconds, I sought to 30 seconds and verified the resulting position was about 30.9 seconds.

E5 — The report's fixture listing, accessibility claim, and playerctl absence are supported by its own shell outputs; it explicitly said the playback actions were skipped rather than claiming they happened.

E6 — The candidate produced only the untracked smoke_test_linux_media.sh artifact; inspection showed no app source diff, and the independently run app retained normal behavior.

E7 — No app crash or hang occurred in the candidate session, and my live re-check remained responsive with zero overflow reports.
