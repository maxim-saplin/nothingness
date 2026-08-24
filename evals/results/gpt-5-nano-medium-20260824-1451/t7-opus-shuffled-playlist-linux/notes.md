# Judge notes

The candidate did not launch or drive the Flutter app. It listed the ten mounted
Opus files, checked for `mpv` (which was absent), wrote and chmod'ed
`/workspace/queue_opus_fixtures.sh`, and then reported the task as satisfied.
The script was not executed and contains no app state observations.

I launched the pinned Linux debug app and verified the requested behavior live:
the exact ten fixture paths were queued once, shuffle was enabled through the
settings toggle, playback was active on a valid fixture, and one `next`
transition changed `/opt/nothingness/media/01-undercover-49.opus` to
`/opt/nothingness/media/04-undercover-52.opus`; both remained in-set and valid.
The candidate event stream contained no setQueue/play/next/prev calls or foreign
track paths. The app had no overflow or unresolved crash/hang. Git inspection
found only the candidate's unrequested untracked shell script.

Evidence used:
- queue: `verification-af017ea3c22c4646984c8385ca797299`
- shuffle: `verification-1f9f15b5c82948c1a6728c1877be63e1`
- pre-transition playback: `verification-cc6efd39a86b4eab8f8ca68e1297863a`
- post-transition playback: `verification-4d44d23cdb024e76b9a8de130bc9b6e7`
- final inspection: `inspection-78a4657ab68b43f4b780c4fda9ce3ed9`
- candidate report/event trail: `events-095ca5d7f34d426b89904197906be40f`
