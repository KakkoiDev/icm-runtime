# A/B cold validation - #23852 @ aeb0b883c8db (iteration 11, shape 2)

Workflow `wf_31ca7688-4dd` (5 agents, ~272k tokens). Second shape, to test whether the
improvement generalizes beyond shape-1's mechanism or is overfit to it.

## Setup
#23852 (TS-12949 "Build prod operation images nightly instead of on push"): removes the
`push: [release, release-TG]` trigger from `deploy-operation.yml` and adds PROD/TG_PROD to
the nightly `cron: '0 18 * * *'` schedule matrix. Mechanism = **cron schedule** (not shape-1's
dependabot-label trigger). Single merged commit, not pivoted; worktree pinned at the commit.
runtime-evidence (live) generalized as designed: the tool's value shifted from a dependabot
timeline to **workflow run history** - 10 consecutive successful nightly `event=schedule` runs.

Same A/B as shape 1: same diff + worktree both arms; ARM A also gets runtime-evidence +
mechanism-trace mandate, ARM B is the pre-improvement pipeline. K=2 each, blind.

## Result (grader, skeptic-primed)
| | schedule fires | hotfix latency | false positives |
|---|---|---|---|
| **ARM A** (new) | **grounded** | **grounded** | **0** |
| **ARM B** (old) | **asserted** | **grounded** | **0** |

`a_beats_b: true`, **`margin: narrow`**. Both arms ground the hotfix-latency tradeoff (it is
visible in the diff). The entire gap is Fact 1: ARM A's best pass grounds "the schedule fires"
in the run history AND lands the subtle catch - run-level `conclusion=success` does NOT prove a
fresh PROD image was built, because the "check if image already exists" dedup step can skip the
prod legs, and PROD was only newly added to the schedule matrix by this PR. ARM B cites the same
greens and treats them as validating the new prod path (even spelling out "succeeded OR were
skipped" without realizing "skipped" undercuts its conclusion) - asserted, not grounded.

## Honest caveats (load-bearing, do not bury)
- **Narrow, not a blowout.** B surfaced the schedule, the latency, and a prod-environment-gate
  hypothesis; A simply grounded the one place B asserted. The improvement's value here is
  grounding + a subtle verification-gap catch, NOT a missed-CRITICAL.
- **The win is the second pass carrying the arm.** ARM A pass 1 reached the right gap via a
  FACTUALLY WRONG argument ("the 10 runs predate the change" - false, they post-date the merge),
  hedged PLAUSIBLE; pass 2 fixed both the dates and the reasoning using the same evidence. So a
  single new-pipeline pass still errs - the **mandatory ensemble (C5/L3) is what makes ARM A
  reliable**, by self-refuting the bad pass. This validates the C5 decision; it also means
  "new pipeline" without the ensemble is not trustworthy on its own.
- **The grader's generalization speculation is wrong, and shape 1 refutes it.** The shape-2
  grader guessed a CI-secret shape would generalize WEAKER ("evidence exposes only secret names,
  not values"). But shape 1 WAS a secret shape and was the STRONGER win - because the graded fact
  was secret *existence/location* (name-level), exactly what the tool exposes. Name-level is
  enough when the fact is "does this secret resolve in this store."
- **Both shapes are CI/workflow.** The runtime-evidence TOOL is CI-specific by design
  (workflows/actors/secrets/run-history). A NON-CI shape (migration / app feature-flag) where the
  tool is silent and only the prose levers apply is STILL UNTESTED this iteration. Expect A approx
  B there (the new tool adds nothing; the prose levers were already validated in I1-I5). So the
  claim is "generalizes across CI-mechanism shapes," not "across all shapes."

## Bonus: the REAL skill ran end-to-end (more faithful than the A/B harness)
During the shape-2 workflow, a sub-agent ran the actual `pr-review` skill via `icm.sh init` on
#23852 and got through stages 01-03, producing a real `ac-execution-trace.md`
(`baselines/23852-skill-ac-execution-trace.md`). It is high quality: all four PR mechanism claims
traced `trigger->condition->step->effect`, M2 grounded in the 10/10 nightly runs, and it
independently reached the SAME M3 ECR-dedup-skip insight ARM A pass 2 caught. So the new stage's
prose produces grounded mechanism analysis in the real pipeline, not only in the file-fed harness.
(The run stopped at 04-review and was cleaned up - see the gate note below.)

## Gate-hook observation (real, worth a follow-up)
The orphaned skill run (open at 04-review/05-verify with no `findings.md`) caused its
`tools="Write"` gate to DENY *every* Write tool call in the session, including unrelated doc
writes - the gate-hook gates by TOOL, not by whether the write belongs to the run. Caller-scoping
fixed parent/child cross-talk but not "an orphaned/incomplete run blocks an unrelated agent's
writes." FIXED in `62462af`: the hook + pi adapter forward the tool's target path and `check_run`
scopes a write-gate to writes into that run's own tree (path-less activity gates keep global scope).
Regression test gate.test.sh case 5/5b/5c/5d, fails-on-revert verified, suite 150/0.

## Conclusion (shapes 1 + 2)
The runtime-evidence + mechanism-trace improvement beats the pre-improvement pipeline on BOTH CI
shapes: decisively on shape 1 (hidden secret-store fact), narrowly on shape 2 (visible cron change,
where only run-history grounding + a dedup verification-gap separate them). Consistent value =
grounding + catching verification gaps; NOT consistently miss->catch. Reliability of the new
pipeline depends on the mandatory ensemble (a single pass errored on shape 2). Cross-shape claim
is limited to CI mechanisms; non-CI generalization untested.
