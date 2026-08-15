E1 — Met. I launched the candidate's Linux build, opened Settings with Cassette selected, and verified both semantics and the rendered screenshot: screen is immediately followed by variant with consecutive indices and abutting rectangles.

E2 — Met. I activated the on-screen screen selector repeatedly and observed Spectrum, Polo, Dot, Void, then Cassette again in the live settings sheet; fresh verification bundles captured the displayed screen values.

E3 — Met. I activated the relocated Cassette variant row and observed its value change from Tape · Mono to Tape · Amber, then used the direct cassettevariant control and verified the resulting row value in a fresh capture.

E4 — Partial. Spectrum, Dot, and Void showed no Cassette-only row and retained their own settings, but the Polo capture labeled the screen Polo while exposing Spectrum rows rather than Polo's own control, so the all-other-screens requirement was not fully established.

E5 — Met. The judge-captured PNG genuinely shows the Settings sheet, screen=cassette, and the legible adjacent variant row in the same frame.

E6 — Met. The Cassette verification bundle's semantics and settings state independently corroborate the screenshot's screen and variant placement/value.

E7 — Met. Across the captured states, unrelated MODE, LOOK, and LIBRARY rows kept their order; representative Spectrum, Dot, and Void controls responded and their fresh captures reflected changed values.

E8 — Met. The live app remained responsive after the exercise; runtime inspection reported no overflow reports and no playback/library error.

Operational note: the candidate's Flutter process had ended when its turn settled, so I relaunched the modified workspace build inside the same isolated container for fresh judge-owned verification. No judge interventions were delivered. Candidate workspace changes collected by the harness were lib/widgets/void_settings_sheet.dart and tool/regression/cassette_settings.txt.