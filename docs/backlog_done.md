# Backlog — Closed

Items moved here when fixed. Append-only trail for regression context and
extraction-just-in-case. See [`backlog.md`](backlog.md) for open items and
the shared conventions.

Each closed entry preserves its original H2 (`## B-0NN (severity): title`)
and body, plus a `**Closed**: YYYY-MM-DD — summary` line at the bottom.

## Pre-existing closed items (ui-revamp arc, 2026-05-22 and earlier)

`B-001` through `B-006` and `B-009` were closed during the `ui-revamp` arc
and merged into `main` as commit `4fb5d27` (v3.0.0+40). Their detailed
entries lived in the arc's `bugs.md`, which was deleted at merge time. The
short tags below are sufficient for "have we seen this before?" lookups; if
you need the full original write-up, `git show 4fb5d27~1:bugs.md` (or walk
the `ui-revamp` branch's history) recovers it.

- **B-001** — smart-roots showed the full filesystem.
- **B-002** — gesture-nav overlapped chrome at the bottom edge.
- **B-003** — 54 px immersive transition overflow stripe.
- **B-004** — settings entry-point `·` glyph was too small to hit.
- **B-005** — launch hint was once-only (now shows on every cold launch
  and fades after 3 s).
- **B-006** — background-mode hijacked the screen on first run.
- **B-009** — search scope was limited to `currentPath` instead of the
  whole library.

**Closed**: 2026-05-22 — shipped together in merge `4fb5d27`.
