E1: I drove the live Linux app to Cassette and verified the semantics order: screen index 5 is immediately followed by color scheme index 6 with contiguous bounds.
E2: The live row reads exactly “color scheme” in lowercase, and the cassette settings semantics contain no stale variant row.
E3: Tapping the screen row drove the complete visible cycle through spectrum, polo, dot, and void; direct screen calls reported matching settings state, then I returned to Cassette.
E4: Tapping the cassette row changed Tape Mono to Tape Amber; a direct cassettevariant 3 call changed the row to Tape Colour and the semantics value matched.
E5: I checked spectrum, dot, polo, and void states; each had its own settings and none exposed color scheme, while spectrum and dot controls changed after on-screen taps.
E6: The final genuine verification PNG shows the settings sheet with cassette selected and screen directly above the legible color scheme row.
E7: Semantics and getSettings captured together corroborate cassette selection, the exact label, adjacent indices, and the displayed variant.
E8: The mode/look/library rows remained in their established order across captures, and unrelated rows remained present and tappable.
E9: The app stayed live through navigation, scrolling, cycling, and activation; final runtime inspection reported zero overflow reports.
