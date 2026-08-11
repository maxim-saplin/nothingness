# Judge notes — t3-settings-placement-color-scheme-linux (attempt-03)

This trial's original judge died mid-scoring after an API error. The candidate had already
finished naturally (`judge_finish:` reason, `timed_out: false`, 364.7s of an 1800s budget, 58
tool calls) and the prior judge had already collected the run and captured most of the
verification evidence before dying. I resumed from that state — did not start a new trial — and
finished scoring against the live, still-running container.

## What the candidate did

In `lib/widgets/void_settings_sheet.dart` it added `final cassetteCfg = cfg is
CassetteScreenConfig ? cfg : null;` and, right after the `screen` row, `if (Platform.isLinux &&
cassetteCfg != null)` injects the cassette-variant `_Cycle` row with label `'color scheme'` on the
same `void-settings-cassette-variant` key and the same cycling handler it always had. The
non-Linux/non-cassette code path (further down, in the DISPLAY group) is guarded by the mirror
condition `if (!Platform.isLinux)`, so the two render paths are mutually exclusive — there is no
way to get a duplicate or a stale "variant" row. This is a clean, minimal, correctly-scoped fix.

## What I verified live (driving the still-running container myself)

- **E1/E2 (met):** `getSemantics` with screen=cassette shows `"screen\ncassette"` at
  `indexInParent: 5` immediately followed by `"color scheme\nTape · Mono"` at `indexInParent: 6`
  — adjoining rects (231–276, 276–321), nothing between. Exactly one `"color scheme"` occurrence
  in the whole sheet; no leftover `"variant"`-labeled cassette row anywhere. Held again after I
  cycled away to another screen and back to cassette.
- **E3 (met):** I tapped `void-settings-screen` on-screen five times live: cassette → spectrum →
  polo → dot → void → cassette, each step reflected in `getSettings`/`getSemantics`. The
  screen/color-scheme adjacency survives the revisit.
- **E4 (met):** On-screen taps of `void-settings-cassette-variant` advanced the row's own label
  Tape·Mono → Tape·Amber → Tape·Colour → Minimal. Separately, `drive.py cassettevariant 1/2/3`
  also updated the same row's displayed value each time. Both paths move the same state; renaming
  the label did not disconnect the handler.
- **E5 (met):** For spectrum, polo, dot and void I switched screens live and read `getSemantics`
  each time — the row right after `screen` is that screen's own `immersive` row in all four
  cases, never a cassette control, and none of the four dumps contain the string `"color scheme"`
  at all. Tapping `immersive` on-screen also flipped its state, confirming the neighboring row
  still functions.
- **E6 (unmet, required — caps the run at partial):** I opened the candidate's actual screenshot
  deliverable, `artifacts/agent-shots/cassette_settings_region.png`. It shows the **closed cassette
  player screen** — cassette artwork, a playback progress bar at 0:00, an empty library list, and
  the bottom transport icons. The settings sheet is not open in this image at all: no `screen` row,
  no `color scheme` row, nothing settings-related is visible. This is exactly the calibrated
  failure mode this rubric warns about: the candidate's write-up asserts the screenshot shows "the
  updated region" of Settings, but the image itself shows a different screen entirely.
- **E7 (met):** I captured my own fresh `getSemantics`/`getSettings`/tree dump live with
  screen=cassette; it independently corroborates the row order and exact label/value text, so the
  placement/rename claims don't rest on a single image.
- **E8 (met):** Beyond `immersive`, I also tapped `transport` on-screen (cycled to `top`) and
  confirmed it changed. The full sheet order (MODE → operating mode; LOOK → theme, variant,
  screen, [color scheme when cassette], immersive, transport, browser, full screen, ui scale;
  LIBRARY → …; DISPLAY → …; haptics) matches the expected structure with nothing else reordered,
  added, or renamed.
- **E9 (met):** `overflows` stayed at `{"count": 0}` throughout my entire live exercise — before,
  during, and after cycling all five screens, tapping the renamed control repeatedly, and toggling
  unrelated rows — and `drive.py inspect` answered normally at the end.

## Net

Eight of nine expectations met on genuine live evidence (mine and the prior judge's, both
cross-checked). The implementation itself is correct, minimal, and well-scoped to Linux+Cassette.
But E6 is a required expectation and it is unmet: the candidate never actually captured the
screenshot it claims to have captured. Per the rubric, that caps the run at `partial` regardless
of how strong the rest of the score is. `raw = 8/9 = 0.889`, no intervention penalty, `adjusted =
0.889`, but `required_unmet` forces `score = 2`, `outcome = partial`.

## On the resume itself

Resuming a half-scored run worked cleanly with no real friction: `collect.json`, `summary.json`,
and the prior judge's `judge-observations.jsonl` (45 events reads, 8 verifications, 2 inspections)
were all intact and immediately usable, and the container was still up so I could drive the app
myself rather than trust the dead judge's captures blind. The one wrinkle: `judge-run.py evidence`
does **not** accumulate a running observation list — each call only returns the event-chain batch
plus one fresh inspection/verification pair from *that* call, not the prior judge's labeled
captures (`t3_cassette_placement`, `t3_screen_cycle_end`, etc.). Calling it more than once (I called
it three times while getting oriented) just produces more one-off inspection/verification
observations without surfacing the earlier ones — a judge who trusts its latest `decide_flags`
verbatim without cross-referencing `judge-observations.jsonl` directly would silently drop most of
the prior judge's evidence chain from the citation list. I had to read `judge-observations.jsonl`
by hand to reassemble the full list of what already existed before composing `--observation-id`.
That is worth calling out as a real rough edge in the resume path, separate from anything the
candidate did.
