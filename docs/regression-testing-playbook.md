# Regression & Exploratory Testing Playbook

How we keep Nothingness from regressing, and how we hunt for new defects. This
doc has three parts: the **regression table** (scripted checks, one row per
behavior that must not break), the **exploratory discipline** (session-based
charters for finding the unknown), and the **adversarial discipline** (deliberate
abuse). It is driven by the `agent-emulator-debugging` skill (`drive.py` + the
`ext.nothingness.*` VM-service extensions) on a Linux desktop build and an
Android emulator, plus deterministic `flutter test` / `integration_test/`.

See also: `docs/agent-driven-debugging.md` (extension reference),
`docs/device-testing.md` (integration tests), `docs/backlog.md` /
`docs/backlog_done.md` (issue trail), `test/README.md` (async test conventions).

## How to run

```bash
D=.claude/skills/agent-emulator-debugging/scripts/drive.py
# Linux desktop (preferred for layout/gesture/portrait work; no ADB flakiness):
export DRIVE_TARGET=linux         # app launched via `flutter run -d linux` + fifo
# Android emulator (required for permissions, MediaStore/smart-roots, media-session):
export DRIVE_TARGET=android       # emulator-5554 via adb

$D inspect                        # router + library + playback + overflow snapshot
$D replay tool/regression/<area>.txt   # run a scripted regression script
```

**Golden rules** (apply to every session):
- One action, then read state back (`inspect` / `getPlaybackState` / `getAudioEvents`). Assert only the fields that matter.
- Keep mutating RPCs **≤5/s** with jitter; high-frequency hammering belongs in `flutter test` (`test/p6_adversarial_test.dart`), not the VM service.
- **Never** `adb force-stop` / `pm clear` / `drive.py reset --force` a live `flutter run` (60-90s rebuild). Use `drive.py restart` (hot) and the audio side-channel (`simulateInterruption`, `simulateNoisy`).
- **Velocity-gated gestures cannot be driven via adb/VM service** — verify hero swipes / flings in widget tests with `tester.fling(...)` (see `test/screens/void_screen_test.dart`, B-027).
- Timing claims come from the **timestamped** `getAudioEvents` ring buffer, never from wall-clock between `inspect` calls (RPC latency makes playback look 2-3× too fast).
- A finding is only filed with a **repro + evidence** (state JSON snippet + `drive.py shoot` PNG + `drive.py overflows`).

## Platform legend

`L` = Linux desktop · `A` = Android emulator · `B` = both. Some checks are
deterministic and live in `flutter test`/`integration_test` (marked `test`).

---

## Part 1 — Regression table

Every closed bug (B-001..B-038) has a row so we never re-ship it; core flows are
interleaved. `Steps` use `drive.py` shorthand (`$D`). Re-run per release and after
any change touching the linked area.

### Playback / transport

| ID | Plat | Title | Preconditions | Steps | Expected | Link |
|----|------|-------|---------------|-------|----------|------|
| RP-01 | B | play/pause toggles | queue set, playing | `$D pause` → `$D inspect` → `$D resume` → `$D inspect` | isPlaying flips false→true; userIntent tracks | core |
| RP-02 | B | next advances | queue ≥3, idx0 | `$D next` ×1; readback | idx 0→1, playing | core |
| RP-03 | B | prev <3s → previous track | playing idx1, pos<3s | `$D prev`; readback | idx→0 | core |
| RP-04 | B | prev >3s → restart current | playing idx1, pos>3s | `$D prev`; readback | idx stays 1, pos→0 | core |
| RP-05 | B | prev at ended tail → restart tail | tail track ended | `$D prev`; readback | idx stays tail, playing | core |
| RP-06 | test | auto-advance through queue | fake queue | emit ended ×N (`pump_until`) | each idx loads once, in order | B-036 |
| RP-07 | B | queue tail stops (no wrap) | idx=last | emit ended / let finish | playing=false, idx=last | core |
| RP-08 | B | duplicate ended doesn't skip | loadDelay, advance in-flight | emit ended twice mid-advance | lands idx+1, NOT idx+2 | **B-036** |
| RP-09 | B | gapless transition | 2s tracks queued | auto-advance; read `getAudioEvents` gaps | ended→loaded gap ≪ pre-fix ~426ms (≈100ms) | **B-037** |
| RP-10 | B | play/pause latency | Android focus | toggle; measure | no ~500ms stall (cached focus) | **B-011** |
| RP-11 | B | missing file skip | queue w/ bad path | auto-advance into it | marked isNotFound, skips to next, lastError=preflight_missing | core |
| RP-12 | test | all-tracks-fail stops | all paths fail | setQueue | every isNotFound, playing=false, no infinite loop | core |
| RP-13 | test | delayed/wrong-path error doesn't corrupt | valid current | emit error w/ wrong path | current track unaffected, not marked failed | B-cluster |
| RP-14 | B | one-shot → restore queue | queue idx1, one-shot a file | natural end | queue restored, advances to resumeAt+1 | B-014 |
| RP-15 | B | explicit next exits one-shot | mid one-shot | `$D next` | exits one-shot, steps from captured idx | B-014 |
| RP-16 | B | shuffle keeps playing track | playing | toggle shuffle | track keeps playing, no reload | core |
| RP-17 | B | becoming-noisy hard-pauses | playing | `$D call ...simulateNoisy` | paused, intent=pause, no auto-resume | core |

### Audio interruptions (deterministic — `integration_test/audio_interruption_test.dart`)

| ID | Plat | Title | Steps | Expected | Link |
|----|------|-------|-------|----------|------|
| AI-01 | test/A | pause-interrupt then resume | simulate begin(pause), end(pause) | pauses; resumes iff userIntent=play & paused-by-interruption | B-011 |
| AI-02 | test/A | duck = no-op | begin(duck) | keeps playing, no transport call | core |
| AI-03 | test/A | unknown focus loss no auto-resume | begin/end(unknown) | hard pause, never auto-resumes | core |
| AI-04 | test/A | interruption storm | rapid begin/end churn | state stays coherent, no crash | adversarial |

### Heroes / gestures

| ID | Plat | Title | Steps | Expected | Link |
|----|------|-------|-------|----------|------|
| HE-01 | B | tap toggles play/pause | tap hero surface | playPause; tap-ring feedback shows | B-012/B-030 |
| HE-02 | test | swipe distance ≥60dp fires prev/next | `tester.fling` | direction mapped, no double-fire | B-027 |
| HE-03 | test | velocity escape ≥300px/s fires | short fast `tester.fling` | prev/next fires even <60dp | **B-027** |
| HE-04 | B | spectrum visualizer non-zero while playing | play, all heroes | spectrumNonZero=true on spectrum/dot/polo/void | core |
| HE-05 | B | visualizer decays to flat when paused | play then `$D pause` | spectrumNonZero→false within ~2s; re-animates on resume | **B-038** |
| HE-06 | L | spectrum no overflow at uiScale=2.5 | `$D pref`/setSetting uiScale, screen spectrum | no overflow report; visualizer hidden below threshold | B-026 |
| HE-07 | B | Polo bespoke (no chrome transport) | screen polo | hero renders LCD skin; hostsChromeTransport=false | B-018 |

### Library / browser / search

| ID | Plat | Title | Steps | Expected | Link |
|----|------|-------|-------|----------|------|
| LB-01 | B | folder navigate + up | `$D nav <dir>` → `$D up` | currentPath updates both ways | core |
| LB-02 | A | smart roots scoped (not full FS) | inspect library smartRoots | curated roots only | B-001 |
| LB-03 | A | MediaStore scan | scan-on-startup | tracks populated from MediaStore | core |
| LB-04 | B | search is global (not currentPath) | enter search, query | results span whole library | **B-009** |
| LB-05 | B | search results = sub-queue, queue restored on exit | tap result, exit search | original queue restored; playing track continues | **B-014** |
| LB-06 | B | jump-to-now-playing glyph | play track in other folder | ⊙ glyph appears (debounced); tap opens browser + scrolls to row | B-015/B-031 |
| LB-07 | L | swipe-up browser open/close animation | browserPresentation=swipe_up | 280ms easeOutCubic; drag handle; drag-down closes | B-032/B-033 |
| LB-08 | B | search raises collapsed browser | swipe_up collapsed, enter search | browser auto-expands (see B-043) | **B-043** |
| LB-09 | B | head-truncation keeps tail | long folder/file names | MidEllipsis keeps meaningful end | B-019 |
| LB-10 | B | Android Back order | back at various depths | collapse browser → exit search → up → pop app | B-007 |

### Settings / persistence

| ID | Plat | Title | Steps | Expected | Link |
|----|------|-------|-------|----------|------|
| ST-01 | B | settings sheet open/close | `$D settings open/close` | opens promptly (no RPC hang), closes | B-024 |
| ST-02 | B | transport position cycle | setSetting transport top/bottom/off | row repositions/hides | B-022 |
| ST-03 | B | screen swap preserves per-skin config | set dot showSongInfo, hop dot→spectrum→dot | dot config survives | **B-028/B-023** |
| ST-04 | B | per-screen text scale | set textScale on dot/void/spectrum | hero typography scales; persists | B-035 |
| ST-05 | B | SOUND group gated by usesVisualizer | open settings on dot/void | no visualizer rows on dot/void | B-034 |
| ST-06 | B | status strip shows queue + shuffle | open settings | queue size + working shuffle toggle | B-016 |
| ST-07 | B | theme variant cycle | `$D variant dark/light/system` | theme updates | core |
| ST-08 | B | immersive toggle smooth | toggle immersive | no overflow stripe on transition | B-003 |

### Permissions / chrome / bootstrap

| ID | Plat | Title | Steps | Expected | Link |
|----|------|-------|-------|----------|------|
| PC-01 | A | OWN mode audio-only gate | fresh perms, own mode | audio perm only; mic/storage not blocking library | **B-017** |
| PC-02 | A | BACKGROUND mode external perms | background mode | mic + notification-listener buttons in EXTERNAL group | B-017 |
| PC-03 | B | settings entry-point hit target | tap ⋮ (44×44) | opens settings | B-004 |
| PC-04 | B | press feedback on tappables | tap rows/buttons | opacity dip (PressFeedback) | B-030/B-012 |
| PC-05 | A | gesture-nav doesn't bleed into chrome | bottom edge | chrome opaque, no bleed | B-002 |
| PC-06 | A | cold-start first frame fast | cold launch | TTFF < ~500ms, no >100-frame skip | B-008 |
| PC-07 | B | launch hint every cold launch | cold launch | "long-press a folder" hint, fades 3s | B-005 |

### Portrait / phone-frame (Linux, gated on B-042)

| ID | Plat | Title | Steps | Expected | Link |
|----|------|-------|-------|----------|------|
| PF-01 | L | phone frame applies | `$D emulate phone` → `$D shoot` `$D inspect` | content letterboxed to ~390×844; getSettings.phoneFrame="390x844" | **B-042** |
| PF-02 | L | portrait overflow sweep | emulate phone/small/tiny, cycle heroes+settings | no overflow reports in any screen | B-040/B-041 |
| PF-03 | L | text scale on all screens incl Polo | emulate phone, set textScale per screen | scales consistently; Polo honors it | **B-041** |
| PF-04 | L | now-playing artist+song hierarchy | emulate phone, play track | Artist + Song shown as two levels (see B-040) | **B-040** |

---

## Part 2 — Exploratory discipline (session-based)

We use **session-based test management (SBTM)**: time-boxed *charters*, not
scripts. Each charter is one focused session (~30–45 min) against one area on
one surface, logged as it runs.

**Charter template:**
> **Charter:** explore `<area>` on `<L|A>` for `<budget>`.
> **Heuristic:** SFDIPOT — Structure, Function, Data, Interfaces, Platform, Operations, Time.
> **Setup:** `<drive.py preconditions>`.
> **Log:** every anomaly as a finding (format below); note coverage + untested-but-suspicious areas at the end.

**SFDIPOT prompts** (ask these while poking the area):
- **Structure** — what widgets/keys exist here? (`$D tree`, `$D getSemantics`)
- **Function** — what is each control supposed to do? does it?
- **Data** — empty / huge / unicode / duplicate / missing inputs.
- **Interfaces** — transitions in/out of this area (back, search, settings, jump glyph).
- **Platform** — Linux vs Android divergence; portrait vs landscape (`$D emulate`).
- **Operations** — realistic user flows end-to-end.
- **Time** — rapid sequences, interruptions, backgrounding, slow loads.

**Suggested charters** (one per area; expand as needed): heroes & feedback ·
browser navigation & swipe-up · search lifecycle · settings & per-screen config ·
transport & queue · library/permissions (A) · portrait layout (L, post-B-042).

**Finding format** (one block per candidate defect, written to `.tmp/regression/<worker>-<shard>.md`):
```
### CAND-<worker>-<n>: <one-line symptom>
- area: chrome|search|transport|permissions|browser|heroes|settings|playback|library
- device: L|A|both
- severity-guess: minor|major|blocker
- repro: <exact drive.py / fling sequence>
- evidence: <state JSON snippet · .tmp/agent_shots/<name>.png · overflow/logcat snip>
- related-closed-bug: B-0NN | none
```

## Part 3 — Adversarial discipline

Deliberately abuse the app. **Route each vector to the surface that can actually
exercise it** (this is the single biggest reliability lever):

| Vector | Where | How |
|--------|-------|-----|
| Rapid-input races (20+ ops <100ms) | `flutter test` | `test/p6_adversarial_test.dart` pattern — VM service >5/s backs up and *looks* like a hang |
| Velocity / gesture edges (~300px/s boundary) | `flutter test` | `tester.fling` at boundary velocities; adb cannot do velocity |
| Lifecycle / interruption storms | `integration_test` + light device confirm | `simulateInterruption` begin/end churn; on device via `$D call ...simulateInterruption` (never force-stop) |
| Missing / malformed files | `flutter test` + device smoke | `TestHarness.setExistsMap` false; `$D play /does/not/exist.wav` then read overflow/lastError |
| Extreme settings values | device (≤5/s) + test | `$D emulate 280x653`, uiScale/textScale extremes; rapid flips in test |
| Concurrent drivers on one app instance | **forbidden** | one worker leases one device; collisions corrupt results |

Adversarial findings use the same `CAND-*` format and flow to the same triage.

## Triage → backlog

The orchestrator (not the workers) aggregates `.tmp/regression/*.md`, dedupes by
`(area, symptom)` (collapsing L+A duplicates to `device:both`), cross-references
`docs/backlog_done.md` (a match = a **regression** of B-0NN — link it), and files
survivors as new `B-0NN` entries in `docs/backlog.md` per the convention there
(monotonic ids; check both backlog files). Fixed items move to `backlog_done.md`
with a `Closed: YYYY-MM-DD — …` note.

## Lessons learned (first campaign, 2026-05-30)

Orchestration mechanics (the parts that bit us):
- **Run workers as FOREGROUND concurrent agents.** Background (`run_in_background`)
  sub-agents are in-process to the orchestrator and are **killed when its turn
  ends or the terminal crashes** — they silently produced nothing. Spawn the
  swarm as parallel foreground `Agent` calls in one message so they complete
  within the turn; the orchestrator stays lean by reading only their compact
  return summaries + the on-disk findings files (never the agent transcripts).
- **Append findings to disk incrementally**, after each shard — a crash then
  costs only the current step, not the whole session.
- **Device leasing is mandatory.** drive.py hard-codes `.vm_ws.txt`,
  `/tmp/flutter_run.log`, `/tmp/flutter_input` as singletons; two drivers sharing
  them silently talk to the wrong app. Each device worker gets its own git
  worktree (→ its own `.vm_ws.txt`), its own flutter-run log, and exactly one
  app instance. Only one driver per instance, ever.
- **`flutter run` launch on Linux:** newlines collapse in the harness `eval`
  (use single-line commands) and the `/tmp/flutter_input` fifo needs a
  `run_in_background` writer (a plain `&` writer dies).

What is and isn't VM-service-drivable:
- **Not drivable via the 27 extensions** (push to widget/integration tests):
  velocity-gated gestures (`tester.fling`), per-skin config retention
  (B-028/B-023), search entry + browser expand/collapse (B-043), swipe-up
  animation. The device sweep can confirm overflow/state but not these.
- **SoLoud on the headless Linux build free-runs its position clock** in real
  wall-clock even across app pause — `prev` "<3s vs >3s" reads can cross the
  threshold during driver sleeps. Minimize latency or assert in widget tests;
  get all timing from the timestamped `getAudioEvents` ring buffer.
- **Android driving is currently blocked** — the debug build fails to compile
  `flutter_soloud` for arm64 (host snap glibc headers leak into the NDK
  sysroot; see **B-045**). Until that's fixed, Android shards (A1-A4 + on-device
  playback) can't run; Linux desktop + deterministic tests carry coverage.

Health snapshot at first run: the deterministic suite is green (336 tests);
B-036/B-037 (gap ≈30ms)/B-038/B-026/B-042 all hold on Linux; the only product
finding was **B-044** (an out-of-UI-range uiScale overflow, now fixed).
