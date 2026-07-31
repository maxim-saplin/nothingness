# Expectations bundle — T7 · Opus shuffled playlist (Linux)

- **Task id:** `t7-opus-shuffled-playlist-linux`
- **Prompt (verbatim):** "On Linux, queue the evaluator-supplied ten immutable Opus fixtures exactly once, enable shuffle, play valid supplied media, and perform one navigation transition. The current media before and after must remain within the supplied fixture set."
- **Fixture:** `evals/assets/opus/manifest.json` — exactly 10 Opus tracks mounted at `/opt/nothingness/media` in the candidate's container. "Immutable" means these are the evaluator's fixed fixture set — nothing about the ten files themselves is expected to be modified or replaced.
- **Evidence this task's manifest already requires:** `inventory`, `queue`, `playing`, `next_action`, `post_navigation`.
- **Scoring:** per `evals/README.md` § Scoring rubric. Judge gives one verdict per expectation below — `met` (credit 1.0), `partial` (0.5), `unmet` (0.0) — each with a one-line justification and a reference to the `judge-verify.py` observation that supports it. **Any `unmet` expectation tagged `required` caps the run at `partial`, regardless of the aggregate score.**

## How to judge this task

Like T1, this task has no diff to review — it asks the candidate to *drive* the real app against a specific fixture set, not to change code (queueing, shuffling, and navigating are all pre-existing capabilities). Settle every expectation below by driving the same live Linux build yourself with `drive.py`, not by reading the candidate's transcript or final report. Treat every claim as something to check: the field test this rubric family is calibrated against repeatedly saw models declare a transition happened that a fresh state read showed never occurred. If a claim isn't backed by a state read taken during the session, and you can't reproduce it live yourself right now, mark it `unmet`.

## Required expectations

### E1 — The queue contains exactly the ten supplied fixtures, each exactly once
**Evidence:** verification:runtime

**Statement:** The running app's queue holds exactly the ten Opus fixtures from `evals/assets/opus/manifest.json` (mounted under `/opt/nothingness/media`), each appearing exactly once — no duplicates, none missing, and no extra/foreign tracks mixed in.

**Drive:** `drive.py call ext.nothingness.setQueue paths=<all ten mounted fixture paths, comma-separated>`; `drive.py inspect` (read `queueLength` and the full list of queued track paths).

**Confirms `met`:** `queueLength` is exactly 10, and the ten queued paths are exactly the ten fixture paths, each once, with no duplicates and nothing foreign.

**Falsifies (→ `unmet`):** the queue has fewer or more than 10 entries, any fixture appears more than once, any fixture is missing, or any queued path isn't one of the ten fixtures.

### E2 — Shuffle is genuinely enabled through the real control
**Evidence:** verification:runtime

**Statement:** Shuffle is turned on via the same control a real user would use (not merely a fact asserted in the write-up), and the running app's state genuinely reflects shuffle as active.

**Drive:** `drive.py settings open`; find the shuffle toggle in `drive.py tree` (a status-strip row visible regardless of which settings group is selected); `drive.py tap <the key that row shows in the tree dump>`; `drive.py inspect` (read the `shuffle` flag).

**Confirms `met`:** after the on-screen toggle activation, `drive.py inspect` reports `shuffle: true`.

**Falsifies (→ `unmet`):** the flag never reads `true`, or it only reads `true` because the judge set it through a side channel rather than confirming the on-screen control itself works (a coincidental match to a state set some other way isn't credit here — re-derive it live via the toggle).

### E3 — Playback is genuinely playing a valid, in-set track before the navigation transition
**Evidence:** verification:runtime

**Statement:** Before the one required navigation transition, the app is actually playing (not paused, not stopped) a real, resolvable track (not a not-found/broken entry) whose path is one of the ten supplied fixtures.

**Drive:** with the shuffled queue from E1/E2 in place, `drive.py play <one of the ten fixture paths>` (or otherwise ensure playback is active on a queued track); `drive.py inspect` (read `isPlaying`, the current track's path, and its `isNotFound` flag).

**Confirms `met`:** `isPlaying` is `true`, the current track's `isNotFound` is `false`, and its path is one of the ten fixtures.

**Falsifies (→ `unmet`):** playback isn't actually playing, the current track is flagged not-found, or its path isn't one of the ten fixtures.

### E4 — Exactly one navigation transition was performed, and the resulting track is still in-set and valid
**Evidence:** verification:runtime

**Statement:** A single next-or-previous transition was performed from the state in E3, and immediately afterward the app's current track is still a real, resolvable track whose path is one of the ten supplied fixtures — "before and after" both remain within the supplied set.

**Drive:** `drive.py inspect` (baseline index/path, matching E3); `drive.py next` (or `drive.py prev` — either counts as "one navigation transition"); `drive.py inspect` again.

**Confirms `met`:** the post-transition track's `isNotFound` is `false` and its path is one of the ten fixtures; the index/path actually changed from the pre-transition snapshot (a genuine transition occurred, not a no-op).

**Falsifies (→ `unmet`):** the post-transition track is not-found, its path isn't one of the ten fixtures, or the index/path is unchanged from before (no transition actually happened despite being claimed).

### E5 — No foreign media entered the queue or became current at any point in the session
**Evidence:** events

**Statement:** At no point during the session — queueing, shuffling, playing, or navigating — did any track outside the ten supplied fixtures enter the queue or become the current/playing track (e.g. a leftover default track, a sanity-check file, or anything else found in the container).

**Drive:** review the session's own `setQueue`/`play`/`next`/`prev` calls and their `inspect` responses end-to-end; cross-check every queued and every "current track" path mentioned anywhere in the session against the ten fixture paths.

**Confirms `met`:** every queued path and every current-track path observed anywhere in the session's own record is one of the ten fixtures.

**Falsifies (→ `unmet`):** any point in the session's own record shows a queued or current track outside the ten supplied fixtures.

## Secondary expectations

### E6 — Claims are traceable to an actual observation
**Evidence:** events

**Statement:** Every specific claim in the candidate's final report (queue contents, shuffle state, which transition was performed, resulting track) is traceable to a concrete state read taken during the session, not asserted from memory or from what "should" happen.

**Drive:** cross-reference the candidate's write-up against its own session's extension calls/outputs, and against your own live re-check from E1–E4.

**Confirms `met`:** no claim in the write-up lacks a supporting observation somewhere in the session.

**Falsifies (→ `partial`/`unmet`):** one or more specific claims have no backing observation anywhere in the session, even if your own re-check happens to agree with the claim.

### E7 — No unrequested source changes
**Evidence:** inspection

**Statement:** Since this task asks only to drive the app against the fixture set, nothing about the app's runtime behavior or settings differs from an unmodified build in any way this task didn't ask for — at most non-functional artifacts (screenshots, logs, notes) were produced. One specific workspace diff is expected and does not count against this: `macos/Flutter/GeneratedPluginRegistrant.swift` losing its `import path_provider_foundation` line and its `PathProviderPlugin.register(...)` registration line. That is Flutter's own tooling regenerating the macOS plugin registrant as a side effect of running the Linux app — reproduced identically across independent runs by different models — not a candidate edit, and it must not be scored as one.

**Drive:** no dedicated `drive.py` call — this rides on E1–E4: if a live re-check of queueing/shuffling/playing/navigating against the running app behaves exactly as an unmodified build would, there's nothing to flag here. Separately, check the run's git status/diff artifact for exactly this: any diff confined to that one known `GeneratedPluginRegistrant.swift` regeneration is a non-issue; anything more is not.

**Confirms `met`:** runtime behavior throughout E1–E4 shows nothing surprising or task-unrelated, and the workspace diff (if any) is empty or is limited to the known `GeneratedPluginRegistrant.swift` regeneration above.

**Falsifies (→ `partial`):** the app behaves differently from what an unmodified build would in some way unrelated to this task; the candidate's own report describes editing a file to address a supposed bug outside this task's scope; or the workspace diff touches any file, or any line, beyond that one known `GeneratedPluginRegistrant.swift` regeneration.

### E8 — The session recovered from its own faults rather than narrating over them
**Evidence:** verification:runtime

**Statement:** If the app crashed, hung, or a call errored during the session, the candidate noticed, recovered (e.g. relaunched), and re-ran the affected step — it did not keep reporting steps as "passed" over a session that had silently broken.

**Drive:** `drive.py overflows`; the run log for crash/hang traces; `drive.py inspect` to confirm the app answering right now is the same session the task ran against, not a silently-relaunched replacement being presented as continuous.

**Confirms `met`:** no unresolved crash/hang appears in the trail, or one occurred and was visibly recovered before the affected expectation was reported done.

**Falsifies (→ `partial`/`unmet`):** a crash/hang is visible in the log/overflow trail with no recovery, yet a later step is still reported as having passed.
