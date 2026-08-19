# Nothingness Evaluator changelog

## 1.7.2 — 2026-08-19

Campaign start no longer races the desktop entrypoint against a slow `docker cp`. The entrypoint keeps retrying Xvfb/Pulse until SIGTERM instead of exiting at 30s; waiters fail fast when the container dies and copy `/run/nothingness/logs` on failure. Fixture seeding streams `git archive` into the container (tar pipe) and runs git init / `pub get` / primed baseline inside it, dropping the host-side checkout and `.git` copy. Preflight no longer re-runs `flutter precache` or a temp-dir `pub get` that prepare and the offline gate already proved. Baseline containers keep `--rm` off so failures leave logs. Ops only; scores remain comparable with 1.7.1.

## 1.7.1 — 2026-08-19

`watch-eval.py` now shows the actual run phase (`PREPARING`, `RUNNING`, `AWAITING JUDGE`, `SCORING`) instead of labeling every unscored row `RETRYING`. Last activity follows the newer of candidate progress and judge artifacts, Live GUI stays up through scoring, and a non-TTY invocation prints one snapshot. A campaign also reserves one noVNC host port at `campaign.py new`, so every task and retry of that campaign binds the same `127.0.0.1` URL; refresh the tab between tasks. Display/ops only; scores remain comparable with 1.7.0.

## 1.7.0 — 2026-08-19

The evaluator image is now Debian bookworm-slim with a pinned Linux-only Flutter SDK (3.47.0), pinned Node/uv/apt snapshots, and no Android or browser toolchain. noVNC is unchanged. Runtime baseline now launches through the same `/run/nothingness` home and drive paths as a real candidate, and the image ships `xdg-user-dirs` so Linux `path_provider` can resolve documents. Scores under 1.7.0 are not directly comparable with earlier campaigns if a candidate depended on floating `stable` behavior.

## 1.6.1 — 2026-08-15

Intentional repeat campaigns are now supported with `campaign.py new --allow-repeat`, preserving the default duplicate-campaign guard while allowing model variability measurements on the same harness and suite.

## 1.6.0 — 2026-08-15

Orchestrator metadata is now a required campaign artifact. Every campaign records the orchestrator name and uses `N/A` when its cost is not available; Pi-backed harnesses can use the new helper to discover parent and matching subagent usage before regenerating the leaderboard.

## 1.5.1 — 2026-08-14

Retry records now capture zero spend for failures that never reached an admission call, so campaign cost remains a number when the harness knows no provider work occurred.

## 1.5.0 — 2026-08-14

The current protocol has one campaign per model triple, one accepted run per task, and at most two fresh task retries. Active terminology no longer uses historical multi-sample labels. Failed retries record only a minimal reason and cost, are not published, and exhaust the whole campaign after the second retry. Campaign spend includes retry spend while accepted-task cost does not; dashboards and reports expose both values separately.

The version of the **harness**, not of the app under test. It is the single
source of truth: `common.eval_version()` parses the topmost `## <version>`
heading below, records it into every run at prepare time, and the index table
shows it per run. There is no separate `VERSION` file to drift out of sync, and
a version bump is impossible without an entry here.

Bump when a change could move a score or change what a number means — rubric
semantics, scoring bands, evidence rules, isolation, what the candidate is
given. A typo fix or a clearer error message does not need a bump.
Results published under different versions are not directly comparable; say so
rather than averaging them.

## 1.4.0 — 2026-08-11

Judge-brief only; no rubric, band, or candidate-facing change. Bumped anyway
because two of these facts prevented false `unmet` verdicts against working
implementations, so a judge that has them can score the same trial differently
from one that does not. Scores under 1.4.0 remain comparable with 1.3.0 for
the candidate's own behaviour, but a 1.3.0 result may carry a verdict a
better-equipped judge would not have reached.

Two reporting fixes, display-only — no score, band, or stored artifact changes:

- **`assisted` is shown per task again.** It has always been a per-task boolean
  in every `result.json`, and `scoring.md` requires it beside the outcome rather
  than inside it — "an assisted pass is reported as `pass` **and**
  `assisted: true`, never laundered into a plain pass". But neither `report.py`
  nor `leaderboard.py` read the field. `report.py` instead summed a *different*
  field, `intervention_count`, across the whole run into one word in the header,
  so an assisted task rendered in the table as a bare `pass` with its 0.05
  penalty already folded silently into `adjusted`. Both now carry an `Assisted`
  column, read from each task's own field.
- **`report.py --write` no longer destroys prose.** It rebuilt the README from
  scratch and overwrote unconditionally, so regenerating a run to refresh its
  numbers silently deleted every filled `<!-- judge: ... -->` section. It now
  reads the existing README back and keeps the intro, interventions and
  surprises prose, reporting what it preserved. It takes the *last* match of a
  section heading, because an embedded `notes.md` can carry the same heading —
  two of the three existing runs do.

All of the below were found by judges during the gpt-5.4-nano medium campaign
of 2026-08-11 and are recorded in `references/judge-brief.md`.

- **`seek` is a no-op while paused.** It acks with the requested `positionMs`
  while the reported position does not move. Two of seven judges hit it; one
  nearly failed a correct swipe-to-seek implementation, because a paused seek
  reading unchanged is indistinguishable from a gesture that redraws but never
  seeks. The single highest-value line added.
- **Absence-of-affordance reads need `isPlaying`/`songInfo` in the same
  bundle.** One judge's "affordance absent" probe was really a fixture track
  that had ended mid-probe.
- **`observe`'s `elapsed_seconds` tracks the last event, not wall clock.** It
  freezes during a hung candidate tool call — 323s reported when ~11 minutes
  had passed. Documented for now; the number itself is still wrong.
- **`publish` resolves its destination from the invoked script's repo root, not
  cwd**, so a judge running the top-level script from its sandbox publishes
  into the shared results tree. Two judges did exactly that in one campaign.
  Documented for now; the one-writer invariant is still unenforced.
- **A key on the `GestureDetector` does not rescue `dragByKey`.** The previous
  wording explained the no-op via the missing `includeSelf` ancestor walk,
  which implied a better-placed key would work. It does not.
- **Sliders are reachable after all** — not by synthetic pointers, but by XTEST
  wheel plus a real click. The old blanket "cannot be activated at all" was
  costing coverage.
- Also: `SoLoudInvalidParameterException` on clamped seeks is pre-existing;
  `settings open` returns before the sheet paints and `shoot` catches the prior
  frame; `getSemantics` is the better default lens and needs its full
  `ext.nothingness.` name; `setQueue` starts playback itself; `playTrackByPath`
  does not sync `currentIndex`; `decide_flags` can include a zero-length events
  batch; `judge_control_unavailable` from `finish` means already-terminated;
  concrete XTEST geometry and a long-metadata staging recipe.

## 1.3.0 — 2026-08-10

Scores under 1.3.0 are not comparable with 1.2.x: t7's prompt was reworded,
t5's budget changed, and a class of run that previously produced no data point
now produces a scored one.

- **A candidate that runs long is scoreable.** Three runs across two campaigns
  were lost outright: the candidate reached its deadline, never entered
  `awaiting_judge`, and `classify-run.py` refuses to score a timed-out run, so
  real work became nothing. Two guards now sit behind the judge. `observe`
  finishes the run itself at 90% of budget, and the in-container supervisor
  terminalizes at 97% with a `deadline_guard:` reason that `classify-run.py`
  accepts as valid. Neither can produce a `pass` — that still requires the
  candidate to reach `awaiting_judge` on its own. Losing the run was biasing the
  leaderboard against slower models rather than losing data at random.
- **`observe` is a poll, not a wait.** It defaulted `--timeout-seconds` to the
  whole candidate budget and treated its own expiry as a failure, so it could
  never return inside a caller's tool-call limit: it had to be backgrounded, the
  judge's turn ended, and nothing read its output or acted on the deadline.
  Judges were not being careless; the tool required it. Now 120s, returning
  normally with `still_running` and the candidate's elapsed/budget.
- **A real gesture primitive.** `dragStart`/`dragUpdate`/`dragEnd` hold a drag
  open across separate VM-service calls, so frames render between them and a
  driver can capture a genuine mid-gesture instant. `dragByKey` ran start,
  every update and end inside one synchronous call, which made the during-gesture
  evidence t4 asks for impossible with documented tooling.
- **`setShuffle`** exposes the same `shuffleQueue`/`disableShuffle` the settings
  toggle calls. Shuffle was previously reachable only by tapping through the
  settings sheet, and `setQueue` can only ever turn it *on*.
- **t7's prompt said "one navigation transition"**, which reads naturally as
  folder navigation — and `navigateVoid` never touches `PlaybackController`, so a
  candidate could satisfy the wording while the playing track never moved. The
  rubric always meant next/prev, so candidates were being penalised for our
  ambiguity, not for gaming. Reworded to say track transition explicitly.
- **t5 gets 2700s**, up from 1800s. It asks for more app-driving than any other
  task in the suite.
- The runtime gate's cold-start budget went from 30s to 120s: it failed under
  load with `runtime_state_timeout:ready` and passed on retry with nothing
  changed. And `drive.py` no longer defaults to the `android` target when
  nothing indicates one, which made `preflight` stall ~30s probing adb on a
  Linux-only host.
- The skills no longer assume a particular agent harness — no literal tool
  timeouts, no named monitor facility — and reach `.agents/skills` directly
  rather than through the `.claude` symlink.

## 1.2.1 — 2026-08-10

Found by running 1.2.0 as a shakedown with judges on a different model, told
to report defects rather than work around them. Every item below was a silent
failure: nothing errored, the numbers just meant less than they appeared to.

- **Screenshot deliverables were never published.** `collect.py` gathers
  untracked workspace files with `git ls-files --others --exclude-standard`,
  which by design skips gitignored paths — and `.tmp/` is gitignored while
  `.tmp/agent_shots/` is exactly where the driving skill tells candidates to
  write `drive.py shoot` output. `artifacts/workspace-untracked/` came back
  empty on a run whose screenshots demonstrably existed in the container. Every
  task with a screenshot expectation was affected. That directory is now copied
  explicitly (not by un-excluding ignores, which would drag in `build/` and
  `.dart_tool/`), and the count lands in `collect.json` as `agent_shots`.
- **`flutter_log_copied` read false for a genuine launch.** Only
  `/run/nothingness/drive/flutter_run.log` and `/tmp/flutter_run.log` were
  checked, but `drive.py preflight` recommends a `DRIVE_SESSION_TAG` launch
  writing `/tmp/flutter_run_<tag>.log`. A candidate that followed the printed
  recipe produced a real 37KB log and still looked, in the artifacts, like it
  had never started the app. Falls back to the newest `/tmp/flutter_run*.log`.
- **The docs promised widget-tree paging the fixture does not have.**
  `skipLines=`/`maxChars=` exist at harness HEAD and are silently ignored at the
  pinned fixture, which takes only `depth` and truncates at 128k from the top.
  Same HEAD-versus-fixture drift as the drag keys in 1.2.0 — the third instance,
  and the reason both skills now carry a standing warning to verify against the
  fixture commit.
- **The watchdog cried wolf twice.** It reported an empty campaign as finished
  (it derived "done" from the run list, empty until the first trial registers),
  and it flagged a judge as unattended after `judge_finish`, when the candidate
  is `completed`, nothing is burning budget, and the judge is simply writing its
  scorecard. It also re-announced every 30s because it deduped on message text
  carrying a live minute count.

Known and unfixed: the runtime gate failed once and passed twice on identical
inputs. Not reproduced; the failure reason was lost.

## 1.2.0 — 2026-08-10

Scores under 1.2.0 are not comparable with 1.1.0 and earlier: the candidate is
now told things it previously had to guess, and two of the first campaign's
seven tasks were lost to exactly that guessing.

- **Candidates are told where the fixtures are.** Every task declared
  `media.container_path`, and no script read it — the candidate received only
  `task["prompt"]`. In the first campaign t1 and t7 both hunted `.tmp` and the
  repo, never looked in `/opt`, and failed on that alone; t1's whole prompt was
  nine words. `launch-candidate.py` now composes an environment preamble from
  the task's own `media` and `limits` fields, and records the prompt actually
  sent in `launch.json`. Tasks declaring neither are unchanged.
- **Candidates are told their time budget**, in the same preamble. A run killed
  at the deadline cannot be scored at all, and the model that hit the wall had
  no way to see it coming. This reduces how often that happens; it does not fix
  the underlying gap (below).
- **One frozen judge brief**, `references/judge-brief.md`, passed verbatim to
  every judge. Previously the manager learned the environment as it went and fed
  each lesson to the *next* judge, so the last judge of a campaign knew ten
  things the first did not. Uneven within a model; across models it silently
  breaks the comparison, since the same task would be judged better-informed for
  whichever model ran second.
- **A watchdog for the one failure that does not self-heal.** `watchdog.py`
  reports a candidate stuck in `awaiting_judge`, a run near its deadline, and a
  container still up with no judge observation for ten minutes — a judge that
  ended its turn mid-trial, which happened once and was caught only because a
  human looked. Armed as a `Monitor` when the campaign is created.
- **Corrected the drag guidance, which described harness HEAD rather than the
  pinned fixture.** `hero-gesture-surface` does not exist at the fixture commit
  and the subtree walk runs without `includeSelf`, so the documented anchor could
  never resolve; `kind=touch` compounds it by returning a success payload while
  moving nothing, which is how one candidate convinced itself a gesture worked.
  Both skills and the t4 rubric now point at real X11 input via XTEST, which also
  makes a genuine mid-gesture capture possible — the t4 rubric previously asserted
  it was not. Rubric prose only; expectation tiers, evidence kinds and lenses are
  unchanged, though the rubric hash moves. No score is invalidated: t4's only
  result is `unassigned`.

- **Judges are told to finish a candidate before its deadline rather than let it
  be killed.** t4 of the first campaign was lost as `unassigned` — a
  fully-evidenced `partial`, 45% of the campaign's spend, no data point — and
  that was a procedure miss, not a harness limit. `finish` has no phase guard:
  called mid-turn it completes the run with `timed_out: false` and a
  `judge_finish:` reason, which classifies normally. Finishing outside
  `awaiting_judge` only forecloses `pass`, which a candidate that never finished
  should not get anyway. The watchdog's 90%-of-budget warning now says to do
  exactly this.

## 1.1.0 — 2026-08-10

- The judge owns its trial end to end (start, observe, score, publish, tear
  down). The manager stands each judge up, unblocks it, and aggregates.
- Fixed the judge sandbox, which could never have worked: `RUNS_ROOT` derived
  from the repository root, so a judge in a worktree looked for its run under a
  path nothing creates.
- `campaign.py next` drives the per-task loop from campaign state instead of a
  numbered list in prose; interrupted campaigns resume exactly.
- Published results are named `<model>-<thinking>-<YYYYMMDD>-<HHMM>`, timed from
  the campaign's start. Same-day repeats previously either refused to publish or
  silently overwrote the earlier run.
- Both zero-credential gates record what they proved against the image id,
  fixture commit and their own code, and skip when all three are unchanged —
  about ten minutes of unchanged re-verification per campaign, now about a
  second. `--force` re-verifies.
- The runtime gate reports the container's state, exit code and OOM flag when
  the desktop never comes up, instead of a bare timeout that read the same
  whether the container was slow or dead.
- Deleted `consolidate.py`. There is no multi-trial aggregation, no pass-rate
  cohort, and no variance or confidence interval: a run is one run, repeats are
  separate rows, and comparing them is a human call.
- The index tracks who conducted each run and what that cost — agent sessions
  outside the measured containers, invisible to the harness, and far larger than
  the candidate spend.

## 1.0.0 — 2026-08-10

Harness state for the first published campaign (`gpt-5.4-nano` medium, seven
tasks, one trial each), at commit `fab6bd2`. Versioning did not exist when that
campaign ran, so its results carry `"eval_version": "1.0.0"` with
`"eval_version_backfilled": true` — the number is assigned from the commit that
produced it, not stamped live like every run since.

- Expectations-bundle scoring: per-task rubrics with `required`/`secondary`
  tiers, hashed into each result; bands 0–3 derived from the scorecard, never
  asserted by the judge.
- Per-expectation evidence binding, contiguous event coverage, genuine-capture
  checks, and a hard cap of three recorded interventions.
- Isolated candidate: pinned image, clean fixture at `5fc7e04`, internal Docker
  network with an exact-host egress proxy, credentials over stdin only.
- Two zero-credential gates: offline build baseline and live runtime baseline.
