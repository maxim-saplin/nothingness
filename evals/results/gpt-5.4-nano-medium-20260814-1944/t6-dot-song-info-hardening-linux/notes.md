E1: The candidate inspected the existing Dot song-info implementation but never launched the Linux app. My post-run verification found no live app, so the fresh default-off state was not demonstrated.

E2: No settings toggle or restart was exercised because the app was never launched. Persistence after enabling therefore remains unverified.

E3: No disable-and-restart round trip was exercised because the app was never launched. Persistence after disabling therefore remains unverified.

E4: The candidate edited `lib/widgets/heroes/dot_hero.dart` but captured no normal-scale screenshot. My verification found no live app and could not inspect long metadata geometry.

E5: No maximum-scale interaction or screenshot was captured by the candidate, and my verification found no live app. Maximum-size containment and dot separation are unverified.

E6: There was no candidate normal-scale screenshot and no fresh 100% reproduction. The only post-run PNG was the no-live-app black placeholder, not a task screenshot.

E7: There was no candidate maximum-scale screenshot and no fresh 150% reproduction. The only post-run PNG was the no-live-app black placeholder, not a task screenshot.

E8: No tree or probe was captured at either scale because the app was never live. Structural rendering of the overlay is therefore unverified.

E9: No short-metadata comparison was driven at either scale. Ordinary-metadata regression behavior is unverified.

E10: The candidate's final Flutter test command hung without output, and the app was never launched for runtime exercise. My inspection confirmed no responsive app, so stability during the requested interactions could not be verified.

The candidate changed `lib/widgets/heroes/dot_hero.dart` and added `test/widgets/dot_hero_song_info_screenshot_test.dart`; no screenshots or runtime evidence were produced before judge finish.