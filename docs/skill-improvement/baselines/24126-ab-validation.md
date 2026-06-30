# A/B cold validation - #24126 @ 93035c789fc5 (iteration 11)

Workflow `wf_4ce67f14-501` (5 agents, ~238k tokens). Tests whether the restructured
pipeline (C0-C5, L1-L3) is load-bearing vs the pre-improvement pipeline, on the commit
the improvement was actually derived from.

## Setup
The PR pivoted on 2026-06-30 (commit `5432f2a0` "drop custom slack workflow") - current
merged HEAD no longer contains the reviewed mechanism. Pinned the review to `93035c789fc5`
(last pre-pivot commit): diff = 116 lines, 3 config/workflow files including
`notify-zengin-code-pr.yml` (`on: pull_request: types: [labeled]`, `secrets.SLACK_ACCESS_TOKEN`).
Ran `gather-runtime-evidence` with the new pinned-diff arg against that commit.

Both arms: same pinned diff + same worktree, K=2 blind passes. Only difference:
- **ARM A (new pipeline)**: also given `runtime-evidence.md` + the mechanism-trace mandate (trace trigger->condition->step->effect, verify each link against a real actor instance, verify-before-clearing, status tags).
- **ARM B (pre-improvement)**: diff only, old prose ("review for security/correctness, check traceability").

## Two load-bearing facts (ground truth)
1. **Does the `labeled` trigger fire?** YES - Dependabot applies the `zengin-code` label as a discrete op (real instance: Dependabot PR **#24217**, `labeled by dependabot[bot] [label=zengin-code]`).
2. **The Slack token**: `SLACK_ACCESS_TOKEN` is absent from the repo Actions store (siblings `OBSERVABILITY_SLACK_TOKEN`/`PR_REVIEWER_SLACK_TOKEN` exist) and the Dependabot store; a Dependabot-context run reads only the (empty) Dependabot store -> auth fails. (Caveat: `/actions/secrets` does not list org/env secrets, so "absent from repo store" is strong, not absolute.)

## Result (grader, knowing ground truth)
| | trigger_fires | token_issue | false positives |
|---|---|---|---|
| **ARM A** (new) | **grounded** (cites #24217 + store inventory) | **grounded** | **0** |
| **ARM B** (old) | **asserted + WRONG** (hypothesized "may not fire") | **asserted** (never store-checked) | **2** |

`a_beats_b: true`, `fails_on_revert: true`. ARM A grounded both facts and was worse on
neither; ARM B only hypothesized from docs, tilted the trigger the wrong way (the real
#24217 timeline refutes "may not fire"), never queried a store, and carried 2 clean FPs
(claimed `/mobile` is a dead dependabot dir - it exists; the "trigger may not fire" finding).

## Honest caveats (do not oversell)
- **ARM B still flagged the token CRITICAL/HIGH.** It did NOT miss the bug - both arms
  would BLOCK this PR. The measured improvement is **grounding + trigger-direction
  correctness + precision (0 vs 2 FPs)**, NOT a flipped missed-CRITICAL. The original
  doc's "missed the trigger question" described a *degraded single static-only pass*; this
  K=2 old-pipeline proxy engaged the trigger (wrongly) and caught the token (ungrounded),
  so it is a fair-but-stronger ARM B than the original failing run.
- **n=1 shape.** This validates on the CI/config shape the weakness was found on.
  Generalization to a second shape (migration/webhook/cron) is NOT yet done - no
  cross-shape claim until it is (per the README validate-across-shapes guardrail).
- The grader is an LLM judge; its grounded/asserted calls are reasoned and cite specifics
  but are judgment, not a deterministic check.

## Conclusion
On #24126, the runtime-evidence stage + mechanism-trace mandate are load-bearing: they
convert doctrinally-asserted, partly-wrong, FP-bearing findings into instance-backed,
store-backed, zero-FP grounded ones. fails-on-revert holds for *grounding and accuracy*.
The "catches a CRITICAL the old pipeline misses" claim is NOT demonstrated here (both block).
