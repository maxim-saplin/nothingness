# T6 — Dot song-info hardening (Linux) · judge-t6

**Outcome: partial · adjusted 0.6 · no interventions.**

## What the candidate actually did

It read the codebase carefully, correctly identified `lib/widgets/heroes/dot_hero.dart` as the place
to fix, and shipped a real change: when `showSongInfo` is on it computes the vertical space the title
block can need (2 lines of artist at `heroSize * textScale` plus 2 lines of song at half that, using
the same 1.18 line-height factor the widget uses) and shrinks the dot's *maximum radius* to whatever
is left above the hero's centre. It also added `ValueKey('dot-circle')` / `ValueKey('dot-song-info')`
so geometry is addressable, and wrote two widget tests asserting the title block's bottom sits above
the dot's top at textScale 1.0 and 1.5. `flutter analyze` was clean and I re-ran its tests myself:
all 7 in `dot_hero_test.dart` pass.

It then spent ~11 minutes of its 30-minute budget hung inside
`flutter test test/widgets/heroes/dot_hero_screenshots_test.dart` — a screenshot-producing widget
test it wrote and later deleted. It abandoned that route, launched the real Linux app at 1385s, ran
`drive.py preflight` and `drive.py inspect`, and was still reading `library_service.dart` looking for
a way to stage long metadata when the deadline guard finished the run at 1625s. **It never captured a
single screenshot** (`.tmp/agent_shots` was empty, and the event stream contains no `shoot` call),
never toggled the option, and never looked at the Dot screen. The prompt asked for screenshots at
both scales; none were delivered, and there is no final write-up.

## What I verified myself

I staged long metadata the way the app actually resolves it: a copy of a fixture opus named
`<82-char artist> - <79-char title>.opus` under `/opt/nothingness/media/longmeta`, played via the
library browser row (`drive.py play` would have given a title-only track with no artist). The app
resolved artist = 82 chars and title = 79 chars. I drove the text-size slider with real X11 input
(XTEST) after wheel-scrolling the settings sheet, and confirmed the row's own value read `150%`
before capturing, and `100%` after setting it back. Two of the restarts were full process relaunches
(kill + fresh `flutter run`), not hot restarts.

- **E1 (met)** — `clearpref '*'` + restart: the hero shows the pulsing dot alone, 230 px across, no
  overlay, settings row reads "show song info / off".
- **E2 (met)** — toggled on, killed the process and relaunched: the overlay is back without
  re-toggling and the row reads "on". Genuine persistence.
- **E3 (met)** — toggled off, relaunched: no overlay, and the dot returns at full size
  (`dot-circle` 173.1×173.1 logical). A real round trip.
- **E4 (partial)** — at 100% with the long metadata the overlay is fully inside the hero: ink ends at
  y=141 of a 230 px band, the artist ellipsizes legibly at 2 lines. Nothing clips and nothing overlaps
  the dot — but only because **the dot isn't there**. The captured tree shows the dot's Container at
  `BoxConstraints(w=0.0, h=0.0)` while the track is playing with a non-zero spectrum. The candidate's
  reserved height (130 logical px at 100%) exceeds the hero's half-height (86.6), so `centerY -
  reserved` goes negative and the radius clamps to 0. The "no overlap" condition holds vacuously.
- **E5 (unmet)** — the one observation this rubric is built around. At 150% the song title's second
  line, "Seventeen Reprise", is **cut mid-glyph at the hero's own bottom bound**: ink runs to y=229
  and stops flat at the 230 px band edge, descenders sliced. The fix only shrank the dot; it never
  constrained the text block, so the clipping the task exists to remove is still there.
- **E6 / E7 (unmet)** — no candidate screenshot exists at either scale, so there is nothing to review
  against my own captures. My own 100% reproduction is clean (modulo the missing dot); my own 150%
  reproduction shows the clip above.
- **E8 (met)** — `drive.py probe` corroborates the text really renders at both scales: hero-artist
  fontSize 30 / 848×70 and hero-song 15 / 713×18 at 100%; 45 / 848×106 and 22.5 / 848×54 at 150%,
  full strings resolved, matching trees.
- **E9 (partial)** — ordinary metadata ("undercover" / "49") renders cleanly at both scales with no
  clipping, but the dot is 0×0 there too. The regression is not limited to long metadata: with the
  option enabled the Dot screen has no dot at any text scale on this window.
- **E10 (met)** — `drive.py overflows` reported 0 before, during and after two toggle cycles, two
  scale changes and switching between long- and short-metadata tracks; the app answered `inspect`
  normally at the end. Only ALSA/JACK container audio noise in the run log, no Flutter exceptions.

## Worth flagging

The candidate's own tests pass while the app clips because they exercise `DotHero` in a 400×400 box.
The real hero band is 960×173 logical — less than half as tall — so the title block fits in the test
and overflows in the app. And `titleRect.bottom <= dotRect.top` is trivially true once the dot is
0×0, so neither test could have caught either problem. Nothing here was mis-scored for lack of
proof: I reproduced every claim live, and the two failures are failures of the change itself, not of
its evidence.
