# SLOC — Lines of Code by Top-Level Folder

Counts **git-tracked** files only (via `git ls-files`), so build output,
`.dart_tool/`, `.venv/`, and anything in `.gitignore` is excluded.

> Snapshot taken **2026-05-30** at commit `b107792`.

## All tracked files

| Folder             |    Lines | Files |
| ------------------ | -------: | ----: |
| `_archive`         |   42,071 |    49 |
| `lib`              |   15,859 |    70 |
| `test`             |    8,911 |    50 |
| `docs`             |    3,614 |    17 |
| `assets`           |    2,682 |     6 |
| `macos`            |    1,758 |    30 |
| `android`          |    1,686 |    36 |
| `.claude`          |    1,521 |     9 |
| `(root files)`     |      514 |    13 |
| `linux`            |      469 |    10 |
| `tool`             |      461 |     8 |
| `integration_test` |      324 |     2 |
| `.github`          |      309 |     4 |
| `.vscode`          |       36 |     2 |
| **TOTAL**          | **80,215** | **306** |

Notes:
- `_archive` is legacy/retired code and dominates the raw total.
- `assets` lines come from data files (e.g. SVG/JSON), not source.

## Dart source only (excludes `_archive`)

This is the more meaningful view of the active app + tests.

| Folder             |    Lines | Files |
| ------------------ | -------: | ----: |
| `lib`              |   15,859 |    70 |
| `test`             |    8,814 |    49 |
| `integration_test` |      324 |     2 |
| **TOTAL**          | **24,997** | **121** |

## Shipping app code (`lib` + platform projects)

`lib` plus the per-platform host projects, excluding tests and tooling.

| Folder    |    Lines | Files |
| --------- | -------: | ----: |
| `lib`     |   15,859 |    70 |
| `macos`   |    1,758 |    30 |
| `android` |    1,686 |    36 |
| `linux`   |      469 |    10 |
| **TOTAL** | **19,772** | **146** |

## How to regenerate

A reusable script lives at [`tool/sloc.sh`](tool/sloc.sh):

```bash
tool/sloc.sh            # all tracked files, grouped by top-level path
tool/sloc.sh --dart     # only .dart source files (excludes _archive)
tool/sloc.sh --app      # shipping app code: lib + macos + android + linux
```

The script `cd`s to the repo root, lists tracked files with `git ls-files`,
sums `wc -l` per top-level folder, and prints a table sorted by line count.
After a notable change, rerun it and update the tables and the snapshot
date/commit above.
