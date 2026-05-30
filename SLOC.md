# SLOC — Lines of Code by Top-Level Folder

Counts **git-tracked** files only (via `git ls-files`), so build output,
`.dart_tool/`, `.venv/`, and anything in `.gitignore` is excluded.

> Snapshot taken **2026-05-31** on branch `redesign/clean-room`.

## Shipping app code (`tool/sloc.sh --app`)

`lib` plus the per-platform host projects, excluding tests and tooling.

| Folder    |    Lines | Files |
| --------- | -------: | ----: |
| `lib`     |   10,697 |    61 |
| `macos`   |    1,758 |    30 |
| `android` |    1,630 |    35 |
| `linux`   |      469 |    10 |
| **TOTAL** | **14,554** | **136** |

**−26.4% from the 19,772 baseline.** Achieved with all features preserved,
all 346 tests green, and `flutter analyze` clean. The reduction came from:
deleting dead code; relocating the debug/automation harness out of shipping
`lib/` into `dev/` (behind a thin `lib/debug_hooks.dart` seam — proper test/prod
boundary); migrating every `StatefulWidget` to `flutter_hooks`; replacing the
`GlobalKey<State>` imperative antipatterns with reactive controllers
(`HeroFlashController`, `VoidBrowserController`); cutting redundant comments; and
**clean-room rewriting each large/medium file against its tests** (~13–18%
denser per file by discarding accumulated defensive cruft).

The platform total (`macos`+`android`+`linux` = 3,857) is almost entirely
generated/native/binary-icon scaffolding (a fresh `flutter create` yields a
comparable size) and is effectively a floor; `android` carries ~1,000 lines of
real custom Kotlin (AudioCaptureService, MediaSessionService, MainActivity).

## All tracked files

| Folder             |    Lines | Files |
| ------------------ | -------: | ----: |
| `_archive`         |   42,071 |    49 |
| `lib`              |   10,697 |    61 |
| `test`             |    8,948 |    50 |
| `docs`             |    4,504 |    18 |
| `assets`           |    2,682 |     6 |
| `macos`            |    1,758 |    30 |
| `android`          |    1,630 |    35 |
| `.claude`          |    1,521 |     9 |
| `dev`              |    1,320 |     7 |
| `(root files)`     |      583 |    14 |
| `tool`             |      508 |     9 |
| `linux`            |      469 |    10 |
| `integration_test` |      326 |     2 |
| `.github`          |      309 |     4 |
| `.vscode`          |       36 |     2 |
| **TOTAL**          | **77,362** | **306** |

Notes:
- `_archive` is legacy/retired code and dominates the raw total.
- `dev/` is the debug/automation harness + integration-test entrypoint, moved
  out of `lib/` (not shipped; release-stripped).

## How to regenerate

```bash
tool/sloc.sh            # all tracked files, grouped by top-level path
tool/sloc.sh --dart     # only .dart source files (excludes _archive)
tool/sloc.sh --app      # shipping app code: lib + macos + android + linux
```

After a notable change, rerun and update the tables and the snapshot date above.
