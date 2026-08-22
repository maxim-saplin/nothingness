# Judge notes

**E1 — Placement:** The candidate's live Linux build showed `screen / cassette` at index 5 followed directly by `color scheme` at index 6, with abutting semantic y-ranges in `verification-d5afbb871dc94283b68998b7855bf721`.

**E2 — Exact label:** The Cassette row read exactly lowercase `color scheme`; full-sheet semantics contained no second cassette variant row in the Cassette captures.

**E3 — Screen control:** I drove the on-screen selector through spectrum, polo, dot, void, and cassette (`verification-94672ebe33914b5687617cf30b687e0d`, `verification-e2e0fad91e6841839215e7a4ac122327`, `verification-e1beb41ead7a49a8812fd28cbc8bb3d5`, `verification-17536ea4cb234dd69f8f0ea712bdb635`, and `verification-12926bd2587445ec84def5fb1cf56b87`), and the displayed screen value tracked each state; direct dot and cassette calls (`verification-6a2fb14b3b974166b820118b27bb544b`, `verification-d5afbb871dc94283b68998b7855bf721`) also matched.

**E4 — Renamed control:** A real activation changed the row from Tape · Mono to Tape · Amber (`verification-234a04e6a3f44360bbb9b8f702ee2c2a`); direct variant calls yielded Tape · Colour and Tape · Mono in `verification-ab0c175545eb470683ddd5f9f620359e` and `verification-9cf2cfaa26b14ac0819b30ed3eaadc79`.

**E5 — Scope:** Spectrum retained its bar-count controls and changed 24 to 8, Polo changed text size to 150%, Dot changed sensitivity from 1.5x to 2.6x, and Void changed transport from bottom to top. None of those non-Cassette semantics captures (`verification-f37eb6d43f2b4bbfb41045a4c09f43db`, `verification-e850ba68b8ee481fa0410120491c3e37`, `verification-3d4824d85a4e4cc4ab320f3bc0b21418`, `verification-eec3bd92c516464299e58c87a0d15687`) contained `color scheme`.

**E6 — Screenshot:** I independently captured and inspected a genuine PNG showing the Settings sheet with Cassette selected and the adjacent, legible `screen` and `color scheme` rows (`verification-d5afbb871dc94283b68998b7855bf721`).

**E7 — Independent dump:** The same Cassette verification's semantics independently reported `screen / cassette`, `color scheme / Tape · Mono`, indices 5 and 6, and contiguous row bounds.

**E8 — Other settings:** Unrelated rows remained in their normal order; real X11 activation changed `transport` to top and `debug layout` to on in `verification-eec3bd92c516464299e58c87a0d15687` and `verification-e5fd5ac970db45dfb369474e2e654a9a`.

**E9 — Runtime health:** The final live inspection `inspection-75b6aef9b45c499999e0848ae1947276` found the app responsive with `overflows.count: 0`; the verification bundles completed successfully throughout the navigation and control checks.
