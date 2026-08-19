The candidate moved Linux Cassette `displayRows` to sit immediately under the screen cycle and renamed CassetteVariant.v3's option text from `Tape · Colour` to `color scheme`. It launched the Linux app, opened Settings, and saved screenshots (the full `cassette_settings_cassette.png` is the useful one; `cassette_settings_region2.png` is cropped above the cassette row).

E1: With Cassette selected I opened Settings and read semantics. Screen (index 5, y 231–276, value cassette) is immediately followed by the cassette-variant row (index 6, y 276–321). The screenshot shows the same pairing.

E2: That row's label is still `variant`. `color scheme` is the value because v3's metadata label was renamed, not the control's row title. The original `variant` row remains.

E3: Tapping `void-settings-screen` walked cassette → spectrum → polo → dot → void → cassette. `drive.py screen` also updated the displayed value. Returning to Cassette still had the variant row directly under screen.

E4: Tapping `void-settings-cassette-variant` moved `color scheme` to Minimal. `drive.py cassettevariant` 1/4/2 landed the same row on Tape · Mono, Minimal, and Tape · Amber.

E5: For spectrum, polo, dot, and void, the row after screen is immersive, not a cassette control and not `color scheme`. Tapping immersive flipped off→on; tapping theme-variant moved system→dark. Dot `show song info` also accepted a tap.

E6: `cassette_settings_cassette.png` from this session shows the settings sheet, Cassette selected, and the next row with `color scheme` readable. The candidate's cropped region shot does not, but a genuine full capture exists.

E7: Semantics, settings JSON (`screenType: cassette`), and the judge screenshot agree on order and on the exact strings on those two rows.

E8: Seating the whole cassette `displayRows` (variant plus text size and haptics) under screen moved those two extra rows ahead of immersive/transport. Theme-variant and immersive still respond to taps.

E9: `drive.py overflows` stayed at count 0; inspect still answered with a live router and playback after the exercise.
