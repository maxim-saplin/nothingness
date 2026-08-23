E1: I played track 44, browsed its parent’s parent folder, and verified the accessible jump action. Activating it returned to /opt/nothingness/media with row 44 visible.

E2: I played track 47 and reset the same-folder list to scrollPosition 0, where row 47 was offscreen. The expected same-folder bring-into-view affordance was absent and its key was not tappable.

E3: I scrolled to scrollPosition 203.2 so row 47 was fully within the viewport; no active jump affordance was exposed.

E4: A live capture with playback stopped reported isPlaying=false and songInfo=null, with no jump action in semantics.

E5: The cross-folder action appeared as a semantic tap target labeled “jump to now-playing folder.”

E6: The candidate did not leave a submitted before screenshot; its screenshot test was still failing when the run was stopped.

E7: The candidate did not leave a submitted after screenshot; its screenshot test was still failing when the run was stopped.

E8: The candidate produced no final write-up claims. Its concrete actions and state reads are present in the contiguous session event evidence.

E9: Tapping the on-screen media folder navigated correctly. Playback control commands returned normally and the app stayed responsive.

E10: Final runtime inspection showed the app live, no library error, and zero overflow reports after the exercised navigation and playback states.
