---
name: qa-handoff
description: Quality gate protocol between implementation and handoff.
---
# QA Handoff

Use this skill after implementation work and before reporting results to the user. This file is the entrypoint: keep it for overview, routing, and shared invariants, then use the mode docs in `references/` for the actual review flow.

## Do Not Use When
- The task is still mid-implementation.
- You are only exploring or planning and have not produced work to verify yet.
- There is nothing substantive to hand off for review.

## Shared Invariants
- Work is **not** reported to the user until it passes QA or 3 rounds are exhausted.
- Ambiguous verdict (neither clear PASS nor FAIL) counts as FAIL.
- The QA reviewer has **no conversation history**. Reconstruct the needed context in the handoff package.
- When the repo already exposes a runtime harness, CLI driver, seed script, or comparable control surface, the reviewer must gather their **own** runtime evidence instead of trusting implementer-provided status or pasted logs alone.
- Only the user can waive a requirement.
- Before assembling or reviewing evidence, read `references/evidence-taxonomy.md`.
- QA validates deliverable readiness, not only internal correctness.

## Choose the Mode
- Default to `references/default-qa-mode.md`.
- Use `references/two-qa-mode.md` only when the user asks for a stronger gate or when you intentionally want both `qa-1` and `qa-2`.
- In two-QA mode, both reviewers must PASS on the same round before handoff.