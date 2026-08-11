# t2-settings-placement-linux — judge notes (v130-judge-t2)

The candidate read `void_settings_sheet.dart`, found the cassette-variant `_Cycle` widget nested
inside a per-screen-type switch (alongside text size and haptics, under the DISPLAY group), and
moved just that one widget out to the top-level `rows` list, inserted right after the `screen`
row, gated on a new `cassetteCfg = cfg is CassetteScreenConfig ? cfg : null` check. It kept the
exact same widget key, label, and handler — a genuinely minimal relocation, not a rewrite. It then
launched the real Linux build, opened settings with Cassette selected, and shot two screenshots
(byte-identical duplicates of the same frame) before stopping. It never raced the sheet animation —
its screenshot is a real capture of the open sheet, not the closed player screen.

**E1 (placement).** Confirmed live: with screen=cassette, `getSemantics` shows node `indexInParent:5`
labelled "screen\ncassette" (rect y 231–276) immediately followed by `indexInParent:6` labelled
"variant\nTape · Mono" (rect y 276–321) — abutting, no gap, no header between them. The candidate's
own screenshot shows the same thing plainly.

**E2 (screen control preserved).** Tapping `void-settings-screen` on-screen walked the full cycle
cassette→spectrum→polo→dot→void→cassette, the row's displayed value tracking every step. A direct
`screen=dot` call also landed and the row updated to "dot". Both directions wired correctly.

**E3 (variant control preserved).** Tapping `void-settings-cassette-variant` advanced
v1 ("Tape · Mono") → v2 ("Tape · Amber"). A direct `cassetteVariant=4` call separately landed on
v4 ("Minimal") with the row's label updating to match. Both the on-screen tap and the direct call
move the variant and both show up in the displayed label.

**E4 (scoped to Cassette).** For each of spectrum, polo, void, and dot, `getSemantics` shows the row
right after "screen" is that screen's own next row (immersive for the first three, and dot's own
list continues normally) — the cassette-variant selector never leaks into another screen's sheet.
Tapping dot's own "show song info" row on-screen flipped it off→on, proving the reshuffle didn't
disconnect any other screen's controls from their handlers.

**E5 (screenshot).** Opened the candidate's actual `artifacts/agent-shots/cassette_settings.png`
directly. It genuinely shows the settings sheet open, "screen: cassette", and the very next row
"variant: Tape · Mono", both legible in frame. (Note: `cassette_settings_region.png` is a
byte-identical duplicate of the same file, not a second distinct capture — harmless but worth
flagging as noise.)

**E6 (independent corroboration).** My own `getSemantics`/`getSettings` dumps corroborate both the
ordering and the value shown in the screenshot; not resting on the image alone.

**E7 (unrelated rows undisturbed).** Across cassette/spectrum/polo/void/dot captures, the unrelated
rows (MODE, operating mode, LOOK, theme, theme-variant, immersive, transport, browser, full screen,
ui scale, LIBRARY, prefer-filename, smart folders, DISPLAY...) keep the same pairwise order in every
case; only the cassette-variant row appears/disappears around "screen". Tapping the unrelated
"immersive" and "prefer filename over tags" rows still flips their values on-screen.

**E8 (no crashes).** `drive.py overflows` returned an empty report before and after the entire
exercise (five screen switches, repeated taps, two direct-variant calls); a final `inspect` call
answered normally with the app still live.

**Result:** all 5 required + all 3 secondary expectations `met`. No interventions. Outcome `pass`,
adjusted score 1.0.
