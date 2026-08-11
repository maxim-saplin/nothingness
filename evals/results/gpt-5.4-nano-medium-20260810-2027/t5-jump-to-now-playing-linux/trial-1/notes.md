# Notes — t5-jump-to-now-playing-linux

The candidate added `VoidBrowserController.isTrackInView(path)` (checks whether a row's `GlobalKey`
currently has a build context) and used it, on Linux only, to decide whether to show the crumb's "jump to
now-playing" glyph when the playing track's folder is already the browsed folder. It reused the existing
`jumpToNowPlaying` navigation logic (which already skipped re-loading the folder when it matched), so
activation correctly leaves the browser in place and centers the row via `Scrollable.ensureVisible`/
`animateTo`.

**E1 (different-folder case): met.** Browsing the parent while a track played in the child folder, the
jump glyph was present; tapping it moved the browser into the track's folder with the row centered.

**E2 (row scrolled out of view, same folder — the core ask): met.** With a fresh track playing in the
already-browsed folder and its row scrolled off-screen, the glyph was present; activating it left the
folder path unchanged and brought the row on screen. I deliberately used a track that hadn't been played
earlier in the session, because replaying the same path doesn't fire a fresh check and can make an already-
frozen state look right or wrong by accident.

**E3 (hidden once already visible): unmet.** The exact same capture that satisfies E2 — row fully
unclipped, centered mid-list, right after the jump completed — still exposes the action as tappable with
a real label. Reading the diff explains why: the visibility check runs inside a `Selector` that only
re-executes when the playing track's path changes or the browsed folder changes (via the ambient
`LibraryController` Provider dependency) — never when the list's `ScrollController` itself moves. I proved
this two ways with a fresh track and no navigation events in between: scrolling a visible row off-screen
left the glyph absent even though the row was genuinely gone, and scrolling an off-screen row back into
full view (after having correctly shown the glyph via a folder-nav round trip) left the glyph shown even
though the row was genuinely back on screen. Either the exposed state was wrong, or it happened to
coincide with reality only because of an unrelated rebuild — it never tracked scrolling on its own.

**E4 (nothing playing): met.** Reaching genuine idle (letting a track play to its end so `songInfo` went
to `null`) and checking both the media folder and its parent showed no active jump action in either.

**E5 (real accessibility identity): met.** `getSemantics` returns a real tree on this build; the action's
node carries the label "jump to now-playing folder", distinct from the crumb path text around it — not a
bare glyph. Minor nit not scored down: that label still says "folder" even in the same-folder/scroll case,
which is a slightly inaccurate description of what the action does there, but it's still a genuine,
distinguishing label.

**E6 (before screenshot): met.** The candidate's `before_now_playing_offscreen_v3.png` genuinely shows the
playing track's row absent from the visible rows — matches the claimed "before" state, and the rendering/
dimensions match my own live captures, ruling out fabrication.

**E7 (after screenshot): unmet.** `after_now_playing_visible_v3.png` is visually identical to the before
screenshot — same six rows, the playing track's row still absent, nothing highlighted. I reproduced the
same starting state live and, when I waited about a second for the scroll animation to settle before
shooting, the row did come into view — so the underlying scroll can work, but the candidate's own submitted
evidence does not show it working. Most likely the candidate's shoot fired immediately after the tap,
before the ~240 ms scroll animation completed.

**E8 (claims traceable): unmet.** The write-up's own caption for the after screenshot — "row scrolled into
view; browser stays in the same folder" — is directly contradicted by that same image (see E7). That's a
falsified claim, not merely an unbacked one.

**E9 (no navigation/playback regression): met.** On-screen taps of a folder row and the "up" affordance
navigated correctly (checked via `getLibraryState`, not just the tap's own success reply). With a real
multi-track queue, `next`/`prev`/`pause`/`resume` all transitioned playback as expected. Note: a bare
single-track `play` (queue length 0) makes `next`/`prev` clear `songInfo` entirely — pre-existing behavior
unrelated to this diff, which only touches the crumb glyph and `VoidBrowserController`.

**E10 (no crashes/new errors): met.** `overflows` stayed at zero throughout E1–E4 and the extra scroll
reproductions, and the app remained fully responsive (correct playback/queue state) at the end.

**Overall:** E3 and E7 are both required and unmet, so the run is capped at `partial` regardless of the
aggregate (raw 0.7, no penalty, adjusted 0.7). The implementation gets the two staged scenarios (divergent
folder, and same-folder-via-nav-round-trip) right, but the underlying reactivity gap means the feature does
not reliably track a user's actual scrolling, and the candidate's own submitted after-screenshot fails to
demonstrate the fix it claims.
