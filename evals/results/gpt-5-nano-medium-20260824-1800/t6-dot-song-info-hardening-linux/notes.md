E1 — Unmet. The candidate only edited dot_hero.dart and never cleared preferences or drove the app. My fresh_default verification found no live app, so default-off behavior was not confirmable.

E2 — Unmet. No show-song-info toggle or restart was exercised; the modified workspace did not produce a runnable Linux app. The persisted_enabled verification recorded no live app.

E3 — Unmet. The candidate did not perform the disable/restart round trip, and disabled_state also found no live app.

E4 — Unmet. My normal_screenshot verification captured a blank X display because the build failed before launch; no long-metadata normal-scale overlay was visible.

E5 — Unmet. My max_screenshot verification likewise had no rendered app. The launch log reports a missing lib/widgets/base_hero_container.dart import in the changed file.

E6 — Unmet. There was no candidate normal screenshot, and the fresh normal capture was only the blank desktop after compilation failed.

E7 — Unmet. There was no candidate maximum screenshot, and the fresh maximum capture was only the blank desktop after compilation failed.

E8 — Unmet. Neither normal_geometry nor max_geometry produced a tree or semantics capture because no Dart VM service was available.

E9 — Unmet. No short/typical metadata was played or compared at either scale; the app never built.

E10 — Unmet. I attempted a real Linux launch after offline pub get; compilation stopped on the missing base_hero_container.dart import, and final runtime inspection showed no live app.
