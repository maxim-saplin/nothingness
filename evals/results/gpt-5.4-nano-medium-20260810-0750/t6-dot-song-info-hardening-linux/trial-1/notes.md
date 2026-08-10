# t6-dot-song-info-hardening-linux — judge notes (judge-t6)

**Outcome: valid / pass / score 3 (adjusted 0.9, raw 0.9, no interventions).**

## What the candidate did

It changed exactly one file, `lib/widgets/heroes/dot_hero.dart` (98 insertions, 26 deletions),
and nothing else. When `showSongInfo` is on, `DotHero` now computes a `reservedTop` band from
the theme's hero font size — top padding, plus two lines of artist at H1, plus the 8px gap,
plus two lines of song at H2, all multiplied by `textScale` — and centres the pulsing dot in
the space *below* that band instead of in the whole hero. The dot's radius clamp was reworked
to use the reduced height, so it shrinks rather than pushing into the text. Two lines each is
exactly right: `HeroTitleBlock` renders both headings with `maxLines: 2` and an ellipsis, so
the reserved band really is the worst case.

Unlike the other runs from this model in this campaign, it genuinely drove the app. Its event
stream shows a real `flutter run -d linux` launch, `drive.py emulate phone`, `pref`, `restart`,
`play` and four `drive.py shoot` calls; it also ran `flutter analyze` (clean) and one widget
test file. The screenshots it submitted are real captures of the real app, not drawings.

## What I verified myself

I drove the still-live container build for every expectation. To get metadata the rubric
actually calls for I dropped two files into `/opt/nothingness/media/longmeta` and played them
through the library browser (`drive.py nav` + tapping the `void-file:` row), which is the only
path that resolves an artist — `drive.py play` and `setQueue` both construct an `AudioTrack`
with the bare filename as the title and no artist at all. The long track resolved to a 65-char
artist and a 68-char title; the control track to "Aha" / "Take On Me".

- **E1 (fresh default off) — met.** `clearpref *` + hot restart: `probeText` finds neither
  `hero-artist` nor `hero-song`, and the screenshot is the bare dot.
- **E2 (enabling persists) — met.** I tapped the real settings row
  `void-settings-dot-show-song-info`, hot-restarted without re-toggling, and the overlay came
  back. The row's own semantics read "show song info / on".
- **E3 (disabling persists) — met.** Tapped it off, restarted, overlay stayed gone.
- **E4 (100%, long metadata) — met.** Artist wraps to two ellipsized lines, song to two more,
  every glyph whole and inside the hero, dot entirely below with a clear gap.
- **E5 (150%, long metadata) — met.** Same, at 45.0px artist / 22.5px song. I confirmed the
  scale through the app's own UI: scrolling the settings sheet with a real X11 wheel event
  brings the row into view and it reads "text size 150%". To check this was a real fix and not
  a scenario that already worked, I reverted `dot_hero.dart` to the pinned baseline and
  hot-reloaded: the baseline dot swallows the middle of the text at 150% for long *and* short
  metadata. I restored the candidate's file and re-checked `git diff --stat` afterwards.
- **E6 / E7 (the required screenshots) — partial, both.** The two submitted PNGs are genuine,
  correctly scaled captures that agree with my clean reproductions. The deduction is the
  metadata: the candidate staged its "long metadata" by copying an mp3 to a long
  `Artist - Title.mp3` filename and playing it with `drive.py play`, which discards the artist
  entirely. Its screenshots therefore show a *single* H1 heading of a long title with no artist
  line at all — never the two-heading artist-plus-song case the prompt names and the case its
  own reserved-space formula was written for. It also never noticed that its 100% capture has
  the overlay text sitting on top of the "tap · long-press · swipe" idle hint in the top-right.
- **E8 (structural corroboration) — met**, by my probes at both scales (30.0/15.0 and
  45.0/22.5 px, full text returned). The candidate ran no structural read of its own.
- **E9 (short metadata unaffected) — met.** "Aha" / "Take On Me" is clean at both scales. The
  baseline comparison matters here: the ordinary case was broken at 150% *before* the change
  too, so nothing regressed. The one cosmetic cost is that the reserved band is a constant, so
  with short metadata the dot now sits lower with a large gap above it rather than centred.
- **E10 (stability) — met.** Three rounds of toggling the option off/on and switching between
  the long and short tracks left `drive.py overflows` at zero, and the runtime answered
  normally at the end. One crash did happen on my watch — a hot restart issued while audio was
  playing died with "Callback invoked after it has been deleted" inside
  `libflutter_linux_gtk`. That is a native hot-restart/audio interaction, not something a pure
  Flutter layout change can cause; pausing playback first made the identical sequence clean. I
  relaunched and carried on.

## Bottom line

The implementation is correct and does fix the defect the task exists for, confirmed against
the pre-change baseline. The evidence it submitted is real but under-tests its own fix by half:
it proved the long-*title* case and left the long-*artist* case, which is the taller one,
entirely unexercised.
