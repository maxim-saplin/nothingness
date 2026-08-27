# T4 judge notes

- **E1:** The candidate only recorded a synchronous `dragByKey` then a capture; it did not establish a genuine mid-gesture bottom-line readout.
- **E2:** I held a real X11 swipe and captured the live app; the bottom line showed seek feedback and no center indicator appeared.
- **E3:** After release and a settle, I verified the bottom text returned to `~` and the preview state was null.
- **E4:** The candidate supplied only one atomic candidate-side swipe/capture, so live values across distinct swipes were not evidenced in its event trail.
- **E5:** My held real swipe moved active playback rightward to the preview target and playback continued after release.
- **E6:** The candidate's claimed during screenshot followed an already-complete synthetic drag, not an in-flight gesture.
- **E7:** My post-gesture image showed the normal `~` folder line with no remaining seek text or center overlay.
- **E8:** The settled structural dump independently reported crumb `~` and a null seek preview.
- **E9:** I verified the exposed next transport control accepts its on-screen driver tap; the other transport keys were not exposed for complete independent verification.
- **E10:** Repeated mixed swipes produced no overflow reports and the app remained responsive.
