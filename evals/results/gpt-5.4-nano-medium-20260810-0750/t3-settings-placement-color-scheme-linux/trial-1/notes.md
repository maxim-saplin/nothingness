# T3 — Cassette settings placement + color-scheme rename (Linux)

**Run:** `t1-t7-gpt-5.4-nano-medium-t3-settings-placement-color-scheme-linux-trial-01-attempt-01`
**Model:** azure-openai-responses / gpt-5.4-nano, thinking=medium · 55 tool calls · 493 s · $0.054 · 0 interventions

## What the model did

It spent roughly the first half of its run getting a Linux build up (repeated `drive.py preflight`
until `live VM=yes`, one dead end where it looked for the VM service URI in the wrong log path),
then made a single-file change to `lib/widgets/void_settings_sheet.dart` (+30/−12) and verified it
with a screenshot.

The change has two halves. In the main row list it inserts, right after the `screen` row, a
`_Cycle` labelled `color scheme` that cycles `CassetteVariant`, guarded by
`Platform.isLinux && cfg is CassetteScreenConfig`. In the per-screen `displayRows` builder it
threads a new `showCassetteVariant` flag, passed as `!Platform.isLinux`, so the original cassette
variant row is suppressed on Linux and no duplicate is built. Both copies use the same
`ValueKey('void-settings-cassette-variant')`, which is safe only because exactly one of them is
ever constructed. The `displayRows` copy was also renamed to `color scheme`, so non-Linux platforms
get the rename without the move.

Worth noting as a design choice rather than a defect: the prompt's "On Linux" reads most naturally
as stating which platform the work is being done on, and the model instead encoded it as a literal
`Platform.isLinux` runtime condition, duplicating the cycle-construction code to do so. No
expectation in this bundle covers other platforms, and the rubric explicitly admits
correct-but-differently-implemented fixes, so this costs nothing here — but it is the kind of
literal-minded scoping that would read oddly in review.

## What I verified myself

Everything below I drove against the candidate's live container myself via `drive.py`, reading the
sheet with `getSemantics` (the widget tree overflows the 128k cap with the sheet open).

**E1 — placement.** With `screen=cassette`, the semantics dump shows `screen | cassette` at
`indexInParent` 5, rect y 231–276, immediately followed by `color scheme | Tape · Mono` at
`indexInParent` 6, rect y 276–321. Consecutive index, abutting y-ranges, nothing between them.

**E2 — exact label.** The semantics node carries label and value on separate lines, and the label
line reads exactly `color scheme` — lowercase, matching `theme` / `variant` / `screen`. There is
exactly one such row on the whole sheet. The `variant` row still present at index 4 is the
pre-existing *theme* variant (value `system`, key `void-settings-variant`), not a leftover cassette
row; I confirmed against the source that it comes from the untouched `ThemeVariant` cycle.

**E3 — screen control preserved.** Six on-screen taps of `void-settings-screen` walked the whole
cycle: spectrum → polo → dot → void → cassette → spectrum. After each tap the row's own displayed
value and `ext.nothingness.getSettings.screenType` agreed. On the return visit to cassette the E1
adjacency reappeared intact, which is the "second visit" case E3's falsifier calls out.

**E4 — renamed control preserved.** Four on-screen taps of the `color scheme` row advanced it
Tape · Mono → Tape · Amber → Tape · Colour → Minimal → Tape · Mono, a full wrap. Independently,
`drive.py cassettevariant 2`, `3` and `1` each landed and the row's displayed value tracked every
one. So the control moved and was renamed without losing its wiring, exercised in both directions.

**E5 — scoped to cassette.** For spectrum, polo, dot and void the row immediately after `screen` is
`immersive` in every case, and a scan of the full sheet found zero `color scheme` rows on any of
them. I then exercised those screens' own controls: spectrum's `text color` (Cyan → Purple → Mono)
and `media controls color` (Cyan → Purple), and dot's `show song info` (off → on → off), all
changed on on-screen tap. Polo and void have exactly one screen-specific control each — a text-size
slider — and I could not activate it: `ext.nothingness.dragByKey` aborts with a `MouseTracker`
assertion (`(event is PointerAddedEvent) == (lastEvent is PointerRemovedEvent)`), the known Linux
desktop limit on synthetic pointer drags. That limit applies to the unmodified build too and the
candidate's diff provably never touches those branches, so I treated it as a gap in my checking
rather than a defect — but I did not prove those two sliders still drag.

**E6 — screenshot.** The candidate captured `/workspace/.tmp/agent_shots/cassette_settings.png`
this session: the full settings sheet, `screen  cassette`, and `color scheme  Tape · Mono` legibly
on the very next line. That image satisfies E6 on its own terms. It is worth flagging that the
model's final answer instead linked a cropped derivative it made afterwards,
`cassette_settings_region.png`, which cuts off at y=270 and slices the `color scheme` row in half —
the label is only half-rendered and the value nearly illegible. Read alone, that crop would not
prove the adjacency it was offered to prove. The compliant full-frame shot is sitting right next to
it in the same deliverables directory, and my own independent capture reproduces it exactly, so I
scored this met rather than partial: the model did produce a screenshot that shows what it claims,
it just presented the worse of its two.

**E7 — corroboration.** `getSemantics` and `getSettings` were captured in the same verification
observation as the screenshot and agree with it on row order, exact label text and current value.

**E8 — nothing else disturbed.** I diffed full-sheet semantics dumps for cassette against a
non-cassette screen, in both `own` and `background` operating mode. The only structural difference
is the inserted `color scheme` row; every unrelated row (immersive, transport, browser, full
screen, ui scale, LIBRARY, prefer filename over tags, smart folders, DISPLAY, debug layout …)
keeps its relative order, and nothing was added, removed or renamed. I then tapped `immersive`
(off → on), `transport` (bottom → top), `browser` (fixed → swipe up), theme `variant`
(system → dark), `smart folders` (on → off) and cassette `haptics` (on → off) — all responded. The
`theme` row does not change on tap, but that is pre-existing: `ThemeId` is a single-value enum
(`void_`), so its cycle is a no-op in any build.

**E9 — stability.** `getOverflowReports` returned count 0 both before and after roughly thirty
sheet opens, screen switches, variant cycles and row taps, and `drive.py inspect` answered normally
at the end with the app still live. The one exception thrown during my session was the
`MouseTracker` assertion from my own `dragByKey` attempt, which is a driver limitation, not app
instability — the app kept responding after it.

## Verdict

All six required and all three secondary expectations met; nothing about the change failed to
reproduce under my own driving. Two caveats recorded above and neither costs credit: the two
slider-only screens could not be drag-tested because of a known Linux desktop limit, and the
screenshot the model chose to present is a bad crop of a good one it had already taken.
