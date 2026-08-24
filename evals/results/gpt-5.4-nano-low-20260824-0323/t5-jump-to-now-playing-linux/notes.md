# T5 — Jump to now playing (Linux)

**Outcome: partial (score 2).** The candidate shipped a correct, working, accessible, and genuinely
visibility-conditional feature — I verified all five behavioral required expectations live — but it
never launched the app and produced neither of the two required before/after screenshots, so both
screenshot expectations are unmet and cap the run at partial.

## What the candidate did
It edited two files (no new widget files): `VoidBrowserController` in `lib/widgets/void_browser.dart`
gained `bool isTrackVisible(String path)`, computed by overlapping the row's `GlobalKey` render box
against the scroll viewport box (with an 8px tolerance). `lib/screens/void_screen.dart` added a new
crumb glyph (`⊙`, key `void-crumb-bring-now-playing-into-view`, semantics label "bring now-playing
track into view") shown only when a track is playing, its folder is already the browsed folder, and
`!isTrackVisible(playingPath)`; activating it calls `scrollToTrack` without navigating. The existing
cross-folder "jump to now-playing folder" glyph (`void-crumb-jump-to-playing`) is unchanged. It ran
`flutter analyze` clean but, by its own admission, could not produce screenshots because it never had
a live Flutter session (its `drive.py replay` attempt failed with "could not find Dart VM service URI").

## What I verified live
I launched the app myself with `dev/main_debug.dart` (the default entrypoint registers no VM-service
extensions), navigated to the mounted 10-track fixture folder, and drove each scenario.

- **E1 (met):** Played track 47, browsed the parent `/opt/nothingness`; the cross-folder jump action
  was present; tapping it set currentPath to `/opt/nothingness/media` with row .47 highlighted and
  fully on screen.
- **E2 (met, the core ask):** With currentPath already `/opt/nothingness/media` and track 47 playing
  but scrolled off-screen (list showed 50–54), the new "bring now-playing track into view" action was
  present; tapping it left currentPath unchanged and scrolled row 47 into view.
- **E3 (met):** Playing track 47 with its row fully visible (isPlaying=true and songInfo=47 captured in
  the same bundle), neither jump action appears in the tree or semantics — it is genuinely conditional
  on visibility, not merely on folder match.
- **E4 (met):** With songInfo=null in both the media folder and its parent, no jump action is exposed.
- **E5 (met):** getSemantics answers on this build; the action node carries a distinguishing label,
  not a bare glyph.
- **E6 / E7 (unmet, required):** The candidate submitted no before or after screenshot; it never ran
  the app. The prompt explicitly required them. This caps the run at partial.
- **E8 (partial):** Code-structure and analyze claims trace to its edits/bash; its runtime-behavioral
  claims match my re-check but had no backing observation in its own session.
- **E9 (met):** An on-screen `void-folder:` row tap navigated correctly; play/pause/resume behaved.
  next/prev clearing playback is the pre-existing empty-queue quirk of `playTrackByPath`, not a
  regression from this diff.
- **E10 (met):** Overflow count stayed 0 throughout and the app answered inspect normally at the end.

## Note on the implementation
`isTrackVisible` uses `Rect.overlaps`, so a row that is only partially clipped by the viewport edge is
treated as "visible" and the action is hidden there — slightly narrower than E3's boundary note (which
would still expose the action for a half-clipped row). This did not affect any expectation's verdict:
the fully-off-screen (E2) and fully-visible (E3) cases both behaved exactly as required.
