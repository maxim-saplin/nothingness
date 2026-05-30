# Backlog

Single-file issue tracker for in-flight UX/bug work on `main`. Continues the
`B-NNN` numbering from the closed `ui-revamp` arc (last id was B-010).

## Conventions

- One H2 per issue: `## B-0NN (severity): title` — severity is `minor` /
  `major` / `blocker`.
- Body uses these fields (omit any that don't apply):
  - **Symptom** — what the user observes.
  - **Repro** — exact sequence (driver commands welcome) plus the runtime
    evidence we collected (numbers, screenshots, logcat snips).
  - **Desired** — what we want it to do.
  - **Notes** — code pointers (`path/to/file.dart:line`), constraints,
    cross-refs (`see B-0NN`).
  - **Area** — short tag (`chrome`, `search`, `transport`, `permissions`,
    `browser`, `heroes`, `settings`).
- When an item is fixed, **move the entry to `backlog_done.md`** and append
  a `**Closed**: YYYY-MM-DD — one-line summary of the resolution (commit
  hash if useful)` line at the bottom of the moved entry. Keep the trail —
  it's cheap to read and pays off when a regression looks familiar.
- New ids are assigned monotonically across both files. Don't reuse closed
  ids; check `backlog_done.md` too when picking the next id.

---

## B-045 (major): Android debug build fails — flutter_soloud arm64 NDK sysroot leak

- **Symptom** — `flutter run -d emulator-5554 --debug` (and any Android build of
  the current tree) fails during Gradle `assembleDebug` while cross-compiling the
  `flutter_soloud-4.0.6` native plugin for **arm64-v8a**. Blocks ALL on-device
  Android testing — the regression swarm's Android shards (A1-A4, on-device
  playback RP-01..11) could not run.
- **Repro** — Android regression worker 2026-05-30, 4 build cycles. NDK 27
  aarch64 clang (`--target=aarch64-none-linux-android21`) pulls the host snap
  glibc headers `/snap/flutter/current/usr/include/c++/9/memory` →
  `error: cast from pointer to smaller type 'uintptr_t' loses information` and
  `bits/wchar2.h: "Assumed value of MB_LEN_MAX wrong"`. Deterministic
  host-toolchain/sysroot defect — NOT emulator flakiness (`emulator-5554` stayed
  `device`; adb push/grant worked).
- **Notes** — `abiFilters` in `android/app/build.gradle.kts` gate only the `:app`
  module; the `flutter_soloud` `externalNativeBuild` still enumerates arm64-v8a,
  and `CI_EMULATOR_ABI=x86_64` did not suppress it. Needs a non-leaking aarch64
  NDK sysroot (snap glibc headers must not leak into the NDK include path), or
  constraining the soloud build's abiFilters, or a non-snap Flutter toolchain.
  Environmental/toolchain — needs maintainer attention; out of scope for the
  in-app QA campaign. Area — build/tooling.

## B-039 (minor): hero swipe direction is unintuitive + no animated card transition

- **Symptom** — Horizontal swipe on the hero skips prev/next, but two things
  feel wrong: (1) the direction is backwards relative to a card mental model,
  and (2) there is no card motion — the track swaps instantly with only a brief
  `‹`/`›` flash, so it's unclear which way advances vs goes back.
- **Current behaviour** — Swipe **right** → `next()`, swipe **left** →
  `previous()` (`lib/screens/void_screen.dart:366-378`, and the B-027 velocity
  escape `:386-398`: `v>0`→next, `v<0`→prev). Feedback is a glyph flash only
  (`HeroFeedbackSurface.flashSwipe` / `triggerSwipe`,
  `lib/widgets/hero_feedback_surface.dart:99-106`) — no card slides.
- **Desired** —
  1. **Reverse the mapping** to match the card metaphor: dragging the current
     card **left** brings the **next** track in (from the right); dragging
     **right** brings the **previous** track in. (i.e. left→next, right→prev —
     the opposite of today.)
  2. **Animated card swipe**: the current track's card slides off in the drag
     direction while the incoming card animates in from the opposite side,
     instead of the instant swap + flash.
- **Notes** — Update both the distance trip (`_onHeroHorizontalDrag`) and the
  velocity escape (`_onHeroHorizontalDragEnd`) so they stay consistent, plus the
  `flashSwipe(±1)` direction args and the `_swipeRight`/glyph logic in
  `hero_feedback_surface.dart:99-106,170-181`. Velocity-gated gestures can't be
  verified via `adb shell input swipe` (synthetic events miss Flutter's velocity
  thresholds) — regress with `tester.fling(...)`, see the B-027 pattern in
  `test/screens/void_screen_test.dart`. Cross-ref the swipe-up browser slide
  animation (B-033) for the existing card-transition style. Thresholds today:
  60 dp distance / 300 px·s⁻¹ velocity.
- **Area** — heroes

## B-040 (minor): now-playing should show Artist + Song as two heading levels; default metadata from filename

- **Symptom** — The hero shows the **track title** as the big headline and the
  **parent folder name** as the subtitle. The `artist` is never displayed, and
  there's no clear Artist/Song hierarchy.
- **Desired** —
  1. Render two distinct heading levels in the hero: **Artist** (H1) and **Song
     title** (H2) — a real typographic hierarchy, not title + folder.
  2. Metadata (`title`, `artist`) should **by default be parsed from the
     filename** (e.g. `Artist - Title.ext`), *not* ID3 tags / MediaStore.
- **Notes** — `AudioTrack` already carries `artist` (`lib/models/audio_track.dart:16`)
  but the void hero ignores it: it maps `track.title`→headline and
  `dirname(track.path)`→subtitle (`lib/widgets/heroes/void_hero.dart:17-18,67-85`).
  Filename parsing already exists — `DesktopMetadataExtractor` is filename-only
  (`lib/services/metadata_extractor.dart:179+`, splits on `" - "` via
  `_splitFilename`), but `AndroidMetadataExtractor` defaults to MediaStore unless
  `useFilenameOverride` (default `false`, `:23,29-32`); the `useFilenameForMetadata`
  setting is wired at `lib/testing/agent_service.dart:445`. Flip the default so
  filename parsing wins, and surface `artist` in the hero (and likely the other
  heroes/browser rows). Sub-headings will need their own typography tokens — see
  B-041 for the font-size work, and B-042 to verify the layout at phone size.
- **Area** — heroes

## B-041 (minor): font-size adjustable on ALL screens + set reasonable default sizes

- **Symptom** — The "text size" control isn't available on every screen, and
  some default sizes are off / inconsistent.
- **Desired** — Every screen exposes a font-size (text-scale) control, and the
  out-of-box default sizes are reasonable on a normal display.
- **Notes** — `textScale` exists on Void / Spectrum / Dot configs but **`PoloScreenConfig`
  has none** (`lib/models/screen_config.dart:58,89,171,251`), and the settings
  sheet only renders three "text size" rows (`lib/widgets/void_settings_sheet.dart:747,889,918`)
  — Polo is missing. Default inconsistency to fix while here:
  `SpectrumScreenConfig` const default `textScale = 0.6` but its `fromJson`
  default is `1.0` (`screen_config.dart:101` vs `:127`) — first run and a
  missing-key reload disagree. Pick sane per-screen defaults and make const ==
  fromJson. Hero title size is `typography.heroSize * config.textScale`
  (`void_hero.dart:75`); confirm the new Artist/Song levels (B-040) both scale.
- **Area** — settings

## B-043 (minor): searching does not raise a collapsed (swipe-up) browser

- **Symptom** — With the browser in swipe-up presentation and collapsed, entering
  search focuses the input but the browser stays parked offscreen, so search
  results are invisible.
- **Repro** — Set browser presentation to swipe-up (collapsed), trigger search
  (long-press crumb). Search field activates; results list never appears.
- **Desired** — Entering search auto-expands the browser when it's collapsed.
- **Notes** — `_enterSearchMode()` sets `_searchMode = true` and focuses the
  field but never expands the browser (`lib/screens/void_screen.dart:317-322`).
  It should call `_setBrowserExpanded(true)` when
  `_browserPresentation == BrowserPresentation.swipeUp && !_browserExpanded`
  (state at `:94`). Mirror the reverse on `_exitSearchMode` if the browser
  should re-collapse. Cross-ref the swipe-up browser work (B-033).
- **Area** — browser
