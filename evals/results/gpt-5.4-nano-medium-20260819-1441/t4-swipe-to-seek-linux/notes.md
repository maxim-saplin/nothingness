# t4-swipe-to-seek-linux — judge notes

The candidate edited `hero_feedback_surface.dart` and `void_screen.dart`: Linux hides the center seek HUD, pipes target/duration/fraction into the crumb as `m:ss / m:ss · p%`, and puts `ValueKey('hero-gesture-surface')` on the ancestor so `dragByKey` can actually fire. It launched `flutter run`, queued a ~1:23 fixture, ran one atomic `dragByKey dx=240` replay, and saved `swipe_seek_linux_during.png` / `_post.png`. Analyze was clean. No interventions.

I staged `07-undercover-44.opus` (~7:00), kept playback running, and drove real XTEST drags from mid-track (press ~451,155). A held right swipe showed crumb `4:45 / 7:00 · 68%` with no `hero-seek-hud`; after settle it was `~` again and runtime had jumped 131658ms → 309273ms. A held left swipe from 180373ms showed `1:10 / 7:00 · 17%` and committed to 110085ms.

**E1 / E4 / E6 unmet.** The session never captured a true mid-gesture instant of its own: one synchronous `dragByKey` then `shoot`. The during PNG is post-release linger (they even added a 120ms clear delay for that). There is not a second candidate target value to compare.

**E2, E3, E5, E7, E8 met.** My reproductions: no center indicator during or after; crumb clears to `~`; seek actually moves; post screenshot and tree agree.

**E9 / E10 met.** Left/center/right hero taps still previous / pause-play / next. Overflows stayed empty across a swipe burst; the app kept answering inspect.
