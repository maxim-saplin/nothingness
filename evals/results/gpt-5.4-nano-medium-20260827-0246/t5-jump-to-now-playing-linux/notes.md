E1: I played track 49, browsed its parent, and activated the existing folder-jump affordance. The browser returned to `/opt/nothingness/media` with row 49 visibly rendered.

E2: I independently staged track 47 outside the rendered rows while remaining in `/opt/nothingness/media`; the new labeled action appeared and scrolled row 47 into view without path change. A separate state with track 49 clipped at the viewport edge exposed no action, so the boundary behavior is incomplete.

E3: After the same-folder jump, row 47 was fully visible in the screenshot, but semantics still reported a tappable `jump to now-playing track` action. This is an always-active-after-scroll defect.

E4: Before any judge playback staging, the app reported `isPlaying: false` and `songInfo: null` in the media folder, and semantics contained no active jump action. I could not obtain a second idle folder after hot restart retained the staged current track.

E5: The live fully-offscreen state exposed a real semantics button labeled `jump to now-playing track`, not merely an unlabeled glyph.

E6: I opened the submitted before image: its hero names 01-undercover-49 while the browser shows 50–54, so the playing row is absent. My live offscreen pre-jump capture reproduced that state.

E7: I opened the submitted after image: row 49 is selected and visible in `/opt/nothingness/media`. My live post-jump capture similarly showed target row 47 in the unchanged folder.

E8: The session includes a replay of the same-folder scenario and resulting screenshot files, but no recorded check supports the claimed fully conditional behavior; live verification contradicted that claim after the row became visible.

E9: I tapped the visible media-folder and up controls and confirmed path changes, then exercised a two-item queue through next, previous, pause, and resume. The app remained responsive throughout.

E10: Live verification after feature and navigation exercises reported no overflow entries, and the app remained responsive after hot restart. Candidate-side command/analyzer mistakes were corrected before completion and no runtime feature error was observed.
