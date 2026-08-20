E1: I browsed /opt/nothingness while playing 06-undercover-54, saw the labeled folder-jump action, activated it, and verified the browser moved to /opt/nothingness/media with the track row visible.

E2: With /opt/nothingness/media already open and 06-undercover-54 outside the visible list, the labeled scroll action appeared; activation kept currentPath unchanged and brought row 54 into view.

E3: While 10-undercover-47 was playing and its full row was within the list viewport, the semantics capture contained no active jump action.

E4: I let playback end and verified isPlaying false and songInfo null in both the media folder and its parent; neither idle state exposed a jump action.

E5: The active affordance was exposed in semantics as a button labeled “scroll to now-playing track,” with a tap action.

E6: The genuine pre-action verification screenshot showed playback of 06-undercover-54 while row 54 was not in the visible list region.

E7: The genuine post-action verification screenshot showed row 54 visible and the browser still at /opt/nothingness/media.

E8: The candidate’s write-up was backed by its inspect, navigation, playback, tap, and screenshot calls in the contiguous event ledger; I also reproduced the key claims live.

E9: I tapped the visible media folder row and confirmed currentPath changed, then exercised browser-row playback, next, previous, pause, and resume; queue/index and playing state responded normally.

E10: Repeated jump, navigation, and playback checks left the app responsive; final runtime inspection reported zero overflow reports and a live process.
