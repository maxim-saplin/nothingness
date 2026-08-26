E1 — I reset the live queue with the ten mounted Opus paths and verified a ten-item, fixture-only runtime queue with every entry resolvable.

E2 — I opened settings, used the visible shuffle control to turn shuffle off and back on, then verified `shuffle: true` in the live runtime capture.

E3 — Before my navigation check, the app was playing `01-undercover-49.opus`; it was in the fixture queue and not marked not-found.

E4 — My single live `next` changed index/path from `8`/`01-undercover-49.opus` to `9`/`05-undercover-53.opus`; the destination remained a resolvable fixture.

E5 — The candidate event chain records fixture-only queueing, playback, and navigation; I found no foreign queue or current-media path.

E6 — The candidate's final before/after, shuffle, queue, and next claims match its recorded state read and my live re-check.

E7 — Inspection found an empty workspace status and no diff; the app behavior I drove was the normal fixture playback flow.

E8 — The candidate retried parsing/control errors and completed a successful final sequence; final runtime was responsive with no overflow reports.
