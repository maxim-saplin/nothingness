# Judge notes — t2-settings-placement-linux

**Run:** t1-t7-gpt-5.4-nano-low-t2-settings-placement-linux-run-06e17d7e9996
**Model:** azure-openai-responses / gpt-5.4-nano / low
**Outcome:** partial (score 2, raw 0.875) — E5 required expectation unmet caps the run at partial; the candidate also never finished its turn.

## What the candidate did
It located the settings sheet builder (`lib/widgets/void_settings_sheet.dart`), removed the cassette-variant `_Cycle` from inside the `CassetteScreenConfig` `displayRows` block, and re-inserted it in the static row list immediately after the `_Cycle('void-settings-screen', ...)` row, guarded by `if (cfg is CassetteScreenConfig)`. The variant's original handler (cycle `CassetteVariant.values`, `saveScreenConfig`) is preserved verbatim. Net diff: +16/-10 in one file, `flutter analyze` clean. It then tried to drive the app to capture the required screenshot but launched `flutter run -d linux` directly in the foreground, which blocked its session; its event stream froze for ~6 minutes and it never ran `shoot`. I finished the run mid-turn and drove the app myself.

## Per-expectation findings (all verified live on my own launch of the built app)
- **E1 (met):** With screen=cassette the semantics dump shows `screen / cassette` (indexInParent 5, y231–276) immediately followed by `variant / Tape · Mono` (indexInParent 6, y276–321) — consecutive indices, abutting y-ranges, no header/gap. My screenshot renders the same order.
- **E2 (met):** Tapping the screen row on-screen cycled cassette→spectrum→polo→dot→void_→cassette (full loop); direct `screen <name>` calls were reflected back in the row's displayed value. Both directions wired.
- **E3 (met):** `cassettevariant` calls moved the row value (1→Tape·Mono, 2→Tape·Amber, 3→Tape·Colour, 4→Minimal; 5–7 clamp to Minimal — a drive.py quirk, only 4 enum values), and on-screen taps advanced the variant exactly one step per tap through the cycle. Row value tracks both ways.
- **E4 (met):** For spectrum/polo/dot/void the row right after `screen` is always `immersive` — no cassette control injected (spectrum bundle cited). Representative controls per screen still respond: spectrum bar-count 24→8 and decay medium→fast, dot show-song-info off→on, void debug-layout off→on.
- **E5 (unmet, required):** The candidate produced no screenshot. It deadlocked in a foreground `flutter run` and never captured one; `flutter_evidence_exists=false` and the only PNG in the container is my own judge capture. The task explicitly required the candidate to provide a screenshot, and none exists among its deliverables. This is exactly the field-test failure E5 guards against.
- **E6 (met):** getSettings (screenType=cassette) plus the semantics row order/values independently corroborate the screenshot's placement claim.
- **E7 (met):** Unrelated rows keep their pairwise order across cassette and non-cassette screens (MODE/operating-mode, LOOK/theme/theme-variant, screen, immersive, transport, browser, full-screen, ui-scale, LIBRARY…, SOUND/DISPLAY); none added/removed/renamed, and immersive/transport/browser each changed value when tapped on-screen.
- **E8 (met):** `overflows` count 0 before and after repeatedly opening settings and switching all five screens; runtime lens shows the app alive and responsive at the end.

## Bottom line
The implementation is correct and minimal — a differently-shaped but behaviorally exact fix — and passes every behavioral expectation. The only miss is the required screenshot deliverable, which the candidate never produced because it hung the app launch. Correct code, unproven by the candidate's own hand, capped at partial.
