E1: The candidate retained the cross-folder glyph and navigation code, but its test command hung before it completed a report. I manually drove the live app: activation moved from `/opt/nothingness` to `/opt/nothingness/media`, but track 47 still was not visible.

E2: The candidate added a Linux same-folder glyph and a `scrollToTrack` call. In the live same-folder state, tapping the exposed action left the browser path unchanged but did not reveal off-screen track 47.

E3: The candidate added an intersection-based visibility predicate, but did not complete a citable fully-visible-row check. The verifier could not attach to the live VM session, so this condition was not credited.

E4: The implementation gates both glyph paths on `isPlaying`, but the candidate did not leave a completed no-playing verification state. I did not credit an unverified idle-state claim.

E5: Manual semantics orientation showed the label `scroll to now-playing track` on the active glyph. The harness verifier could not capture that live semantics state, so accessibility was not credited.

E6: The candidate created no before screenshot artifact; only judge-generated screenshots exist in the run tree. No on-point pre-jump submission was verified.

E7: The candidate created no after screenshot artifact and never completed its test/report. No submitted image showed the target row revealed.

E8: The candidate produced no final write-up or completion claim before its last tool call hung. Its terminal session event therefore contains no unsupported behavioral assertion.

E9: The candidate did not complete the required on-screen navigation and playback regression exercise. Direct `nav` orientation calls do not substitute for the rubric's on-screen taps, so no credit was assigned.

E10: The manually launched app remained responsive and showed zero overflows during orientation, but the required citable runtime bundle was unavailable. No stability credit was assigned.
