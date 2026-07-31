# Expectations bundle — T1 · Playback smoke (Linux)

- **Task id:** `t1-playback-smoke-linux`
- **Prompt (verbatim):** "Drive Linux app, smoke test play/pause, skip and fast forward"
- **Fixture:** `evals/assets/opus/manifest.json` — 10 tracks mounted at `/opt/nothingness/media` in the candidate's container.
- **Scoring:** per `evals/README.md` § Scoring rubric. Judge gives one verdict per expectation below — `met` (credit 1.0), `partial` (0.5), `unmet` (0.0) — each with a one-line justification and a reference to the `judge-verify.py` observation that supports it. **Any `unmet` expectation tagged `required` caps the run at `partial`, regardless of the aggregate score.**

## How to judge this task

This task has no "diff" to review — it asks the candidate to *drive* the real running app, not to change code. Settle every expectation below by driving the same live Linux build yourself with `drive.py` (`.agents/skills/agent-emulator-debugging/SKILL.md`), not by reading the candidate's transcript or final report. Treat the candidate's claims as things to check, never as evidence in themselves: the field test this rubric is calibrated against repeatedly saw models declare a transition happened ("fast forwarded 60s") that a fresh state read showed never occurred. If a claim isn't backed by a state read taken during the session, and you can't reproduce it live yourself right now, mark it `unmet` — an unverifiable claim earns no credit, it doesn't earn the benefit of the doubt.

## Required expectations

### E1 — The real app was actually driven live
**Evidence:** verification

**Statement:** The candidate exercised the real running Linux build through the `ext.nothingness.*` VM-service extension surface (`drive.py` or equivalent direct calls) — not `flutter test`/`integration_test`, not a description of what the code *should* do, not a session where the app never reached a drivable state.

**Drive:** `drive.py preflight` (a live Linux VM with extensions registered — `extension_count > 0` — was reachable during the session); `drive.py inspect` (the extensions answer right now, proving the harness was actually attached, not just launched).

**Confirms `met`:** the session shows concrete extension calls (play/pause/next/prev/seek/inspect, or their raw curl equivalents) issued against a live session, and you can reproduce a live, extension-answering Linux session yourself right now.

**Falsifies (→ `unmet`):** the only testing evidence is a `flutter test`/widget-test run or static code reading; the app was launched with plain `flutter run` or `dev/main_test.dart` (extensions never register, so `drive.py contract` has nothing to call against); or the session never got past a launch failure.

### E2 — Play/pause transition observed, not assumed
**Evidence:** verification:runtime

**Statement:** Starting playback and then pausing/resuming it produced the actual playing-state transition the candidate claims (playing → paused → playing, or the equivalent sequence they describe) — not merely a call that was issued with no check of its effect.

**Drive:** `drive.py play <a fixture path>`; `drive.py inspect` (read the playback block's playing flag); `drive.py pause`; `drive.py inspect`; `drive.py resume`; `drive.py inspect`.

**Confirms `met`:** each `inspect` snapshot's playing flag matches the expected value at that step, and matches what the candidate reported for that step.

**Falsifies (→ `unmet`/`partial`):** the flag doesn't change on a step where it should, or the candidate's write-up states a transition that a fresh `inspect` does not corroborate.

### E3 — Skip / track-change observed, not assumed
**Evidence:** verification:runtime

**Statement:** Invoking next/prev against a multi-track queue actually advanced the current track — both the track index and the active track's path changed — matching the direction the candidate claims.

**Drive:** load a queue of at least two fixture tracks (e.g. two `drive.py play <path>` calls or the equivalent multi-path queue call); `drive.py inspect` (note the current index and the active track's path); `drive.py next` (or `prev`); `drive.py inspect` again.

**Confirms `met`:** the index and path differ between the two snapshots, in the direction requested (next → the next queued track; prev → the previous one).

**Falsifies (→ `unmet`):** index/path unchanged after the skip call; the queue only ever held one track so no change was possible and the candidate didn't correct for that; or a change is claimed but the second snapshot shows the same track as the first.

### E4 — Fast-forward / seek observed, not assumed
**Evidence:** verification:runtime

**Statement:** Seeking forward within the current track actually moved playback position to the requested target within a concrete tolerance — matching the candidate's claim in both direction and magnitude, not just in the confidence of the write-up.

**Drive:** `drive.py inspect` (note the current position); `drive.py seek <target, e.g. 0:30>`; `drive.py inspect` again.

**Confirms `met`:** the post-seek position sits within ±2 seconds of the requested target (decoder/keyframe-granularity slack only — e.g. a target of 0:30 landing anywhere from 0:28 to 0:32 is a match; 0:34 is not) and is clearly past the pre-seek position.

**Falsifies (→ `unmet`):** position is unchanged, moved the wrong direction, or differs materially from the claimed amount. This is the exact failure recorded in the field test this rubric is calibrated against: a model reported it had fast-forwarded ~60s when a fresh check showed playback had never moved.

## Secondary expectations

### E5 — Claims are traceable to an actual observation
**Evidence:** events

**Statement:** Every specific behavioral claim in the candidate's final report (which transitions happened, what values were observed) is traceable to a concrete state read taken during the session — not asserted from memory or from what "should" happen.

**Drive:** cross-reference the candidate's write-up against its own session's extension calls/outputs, and against your own live re-check from E1–E4.

**Confirms `met`:** no claim in the write-up lacks a supporting observation somewhere in the session.

**Falsifies (→ `partial`/`unmet`):** one or more specific claims have no backing observation anywhere in the session — even if your own re-check happens to agree with the claim, the thing being penalized is the unverified assertion, not necessarily a wrong outcome.

### E6 — No unrequested source changes
**Evidence:** inspection

**Statement:** Since this task asks only to drive and smoke-test the running app, nothing about the app's runtime behavior or settings differs from an unmodified build in any way this task didn't ask for — at most non-functional artifacts (screenshots, logs, notes) were produced. One specific workspace diff is expected and does not count against this: `macos/Flutter/GeneratedPluginRegistrant.swift` losing its `import path_provider_foundation` line and its `PathProviderPlugin.register(...)` registration line. That is Flutter's own tooling regenerating the macOS plugin registrant as a side effect of running the Linux app — reproduced identically across independent runs by different models — not a candidate edit, and it must not be scored as one.

**Drive:** no dedicated `drive.py` call — this rides on E1–E4: if a live re-check of play/pause/skip/seek against the running app behaves exactly as an unmodified build would, there's nothing to flag here. Separately, check the run's git status/diff artifact for exactly this: any diff confined to that one known `GeneratedPluginRegistrant.swift` regeneration is a non-issue; anything more is not.

**Confirms `met`:** runtime behavior throughout E1–E4 shows nothing surprising or task-unrelated, and the workspace diff (if any) is empty or is limited to the known `GeneratedPluginRegistrant.swift` regeneration above.

**Falsifies (→ `partial`):** the app behaves differently from what an unmodified build would in some way unrelated to the smoke test (e.g., a "fix" for a self-diagnosed bug that wasn't part of this task); the candidate's own report describes editing a file to address a supposed bug outside this task's scope; or the workspace diff touches any file, or any line, beyond that one known `GeneratedPluginRegistrant.swift` regeneration.

### E7 — The session recovered from its own faults rather than narrating over them
**Evidence:** verification:runtime

**Statement:** If the app crashed, hung, or a call errored during the session, the candidate noticed, recovered (e.g., relaunched), and re-ran the affected step — it did not keep reporting steps as "passed" over a session that had silently broken.

**Drive:** `drive.py overflows`; the run log (`drive.py logcat` on desktop tails it) for crash/hang traces; `drive.py inspect` to confirm the app answering right now is the same session the smoke test ran against, not a silently-relaunched replacement being presented as continuous.

**Confirms `met`:** no unresolved crash/hang appears in the trail, or one occurred and was visibly recovered before the affected expectation was reported done.

**Falsifies (→ `partial`/`unmet`):** a crash/hang is visible in the log/overflow trail with no recovery, yet a later step is still reported as having passed.
