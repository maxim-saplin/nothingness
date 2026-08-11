# T2 · Cassette settings placement (Linux) — judge-t2

**Outcome: `partial`** (raw 0.875, penalty 0, adjusted 0.875; capped at `partial` because required E5 is `unmet`).
0 interventions. Candidate settled on its own at 531s of an 1800s budget for $0.042.

## What the model actually did

It spent its first ~4 minutes reading the repo, then made a single-file change to
`lib/widgets/void_settings_sheet.dart` (24 insertions, 10 deletions, nothing else touched). The
approach: wrap the existing cassette-variant `_Cycle` in the `DISPLAY` section with `if
(!Platform.isLinux)`, and add a second copy of that row in the `LOOK` group immediately after the
`void-settings-screen` row, guarded by `if (Platform.isLinux && cassetteCfg != null)` where
`cassetteCfg` is the current screen config downcast to `CassetteScreenConfig`. It hit two rounds of
analyzer errors (a missing paren, an undefined name, then an unnecessary cast and a no-op `!`) and
cleared them before moving on — `flutter analyze` was clean at the end.

It then built and launched the Linux app for real, set the screen to cassette, opened the settings
sheet, took a screenshot, and cropped the top half of it with PIL. It never looked at either image
(it only `ls -l`'d their byte sizes), and finished by presenting the crop as proof.

I did not intervene at any point.

## What I verified with my own hands

I drove the candidate's still-running build in its container throughout — `drive.py` reads,
`tapByKey` activations, `getSemantics`, `getSettings`, `getOverflowReports`, and my own screenshots
captured through `judge-verify.py`. I read the settings sheet via `getSemantics` (not the widget
tree) and used consecutive `indexInParent` with abutting y-ranges to settle adjacency.

**E1 — met.** With screen = cassette the sheet reads `indexInParent 5 = "screen / cassette"`
(y 231–276) followed immediately by `indexInParent 6 = "variant / Tape · Mono"` (y 276–321), then
`immersive` at 7. Abutting rects, consecutive indices, no group header or gap between them. My own
screenshot of that state, read plainly, shows the same order rendered: `screen  cassette` and
directly under it `variant  Tape · Amber`. The row was genuinely removed from `DISPLAY`, not
duplicated — the `DISPLAY` group now reads debug layout / text size / haptics.

**E2 — met.** Five consecutive on-screen taps of `void-settings-screen` walked
cassette → spectrum → polo → dot → void → cassette, i.e. the full established cycle back to the
start, with the row's own displayed value tracking every step. Separately, `drive.py screen <name>`
for all five screens was reflected back both in `getSettings` (`screenType`) and in the row's
displayed value, so the row and the setting are still connected in both directions. On the second
visit to cassette the E1 adjacency held again, with no stale state.

**E3 — met.** This was the "moved the label, dropped the wiring" risk, and the wiring survived.
Tapping `void-settings-cassette-variant` in its new position cycled
Mono → Amber → Colour → Minimal → Mono, the row's value tracking each tap. `drive.py cassettevariant
3/1/4/2` moved it the other way and the row's value matched each time. The change is real, not
cosmetic: with the sheet closed, variant 2 renders the amber tape artwork on the cassette screen
while variant 4 renders the minimal "SIDE A / No tape loaded" layout.

**E4 — met.** For spectrum, polo, dot and void, the row immediately after `screen` is `immersive` —
the pre-change next row — with no cassette-only control injected anywhere. Each of those screens'
own controls still respond to on-screen activation: spectrum `bar count` 24→8→12, polo `bar style`
solid→glow, dot `show song info` off→on, void `debug layout` off→on.

**E5 — unmet. This is the one real failure.** Both PNGs the candidate produced show the **cassette
playback screen** — the tape-reel artwork, the transport buttons, the word "empty" — and not the
settings sheet at all. Not a single settings row appears in either image, so the adjacency they are
captioned as proving cannot be read off them. The cause is visible in its event stream: it chained
`drive.py screen cassette && drive.py settings open && drive.py shoot cassette_settings_top` as one
command that returned in 0.27s, so `ext.nothingness.screenshot` rasterized a frame from before the
sheet's first paint. It then cropped that same wrong PNG (`img.crop((0, h*0.08, w, h*0.55))`) and
embedded the crop in its final answer under the heading "Screenshot (Cassette selected; relevant
region)". This is the second recorded field-test failure mode exactly: the model's own screenshot,
read plainly, does not show what its write-up claims.

To be fair to it I checked this was not a harness limitation. It is not: my own captures of the same
state, same app, same 1278×720 resolution show the sheet plainly. The sheet does take a moment to
appear — I saw the same one-state lag when `drive.py settings close` returned `{"closed": true}`
while the screenshot still showed the sheet — but a short wait, or simply looking at the resulting
image once, is all it took. The candidate did neither.

**E6 — met.** The placement claim does not rest on an image: `getSemantics` gives the consecutive
`indexInParent` 5/6 with abutting y-ranges and the live variant value, and `getSettings` confirms
`screenType: cassette` in the same capture. Structural dump and screenshot agree on both order and
value. (`getSemantics` answered fully on this build — it was not the "semantics not available" case
the rubric warns about.)

**E7 — met.** The full row list is unchanged apart from the inserted row. Across cassette plus all
four other screens the order is MODE / operating mode / LOOK / theme / variant (theme) / screen /
[cassette variant, cassette only] / immersive / transport / browser / full screen / ui scale /
LIBRARY / prefer filename / smart folders / then the per-screen SOUND and DISPLAY groups — matching
the pre-change source order for every unrelated pair, with nothing added, removed or renamed. I also
confirmed a full dump before and after tapping five unrelated rows was byte-identical in ordering.
Every unrelated row I could activate changed its displayed value: immersive off→on, transport
top→off, browser swipe up→fixed, prefer filename off→on, smart folders on→off, theme variant
system→dark, debug layout off→on, plus the spectrum SOUND rows. The `theme` row cycles to itself,
which is correct rather than broken — `ThemeId` has exactly one value (`void_`).

**E8 — met.** `getOverflowReports` was `count: 0` both before and after roughly forty sheet opens,
screen switches and row activations. At the end the app still answered `inspect` normally, `git
status` showed only the one modified file, and the runtime lens reported no overflows.

## Limits of my own testing, stated so they are not read as candidate faults

- **Sliders cannot be driven by synthetic pointers on this build.** Polo's and void's only
  *screen-specific* controls are text-size sliders, so for those two screens I exercised a
  neighbouring row of theirs instead (polo's SOUND `bar style`, void's `debug layout`). That is my
  blind spot, not a gap in the candidate's work.
- **`void-settings-spectrum-text-color` is unreachable by key**, because the settings `ListView`
  only builds ~20 children and spectrum's `DISPLAY` group starts at index 19. Pre-existing harness
  limitation; I used spectrum's SOUND rows instead.

## One judgement call worth flagging to the manager

E1's falsifier list ends with "…or the screenshot the candidate supplies doesn't actually show the
two rows adjacent even though the write-up claims it does," which read in isolation would also fire
here. I scored E1 `met` anyway, because the rubric's own "How to judge this task" section tells the
judge to settle every expectation by driving the running build rather than trusting the candidate's
screenshot, maps the three prompt clauses to E1 (where the row sits) and E5 (a screenshot proving
it), and states that a correct implementation must pass every expectation. The placement genuinely
is correct in the running app — I confirmed it four independent ways — so the screenshot defect is
priced once, in E5, rather than twice. Either reading lands the run at `partial`, since E5 is
required and unmet; only the raw score differs (0.875 vs 0.75). Flagging it in case the manager
reads that clause more literally.
