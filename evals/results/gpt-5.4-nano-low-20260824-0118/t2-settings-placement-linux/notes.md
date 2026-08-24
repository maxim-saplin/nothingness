E1: I opened Settings and selected Cassette. The live semantics and screenshot showed screen=cassette immediately followed by variant=Tape · Mono, with abutting row bounds.

E2: I tapped the live screen row through the full cycle cassette→spectrum→polo→dot→void→cassette and checked matching getSettings states; a direct Polo setting also updated the row.

E3: I activated the adjacent Cassette variant row and observed Tape · Mono→Tape · Amber, then used direct cassettevariant calls and verified the displayed variant changed accordingly.

E4: I selected Spectrum, Polo, Dot, and Void and verified the Cassette-only row was absent while each screen-specific section remained present. Spectrum bar count and Dot show-song-info controls responded; Polo/Void text-size sliders were present but not practically reachable through this desktop pointer path.

E5: The captured PNG genuinely showed the Settings sheet with Cassette selected and both adjacent rows legible in the frame.

E6: The Cassette screenshot was corroborated by the same-state semantics dump and getSettings payload, including screenType=cassette and the row indices.

E7: The unrelated settings rows retained their order, and live taps on immersive, transport, and operating mode changed their displayed values.

E8: After the exercise, the app remained responsive; runtime inspection reported zero overflow reports and overflow count 0.
