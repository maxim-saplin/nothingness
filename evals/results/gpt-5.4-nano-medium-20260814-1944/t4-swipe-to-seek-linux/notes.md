E1 — The candidate used `dragByKey ... shotStep=10` and wrote `seek_during.png`; the captured image shows the bottom crumb with a target/duration readout and percentage, not the centered HUD. I also reproduced the same placement with a real held X11 swipe (verification-761d6df0a7d6420dbec24144bdf5bdac).
E2 — Fresh held horizontal swipes showed no centered time indicator or tall vertical line; the during screenshot displayed feedback only in the bottom line and the settled screenshot had neither indicator.
E3 — After release and a settle window, the bottom semantics returned to the normal `~` crumb and the seek readout/percentage disappeared.
E4 — The candidate supplied only one legible during-gesture capture, so I could not verify two different live target values as required.
E5 — During a real swipe the bottom line showed `0:54 / 3:14` at 28%; after release, the paused runtime read was 54,815 ms on the 194,255 ms track, within about one second of that target.
E6 — The candidate event trail records the custom `shotStep=10` capture and the resulting during screenshot while the gesture routine was active, rather than only a post-release screenshot.
E7 — My post-gesture screenshot shows the normal `~` folder crumb with no lingering seek text, percentage, or center indicator.
E8 — The settled screenshot is independently corroborated by the same capture's tree and semantics, which show the normal `~` crumb.
E9 — Real on-screen next, previous (two-stage), and pause/resume taps all produced the expected transport transitions; a vertical hero drag in the default fixed browser mode left the screen unchanged.
E10 — Repeated real X11 swipe exercises left the app responsive; runtime captures reported zero overflow/error reports.
