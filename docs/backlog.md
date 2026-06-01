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

The next id to assign is **B-051** — check `backlog_done.md` before reusing any
number.

## B-049 (minor): native-first audio load is unverified on the API 37 emulator

**Symptom** — no user-facing bug; a test-coverage / design-decision gap to revisit.

**Repro** — `SoLoudTransport._openSource` (3.8.0+61) tries `loadFile(path)` first
and falls back to a MediaStore content-URI byte read (`readAndroidAudioBytes` →
`loadMem`) only when raw-path access fails. On the **API 37 (Android 17) x86_64
emulator**, scoped storage *always* blocks raw shared-storage paths, so the
emulator only ever exercises the content-URI **fallback** (confirmed working —
25/25 corner-case harness, real position advance). The native `loadFile` success
branch — the fast path that benefits real devices where raw paths work — has **no
live coverage on this host**.

**Desired** — verify the native fast path end-to-end (and that it's measurably
faster than 3.7.0's content-URI-always path) on a surface where raw paths work: a
real device, or a lower-API / All-files-access emulator. Then decide the
long-term design: keep native-first-then-fallback, or move to an **fd-based**
content-URI load (`loadFile("/proc/self/fd/N")` via
`ContentResolver.openFileDescriptor`) that avoids both the raw-path attempt and
the full-file byte marshal uniformly (note: flutter_soloud 4.0.6 `loadMem` takes
bytes only — no fd/streaming — so an fd path needs fd lifecycle management).

**Notes** — `lib/services/soloud_transport.dart` (`_openSource`),
`lib/services/android_audio_source.dart`; memory `android-api37-fileexists-preflight`.
Shipped in **3.8.0+61** (commit `5861650`).

**Area** — transport
