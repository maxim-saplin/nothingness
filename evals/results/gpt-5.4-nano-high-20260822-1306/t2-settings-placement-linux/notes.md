E1 — The candidate relocated the Cassette controls, and I verified the live Settings semantics: screen is index 5 and the Cassette variant is index 6 with abutting rectangles; the captured screen agrees (verification-f0cd2c686e0a4fd6a6d0d428f85d7cbe).

E2 — I tapped the live screen row through Spectrum, Polo, Dot, Void, and back to Cassette, then used direct screen calls; each displayed value tracked the active screen (verification-35f6cf17ecb342ee8083697a61ba7226, verification-d78a980505ec4e3db339ea2be11df4d8, verification-3b2e61a2ca66488786653715b2997c75, verification-47c2659a58484389aade84f39b5ccf88, verification-03d46af4de1b40a397c1277e19d841f2).

E3 — With Cassette selected, I activated the adjacent variant row and then set multiple variants directly; the row and settings state updated together (verification-da3a072d9451497ebbd0c2a2bd301f5f, verification-7083965d34ac4763a9e1f09e01ca4627, verification-726313d69b8b4bf78e45a055b2723dc5).

E4 — I checked Spectrum, Polo, Dot, and Void individually: none injected a Cassette-only row after screen, and each screen-specific control responded to an on-screen exercise (verification-448bf700790b4e4ab9e39dff6f1262f8, verification-a0c50e7e47164c389b517740da0a32ad, verification-fc8d4171742f4aa59660ad73fe49ddf9, verification-cbba731bcdb94abab45ad4b93cd89192).

E5 — I opened a fresh genuine screenshot capture with Cassette selected; it visibly contains the legible screen row and directly adjacent variant row (verification-f0cd2c686e0a4fd6a6d0d428f85d7cbe).

E6 — The live semantics and settings dumps independently corroborate Cassette selection, adjacency, and the final Tape · Mono value (verification-775d8922d0464211879e24358bc792ee).

E7 — I compared unrelated row ordering and exercised immersive and transport; both changed on tap, and transport was restored without changing the Cassette placement (verification-774457c70d4847bfa71237cc613c8c00, verification-775d8922d0464211879e24358bc792ee).

E8 — After the navigation and control checks, the app remained responsive; the final runtime reported no errors and zero overflow reports, with live processes confirmed by inspection-dd7605ff8e0b40d1847e473f55ce92aa.
