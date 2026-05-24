# Backlog — Closed

Items moved here when fixed. Append-only trail for regression context and
extraction-just-in-case. See [`backlog.md`](backlog.md) for open items and
the shared conventions.

Each closed entry preserves its original H2 (`## B-0NN (severity): title`)
and body, plus a `**Closed**: YYYY-MM-DD — summary` line at the bottom.

## Pre-existing closed items (ui-revamp arc, 2026-05-22 and earlier)

`B-001` through `B-006` and `B-009` were closed during the `ui-revamp` arc
and merged into `main` as commit `4fb5d27` (v3.0.0+40). Their detailed
entries lived in the arc's `bugs.md`, which was deleted at merge time. The
short tags below are sufficient for "have we seen this before?" lookups; if
you need the full original write-up, `git show 4fb5d27~1:bugs.md` (or walk
the `ui-revamp` branch's history) recovers it.

- **B-001** — smart-roots showed the full filesystem.
- **B-002** — gesture-nav overlapped chrome at the bottom edge.
- **B-003** — 54 px immersive transition overflow stripe.
- **B-004** — settings entry-point `·` glyph was too small to hit.
- **B-005** — launch hint was once-only (now shows on every cold launch
  and fades after 3 s).
- **B-006** — background-mode hijacked the screen on first run.
- **B-009** — search scope was limited to `currentPath` instead of the
  whole library.

**Closed**: 2026-05-22 — shipped together in merge `4fb5d27`.

---

## B-007 (minor): Android Back exits Void silently — verify

**Symptom** (historical): Pressing Android Back from `VoidScreen` exited the
app silently. Audio kept playing but UI state was lost.

**Status**: Plausibly already fixed — `PopScope` is wired at
`lib/screens/void_screen.dart:302` with `_onPopInvoked` at line 454
that collapses the swipe-up browser, exits search, then walks the
library tree up before letting the OS pop. **Needs an explicit live
verification** before closing: on the emulator, press Back from various
chrome states and confirm the order above holds.

**Area**: chrome / navigation

**Closed**: 2026-05-24 — verified on emulator-5554, PopScope order holds across all five chrome states (root → background; subfolder → folder up; expanded swipe-up browser → collapse; search mode → exits search after the standard IME-dismiss tap; settings sheet → closes via Navigator pop).

---

## B-010 (major): Rapid `setSetting(themeVariant)` saturates the VM service

**Symptom**: Driving `ext.nothingness.setSetting name=themeVariant ...`
at >15 calls/second over the VM service stops the isolate responding.

**Likely cause**: VM-service RPC saturation, not user-facing logic. The
in-tree widget test `test/p6_adversarial_test.dart` exercises the same
code path at the same cadence in-process and passes.

**Desired**: Either rate-limit the extension handler, or document that the
test agent must throttle. No user-facing fix needed if the diagnosis
holds — but if a user-driven path can reach the same cadence (e.g. a
settings cycle held down with hardware key repeat), we need a real fix.

**Area**: testing / agent-service

**Closed**: 2026-05-24 — diagnosis confirmed on emulator-5554: each `setSetting` RPC costs ~140 ms steady-state (awaits `SharedPreferences.setString`), so sustained send rates above ~7/s back up the response queue. At >500/s pipelined the queue grows beyond reasonable drain timeouts, matching the original "stops responding" symptom; isolate recovers once drained. No user-driven path can reach this cadence: the only write paths are `agent_service._setSetting` and `VoidSettingsSheet._cycleVariant` (tap-only, no hardware-key repeat or timer). Documented the cadence ceiling and recovery in `.claude/skills/agent-emulator-debugging/SKILL.md`; recommended ≤5/s for `setSetting`-style calls, with `test/p6_adversarial_test.dart` as the in-process equivalent for higher cadences.

---

## B-019 (minor): Crumb and browser rows truncate the tail

**Symptom**: When text doesn't fit the row width, Flutter's default
`TextOverflow.ellipsis` clips the **end**. For the crumb this hides the
current folder name; for browser rows this hides the rest of the song
title. Both are the more informative end.

**Repro**: `drive.py call ext.nothingness.setSetting name=uiScale value=2.5`
→ navigate to `/storage/emulated/0/Music/Russian Rock`. Screenshot
`.tmp/agent_shots/crumb_scaled.png` shows:
- Crumb: `/storage/emulated…` — current folder gone.
- Browser rows: `Ария - Бесп…`, `Кино - Груп…` — song titles
  truncated to the artist + the start of the title.

**Desired**: Adopt a consistent "keep the meaningful tail" policy across
the chrome:
- Crumb: head-truncate, `…/Music/Russian Rock`.
- Browser file rows: head-truncate, `…бесп ангел`. (Folder rows are
  usually short enough not to matter, but the same rule should apply
  for safety.)
- Implement once as a small `MidEllipsis` widget that takes a
  `keepEnd` length hint, used by both call sites.

**Notes**:
- Crumb: `lib/screens/void_screen.dart:563-572`.
- Browser file rows: `lib/widgets/void_browser.dart:553-562, 469-487`
  (search result rows have a similar issue at lines 458-487).
- Watch RTL: the same trick that keeps the tail in LTR will keep the
  head in RTL, which is what RTL users actually want — so the
  implementation should respect ambient `TextDirection`.

**Area**: chrome / crumb / browser

**Closed**: 2026-05-24 — head-truncating widget added; wired into crumb + browser file rows + search result rows.

---

## B-016 (minor): Settings sheet has no at-a-glance status

**Symptom**: Opening settings drops the user straight into the MODE group.
No queue size, no shuffle state — both require leaving settings to check.

**Repro**: Screenshot `.tmp/agent_shots/settings_top.png` — header reads
`< settings`, then MODE → operating mode. Nothing surfaces queue length
or shuffle.

**Desired**: A non-scrolling status strip above the MODE group:
- queue size (e.g. `queue · 47 tracks`)
- shuffle toggle (live; toggling here calls
  `AudioPlayerProvider.shuffleQueue` / `disableShuffle`)

**Notes**: Header lives at `lib/widgets/void_settings_sheet.dart:858-891`.
Insert the new row between `_header` and the first `_groupHeader`. Use
`_toggleRow` for shuffle to match existing visual language. There is no
shuffle row anywhere else in settings today — confirmed by reading the
full `_buildGroups` method.

**Area**: settings

**Closed**: 2026-05-24 — status strip (queue size + shuffle toggle) added above MODE group in void settings sheet.

---

## B-013 (minor): Search input font too small; close is a tiny faded ×

**Symptom**: Entering search mode shrinks the input to `typography.crumbSize`
(same as the path readout) — noticeably smaller than the search-result
rows above it. Close is a single `×` glyph in `fgTertiary` (low-contrast)
at the row end; easy to miss.

**Repro**: long-press the crumb, type `the`. Screenshot at
`.tmp/agent_shots/search_the.png` (this session): the input "? the" reads
visibly smaller than each result row beside it, and the × glyph is
identical to the result-row dividers in tone.

**Desired**: Bump the search input to at least `typography.rowSize` (the
same size as the result rows). Make dismissal more discoverable: enlarge
the × hit target without changing the visual weight, accept swipe-down on
the crumb as a dismissal gesture, and confirm `_onSearchFocusChanged`
(`lib/screens/void_screen.dart:215-222`) really collapses search on
focus-out (it does, but only when the query is empty — that may also be
worth relaxing).

**Notes**: `_buildSearchCrumb` lives at
`lib/screens/void_screen.dart:579-613`.

**Area**: chrome / search

**Closed**: 2026-05-24 — search input bumped to `typography.rowSize` (parity with result rows); × kept at crumb-size/fgTertiary visual weight but wrapped in a 44×44 hit target keyed `void-search-close`; downward fling on the search crumb dismisses (gesture region keyed `void-search-crumb-region`); `_onSearchFocusChanged` now collapses on focus-out regardless of query (and clears the controller) — tap-away ends the session, re-tap resumes.

---

## B-017 (major): Mic permission blocks the library in OWN mode; raise min SDK to 29

**Symptom**: First-launch "tap to grant" gate requests microphone alongside
storage/audio — but worse, **denying mic blocks the entire library** even
when storage was granted.

**Repro** (code-only — fresh install needed for an end-to-end repro):
`LibraryController.requestPermission`
(`lib/controllers/library_controller.dart:220-235`):

```dart
final statuses = await [
  Permission.storage,
  Permission.audio,
  Permission.microphone,  // line 229 — bundled into the OWN-mode gate
].request();

hasPermission =
    (statuses[Permission.storage]!.isGranted ||
        statuses[Permission.audio]!.isGranted) &&
    statuses[Permission.microphone]!.isGranted;  // line 235 — blocks library
```

So if the user denies the surprise mic prompt, the library is
unreachable in OWN mode even with storage granted. Mic is not used in
OWN mode — it's a BACKGROUND-mode dependency for audio capture.

**Desired**:
1. **Raise `minSdkVersion` to 29 (Android 10)** in
   `android/app/build.gradle.kts`. With API 29 as the floor, scoped
   storage is universal, and `Permission.audio` (which
   `permission_handler` maps to `READ_MEDIA_AUDIO` on 33+ and to
   `READ_EXTERNAL_STORAGE` on 29–32) covers the library on every
   supported version. **Drop `Permission.storage` from the request and
   from the manifest's `READ_EXTERNAL_STORAGE`** — note that on 29–32
   `Permission.audio` will request the legacy `READ_EXTERNAL_STORAGE`
   under the hood, so the manifest entry may still be needed depending
   on `permission_handler` internals; verify before deleting.
2. Drop `Permission.microphone` from the OWN-mode gate. Mic is
   BACKGROUND-only.
3. Make `hasPermission` depend only on the audio permission.
4. Surface mic + notification-listener requests behind explicit buttons
   in settings (the EXTERNAL group already has both for BACKGROUND mode
   at `lib/widgets/void_settings_sheet.dart:527-546`). They only appear
   in BACKGROUND today — that's correct; leave it.
5. Keep `MediaControllerPage._ensureBackgroundPermissions`
   (`lib/screens/media_controller_page.dart:203-219`) as the BACKGROUND
   path — already gated on `_operatingMode == background`.

**Notes**: Also re-check the OWN-mode `_checkPermissions` path
(`lib/screens/media_controller_page.dart:265-267`) which silently
requests `POST_NOTIFICATIONS`. That one is reasonable (lock-screen
controls need it on API 33+); just document the intentional split.
Current manifest has both `READ_EXTERNAL_STORAGE` and `READ_MEDIA_AUDIO`
— prune the former if step 1 verification allows.

**Area**: permissions / build

**Closed**: 2026-05-24 — minSdk 29; mic + storage dropped from OWN-mode gate; hasPermission keyed off audio only.

---

## B-018 (minor): Define a per-skin transport-row contract

**Symptom**: There is no shared convention for how each hero integrates the
chrome's transport row. Polo opts out entirely (bespoke LCD-style
controls); Spectrum, Dot, and Void all *can* respect the global
`transport` setting, but each has its own implicit layout assumption
about how much vertical room the transport row consumes and where it
sits relative to hero content. With `transport: off`, some heroes
(Dot in particular) end up with no on-screen controls at all and no
song info either.

**Repro**: Screenshot `.tmp/agent_shots/dot_top_transport.png` — Dot with
transport `top` renders the prev/play/next row beneath the pulsing dot.
At `transport: off` the Dot screen becomes "just a dot" with no controls
and no metadata, hero gestures only.

**Desired — transport contract**:
1. Each hero declares whether it **hosts** the chrome transport row
   (Spectrum, Dot, Void) or is **bespoke** (Polo). Hosted heroes are
   subject to the global `transport` setting (`top` / `bottom` / `off`).
2. Hosted heroes lay out their content within a guaranteed *hero band*
   (the region above the transport when `bottom`, below it when `top`,
   the full hero area when `off`). The shell allocates the transport
   slot; the hero never has to know its exact height.
3. `VoidScreen` (the shell) is the single owner of transport-row
   placement; heroes do not paint their own transport. Polo is the only
   exception and stays exempt.

**Implementation sketch**:
- Add a `bool ScreenConfig.hostsChromeTransport` (or equivalent) so the
  shell knows which heroes participate. Polo returns false; the others
  return true.
- The transport-position branch in `lib/screens/void_screen.dart:406-416`
  already does the placement work — extend it to gate on
  `hostsChromeTransport`, and pass the hero band size into the hero
  through `LayoutBuilder` constraints so the hero doesn't guess.

**Notes**: This is foundation for B-020 (Dot song info toggle) — both
features want the hero to honour a stable band given to it by the shell.

**Area**: heroes / chrome / transport

**Closed**: 2026-05-24 — transport contract: ScreenConfig.hostsChromeTransport gates chrome transport; Polo bespoke; hosted heroes get hero-band via Expanded.
