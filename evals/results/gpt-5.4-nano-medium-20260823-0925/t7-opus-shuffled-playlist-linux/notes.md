# Judge notes — t7-opus-shuffled-playlist-linux

Run: `t1-t7-gpt-5.4-nano-medium-t7-opus-shuffled-playlist-linux-run-ea25b93c2a6b`
Model: azure-openai-responses / gpt-5.4-nano / medium. Outcome: **pass (3)**. Interventions: 0.

The candidate launched the Linux build, called `setQueue` with the ten mounted fixtures, tapped the
on-screen shuffle toggle, played, and issued one `next`, then reported before=01-undercover-49 /
after=04-undercover-52. I settled every expectation by driving the same live app myself rather than
trusting that write-up.

## E1 — queue is exactly the ten fixtures, each once (met)
My runtime inspect (`verification-03f60...`) shows `queueLength` 10 with the exact ten fixture paths
under `/opt/nothingness/media`, each appearing once — no duplicates, nothing missing, nothing foreign.
All entries `isNotFound:false`.

## E2 — shuffle enabled through the real control (met)
I re-drove the actual on-screen toggle: opened settings and tapped `void-settings-status-shuffle`,
watching `shuffle` flip true→false→true across three inspects. It is genuinely driven by the control,
not a side-channel. `verification-773f9d3d...` captures the restored `shuffle:true`.

## E3 — playing a valid, in-set track before the transition (met)
Runtime inspect showed `isPlaying:true` on `04-undercover-52.opus` (an in-set fixture) with
`isNotFound:false` (`verification-03f60...`). Playback was genuinely advancing on its own (I watched
the current index auto-increment as tracks ended).

## E4 — exactly one transition, result still in-set and valid (met)
I performed one live `next`: index 6 (`09-undercover-46.opus`) → index 7 (`07-undercover-44.opus`).
The index genuinely changed, the post-track is one of the ten fixtures and `isNotFound:false`, and
playback stayed active (`verification-9cd9aa45...`).

## E5 — no foreign media anywhere (met)
Scanning every media path across the session's own setQueue/play/next/inspect events, the only paths
that appear are the ten fixtures. The single non-fixture reference is `media/manifest.json`, which the
candidate read to enumerate the set — it never entered the queue or became current.

## E6 — claims traceable to observations (met)
Each specific claim in the report (queue of 10, `shuffle:true`, before=01-undercover-49,
after=04-undercover-52) maps to a concrete inspect in the session's event stream: the captured inspects
show index 4 = 01-undercover-49 then, after `next`, index 5 = 04-undercover-52.

## E7 — no unrequested source changes (met)
The inspection observation's git `status` and `diff_stat` are both empty — not even the known
`GeneratedPluginRegistrant.swift` regeneration this rubric tolerates. Runtime behavior across E1–E4
matched an unmodified build.

## E8 — recovered from its own faults (met)
`drive.py overflows` returned zero reports and the run log holds no crash/hang traces — only benign
ALSA "no sound card" config noise from the headless container. The same session answered every one of
my live probes and was still playing, so nothing was narrated over a silently-broken app.
