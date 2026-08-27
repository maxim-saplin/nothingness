# Judge notes

## E1
With Cassette selected, I verified in the live semantics tree that `screen / cassette` was index 5 at y=231–276 and the tappable `variant / Tape · Amber` row was index 6 at y=276–321. I opened the final verification PNG and it visibly shows those rows adjacent with no header or gap.

## E2
I activated the live screen selector repeatedly and observed the cycle Cassette→Spectrum→Polo→Dot→Void→Cassette; direct `screen spectrum` and `screen polo` selections also appeared in the row. The app remained responsive throughout the sequence.

## E3
I set cassette variant 1 directly and captured `Tape · Amber`, then activated the row itself and captured its changed `Tape · Mono` label. A later direct selection returned it to Tape · Amber, confirming both paths remain connected.

## E4
I exercised Spectrum, Polo, Dot, and Void and inspected each live settings state: none showed a cassette-only row beneath `screen`. A Spectrum bar-count tap, a Dot show-song-info tap, and representative normal controls on the other screen states responded without disrupting the sheet.

## E5
I captured and opened the final live Settings screenshot. It is legible, has Cassette selected, and keeps the screen and immediately following cassette variant row in frame.

## E6
The final semantics snapshot independently matches the screenshot, including the adjacent indices and abutting rects for the screen and Tape · Amber rows. The capture was taken from the active Linux app, not supplied candidate imagery.

## E7
The unrelated settings rows stayed in their expected order around the moved pair. I tapped theme and transport on the live sheet and their displayed values updated, while the cassette pair remained adjacent.

## E8
I closed and reopened Settings and switched Spectrum, Void, and Cassette before the final runtime capture. `overflows` reported an empty list and the final inspect bundle showed a responsive live app with no error state.
