E1 — The candidate added a mid-gesture capture helper, but its recorded event output was consumed by PNG base64 before the bottom-line text was legible. I independently saw the working bottom feedback with a held X11 gesture, but that cannot replace the required candidate-events proof.

E2 — I held a real X11 swipe in progress and opened the captured screenshot; it showed only the bottom `0:50 / 1:29 · 57%` feedback and no center indicator or vertical line.

E3 — After release and settling, I opened the new screenshot and inspected tree/semantics; all showed `/opt/nothingness/media` restored with no residual feedback.

E4 — The candidate recorded only same-direction `dx=300` mid-capture attempts, and the event payload did not expose target values for comparison. I could not verify two distinct live candidate values.

E5 — On a fresh 2:05 track, my real rightward swipe moved runtime position from 7.4s to 56.6s, consistent with the gesture target and ongoing playback.

E6 — The candidate’s event trail records its `during` PNG capture before the helper invokes drag end, with an in-helper frame yield at the capture point. This is a traceable mid-gesture artifact.

E7 — I opened an independently captured settled screenshot after release; it is visibly later and shows the normal folder path without feedback or center UI.

E8 — The same settled verification includes a tree and semantics dump that both name `/opt/nothingness/media`, matching the screenshot.

E9 — The final semantics still exposes previous, play/pause, and next controls. I did not establish every tap-zone transition or the vertical-drag behavior in this session.

E10 — I exercised several held real-X11 swipes in both directions. The final runtime capture remained responsive and reported no overflows.
