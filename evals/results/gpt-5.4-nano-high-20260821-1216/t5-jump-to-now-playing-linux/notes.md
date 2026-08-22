E1 — met. I played track 44, browsed /opt/nothingness, and verified the accessible jump action navigated to /opt/nothingness/media with row 44 visible and highlighted (verification-3b718ce754d84ff7b780e0d08d5525d0; verification-fbc195e26a5e4da3beb0cd2cdfbc5a42).

E2 — met. With /opt/nothingness/media already open, track 47 was offscreen and the action was available; activation preserved the folder and scrolled row 47 into view (verification-67aafdf1529b4526bf646f6833b24e50; verification-bc80f86da2f444c4b9a544b7661df900).

E3 — met. The post-jump semantics and screenshot showed row 47 fully within the list viewport, and no active jump affordance was exposed.

E4 — met. In the media folder, isPlaying was false and songInfo was null and no jump action appeared; a second no-playing capture at /opt/nothingness likewise exposed no active jump action (verification-485983509dd14f8ca6c9c954a4cbca3b; verification-210f2e93824d4b54bed3910970360436).

E5 — met. The active action appeared in semantics as a button labeled with the folder and “jump to now-playing track,” giving it a distinguishing accessible identity (verification-3b718ce754d84ff7b780e0d08d5525d0).

E6 — met. The before screenshot plainly showed track 47 playing while the visible list started at later rows and did not contain 47 (verification-67aafdf1529b4526bf646f6833b24e50).

E7 — met. The after screenshot showed highlighted row 47 in the same /opt/nothingness/media folder (verification-bc80f86da2f444c4b9a544b7661df900).

E8 — partial. The candidate’s reload/play/tap/screenshot sequence is present in the contiguous event stream, but the final candidate session did not capture a browser semantics/runtime read proving the idle affordance was absent; its idle inspect was at an unregistered library state (events-aded13a946dd43c1a2bde64339182f9f).

E9 — met. An actual visible folder-row tap navigated successfully, and setQueue, pause, resume, next, and previous produced the expected live playback transitions (verification-a71e14d821154494b0742f56e673a047).

E10 — met. Repeated cross-folder, same-folder, idle, and transport checks left the app responsive with zero overflow reports in the final runtime bundle (verification-bf0a596082be4a4489039bf4988e249a).
