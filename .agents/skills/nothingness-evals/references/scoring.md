# Scoring

The judge never asserts an outcome or a score directly. It writes one verdict per expectation in the task's rubric — a **scorecard** — and `classify-run.py --scorecard <path>` computes everything else deterministically. This is the full contract in `evals/README.md` § Scoring rubric.

## Expectations bundle

Every task ships `evals/tasks/rubrics/<task-id>.md`: an ordered list of expectations, each with an id, a prose statement settled by driving the real app (never by reading a diff or a widget key), a tier, and an evidence-kind declaration:

- **`required`** — the core ask. Any `unmet` required expectation caps the run at score 2 (`partial`); it can never be a `pass`.
- **`secondary`** — polish, evidence quality, not breaking adjacent behavior.

Each expectation also declares, in a `**Evidence:**` line alongside its `**Statement:** / **Drive:** / **Confirms** / **Falsifies**` structure, which `judge-observations.jsonl` `kind` may settle it: `verification` (drove the live app and looked — screenshot/tree/semantics/settings/runtime, via `judge-verify.py`), `inspection` (git/workspace/process state, via `judge-inspect.py` — legitimate only for expectations that are genuinely about the workspace, e.g. "no unrequested source changes"), or `events` (the candidate's own session event trail, via `judge-events.py` — legitimate only for expectations about whether the candidate's *own claims* are traceable to *its own* observations, never as a substitute for the judge looking at the app). Absent a declaration, an expectation defaults to `verification`: fail closed toward requiring eyes. Nearly every expectation across both rubrics is `verification`; `inspection`/`events` are the deliberate, narrow exceptions.

`verification` may carry an optional lens qualifier naming exactly one of `judge-verify.py`'s five captures — `**Evidence:** verification:screenshot` — for the rare expectation that is meaningless without that one specific capture (e.g. T2/E5, whose entire statement is that a screenshot exists and is legible; a runtime-only capture cannot settle it no matter how genuine). Unqualified `verification` keeps meaning "any one genuine capture", which stays correct for expectations several lenses can settle together (e.g. T2/E1, whose own prose treats the tree dump and the screenshot as interchangeable proof).

Per-expectation binding is enforced, not aggregate: each scorecard entry's `evidence_ref` must resolve to an observation of *exactly* the kind (and, where declared, the exact lens) its own expectation requires — pointing every expectation at one unrelated `inspection` or `events` observation is rejected, naming the offending expectation; so is citing a `verification` observation whose only genuine capture isn't the lens that expectation actually needs. This check runs per scorecard entry against what that entry itself cites — it is not satisfied by some other, genuinely-captured observation being cited elsewhere for the aggregate "did the judge look at all" gate (below). `judge-verify.py` inspects capture payloads for known "nothing to show" sentinels (e.g. `getSemantics` returning `"semantics not available"` with exit 0) rather than trusting return codes, so a capture that technically succeeded but recorded nothing is marked unavailable with a reason, not silently counted as a look at the app.

The rubric's hash is **frozen at `prepare-run.py` time**, before the candidate ever sees the prompt — recorded in `run.json["rubric_contract"]`, exactly mirroring how `task_contract.manifest_sha256` freezes the task manifest. A task with no rubric yet fails preparation outright: a task that cannot be scored must not be launched. `classify-run.py` compares the rubric file's *current* hash against this frozen value (catching drift after prepare), and separately compares the scorecard's own self-declared `rubric_sha256` against the same frozen value (not against a hash it recomputes from disk at scoring time) — recomputing and comparing only against the scorecard's own declaration would be circular, since both are written by the same actor at the same time. `rubric_id`/`rubric_sha256` land in `result.json` from the frozen contract, so a score stays reproducible against the exact expectations that existed before the run started. `classify-run.py` also rejects a scorecard whose expectation ids/tiers don't match the rubric, or whose declared task doesn't match the run's task.

## Scorecard

One verdict per expectation, each with a one-line justification and an `evidence_ref` pointing at the `judge-observations.jsonl` observation (of the kind, and where declared the lens, that expectation's own rubric entry requires) that supports it: `met` (credit 1.0), `partial` (0.5), `unmet` (0.0). Separately from the per-expectation check above, at least one cited `--observation-id` must be a `judge-verify.py` verification observation with a genuine capture — inspection/event evidence alone can never satisfy that aggregate gate, only settle the specific expectations that legitimately declare them.

```
raw       = Σ(credit) / count                      # over every expectation
penalty   = 0.05 × min(delivered_interventions, 3)  # capped at 3 → max 0.15
adjusted  = clamp(raw − penalty, 0, 1)
```

## Bands

| `adjusted` | Score | Meaning | Outcome |
| --- | --- | --- | --- |
| ≥ 0.85 | **3** | GOOD — clean, verified, evidence matches | `pass` |
| 0.60 – 0.85 | **2** | AVG — works, but nudged or rough | `partial` |
| 0.30 – 0.60 | **1** | BAD — barely; broken or invented behavior | `partial` |
| < 0.30 | **0** | FAIL — didn't do it, or no evidence | `fail` |

Boundaries are left-closed (`score_band` uses `>=`): exactly 0.60 lands in the score-2 band, exactly 0.30 in the score-1 band.

Hard rule: **any unmet `required` expectation caps the score at 2**, regardless of `adjusted` — a run cannot pass while missing the core ask. `validity` stays a separate axis: `unassigned`/`invalid_infrastructure` runs carry no outcome or score at all.

## Assistance

`assisted` is an independent boolean field, never folded into the outcome name — an assisted pass is reported as `pass` **and** `assisted: true`, never laundered into a plain pass. `intervention_count` records exactly how many interventions were delivered. `judge-control.py` enforces a hard cap of 3 delivered interventions per run: a 4th delivery is refused (exit code 6); the judge must terminalize the run instead of continuing to steer. The cap check and the delivery it guards are serialized under an exclusive file lock across the whole read-check-append-write, so the cap holds even under two concurrent `judge-control.py` invocations — no delivery reaches the candidate without also being durably recorded.

## Model identity

`result.json`'s `model_identity_verified` is a real derived fact, not an asserted one, and it is `true` only when two independent pieces of evidence both agree the requested provider/model were actually served: pi's admission probe response (`admission.json["identity_verified"]`, from the `provider`/`model` fields pi's own assistant message carries — confirmed against a real captured transcript) and, separately, the actual candidate session's own transcript (`summary.json["model_identity_verified"]`, derived from every `turn_end` message pi emitted during the real run, via `summarize-run.py`). A mismatch on either is infrastructure-invalid: preflight hard-fails outright on an admission mismatch, and `classify-run.py` refuses to classify a run `valid` if the candidate transcript itself didn't independently confirm it — a session that crashed before completing a single turn is correctly *unverified*, not vacuously verified. This covers `provider` and `model` only. `thinking` is a request-time parameter with no analogous confirmation anywhere in pi's event stream — it is carried through from the request, never independently checked, and is not part of what `identity_verified`/`model_identity_verified` claims.

## Repeated campaigns are separate samples

A model may have multiple campaigns for the same suite. Each campaign still has one accepted run
per task and at most two fresh retries after operational failure. Retries are not samples, are
never averaged, and do not change accepted-task cost. Repeated campaign scores remain separate
published data points; compare them only when their harness version and suite manifest match.

Campaign cost is the actual measured candidate/admission spend for accepted runs plus retries.
Accepted-task cost is measured only from the accepted run for each task. Orchestrator/judge spend
remains separate because it is outside the measured containers.

## Known limitations

These are stated plainly, not to be minimized, and are not being patched — some are inherent to the trust model, some are deliberate scope decisions:

- **The scorecard is the judge's testimony.** All of the machinery above — frozen rubric hashes, per-expectation evidence-kind and lens binding, genuine-capture checks, the intervention lock — catches *mistakes*: a silently-failed capture, a drifted rubric, racing processes, an aggregate check satisfied by evidence a specific verdict never actually cited. None of it constrains a judge that deliberately misreports what it saw — one willing to mark every expectation `met` against a genuine screenshot that doesn't show what it claims defeats any scheme built on top of the judge's own attestation. That is a property of the trust model (the judge authors the scorecard), not a defect to be fixed here.
- `common.exclusive_lock` (used by `judge-control.py`'s intervention cap) guards concurrent invocations correctly under normal use — verified crossing real process boundaries, not just threads within one process. It provides no protection if `interventions.lock` is deleted while held: `flock` locks the open file description, not the pathname, so a deleted-and-recreated lock file would let a new locker in without ever contending with the original holder.
- Nothing verifies that an expectation's declared evidence kind (or lens) matches what its prose genuinely requires. A rubric author who writes a claim that needs a screenshot but declares `**Evidence:** events` will not be caught by any code here — this is inherent to the "never parse prose" principle (principle 3): the statement itself is never mechanically checked against its own declaration.
- **`thinking` is not verified.** `model_identity_verified` (see "Model identity" above) confirms `provider` and `model` from two independent real sources, but pi's event stream never echoes back what reasoning-effort level it actually used for a turn — there is no field analogous to the `provider`/`model` ones on the assistant message. A run's `thinking` is exactly what was requested, carried through unverified; this is a hard limit of what pi's own output exposes, not a gap in the harness's checking.
- Rubric-parser footguns for WP7 to avoid when authoring T3–T7's rubrics:
  - **Duplicate `**Evidence:**` lines in one expectation block silently take the first match** — a second, later declaration is never read or flagged as a conflict.
  - **The parser is not markdown-fence-aware.** An example `**Evidence:**` line written inside a fenced code block or inline-code illustration within an expectation's own text can be matched instead of (or before) the real declaration, since the regex scans the whole block's raw text.
  - **A trailing `##` section after the two expectation sections gets silently absorbed.** Only `## Required expectations` and `## Secondary expectations` are recognized section headers; any other `##` heading placed after them (e.g. a stray "## Notes" at the end of the file) is treated as part of the prior section's body, and any `### ...` sub-heading inside it is parsed as a real, scored expectation.
