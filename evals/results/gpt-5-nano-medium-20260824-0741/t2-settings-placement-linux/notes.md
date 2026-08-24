Candidate edited `lib/widgets/void_settings_sheet.dart` but never launched the app or captured a screenshot during its own run. I launched the instrumented Linux build independently and verified the behavior live.

E1: Cassette semantics placed the screen row at index 5 and the cassette variant row at index 6 with abutting y-ranges; the screenshot showed the same adjacency.
E2: The screen row cycled through spectrum, polo, dot, void, and Cassette via taps, and direct screen commands updated the displayed value.
E3: The cassette variant row changed after its own tap and after direct cassettevariant calls, with the displayed label tracking the selected variant.
E4: Spectrum, Polo, Dot, and Void each showed their own controls without the cassette-only row; a real X11 click changed the Polo text-size slider to 130%.
E5: A live verified PNG showed the Settings sheet with Cassette selected and both adjacent rows legible.
E6: The live Cassette capture included semantics and settings state corroborating the screenshot and current variant.
E7: Unrelated settings rows retained their order, and theme, immersive, transport, and browser controls responded to taps.
E8: Repeated settings navigation and screen switching left the app responsive; runtime inspection reported zero overflow reports.
