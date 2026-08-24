# T7 — Opus shuffled playlist (Linux) — judge notes

Run: `t1-t7-gpt-5.4-nano-low-t7-opus-shuffled-playlist-linux-run-55c1b5ef00aa`
Model: azure-openai-responses / gpt-5.4-nano / low. Candidate settled at `awaiting_judge`
after ~268s, no interventions, exit 0. I verified every expectation by driving the same live
Linux build myself (the candidate's app isolate was still up), not by trusting its write-up.

**What the candidate did.** It queued the ten immutable Opus fixtures with one
`ext.nothingness.setQueue` call (`queued:10, startIndex:0`), opened the settings sheet, tapped the
`void-settings-status-shuffle` row to enable shuffle, played, read state, then advanced with one
`ext.nothingness.next`. Its final report states before=`01-undercover-49.opus` (idx 8) and
after=`09-undercover-46.opus` (idx 9), shuffle true, queue of 10.

**E1 (met).** My live `drive.py inspect` reports `queueLength:10`, and the ten queued paths are
exactly the ten fixtures under `/opt/nothingness/media`, each once — no duplicates, none missing,
nothing foreign. (verification `inventory`)

**E2 (met).** I exercised the real control myself: with the settings sheet open I tapped
`void-settings-status-shuffle` and inspect flipped `shuffle` true→false, tapped again and it went
false→true. The flag genuinely tracks the on-screen toggle, not a side channel. (verification
`shuffle_on`)

**E3 (met).** Before my transition the app was actually playing (`isPlaying:true`) currentIndex 8 =
`01-undercover-49.opus`, an in-set fixture with `isNotFound:false`. (verification `transition_before`)

**E4 (met).** A single `drive.py next` moved currentIndex 8→9, i.e.
`01-undercover-49.opus` → `09-undercover-46.opus`; the resulting track is in-set with
`isNotFound:false` and the index genuinely changed — a real transition, not a no-op. (I first
confirmed the mechanic separately with a prev that took 9→8.) (verification `transition_after`)

**E5 (met).** Every queued path and every current-track path in the candidate's own
setQueue/play/next getPlaybackState reads is one of the ten fixtures; a session-wide grep for
`.opus` returned zero paths outside `/opt/nothingness/media`. (events)

**E6 (met).** Each specific claim in the report (10-file queue, shuffle on, one next transition,
before/after track paths and indices) traces to a concrete getPlaybackState observation in the
session record; nothing is asserted from memory. (events)

**E7 (met).** Runtime behavior matched an unmodified build throughout E1–E4, and the workspace git
status and diff are empty — not even the tolerated `GeneratedPluginRegistrant.swift` regeneration
appeared. (inspection git/processes)

**E8 (met).** `drive.py overflows` reports count 0 and the runtime lens shows no crash/hang trace;
the same live isolate answered continuously, so nothing was silently relaunched and narrated over.
(verification runtime, overflows)

**Verdict.** All eight expectations met — a clean pass. The candidate correctly queued exactly the
ten fixtures once, enabled shuffle through the real control, played a valid in-set track, and
advanced by exactly one transition that stayed within the fixture set.
