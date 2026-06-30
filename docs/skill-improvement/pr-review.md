# pr-review improvement log

Skill: `kakkoidev/pr-review`. Reference agent: `review` (`~/dotfiles/claude-profiles/main/agents/review.md`). Method: `README.md`.

Goal: pr-review as good or better than the review agent, proven on real PRs.

## Reference baselines (review agent, fixed reference - real findings)

### meetsmore/meetsone#24151 - validation bug (taxCode)
- HIGH: gate keyed on `isAvailable` is stricter than the bug; FE crash uses the full registered master, so `"002"`/`"004"` wrongly rejected. (VERIFIED real.)
- MEDIUM: N+1 - available set re-fetched per bulk row.
- LOW: defensive `String(taxCode).slice(0,64)`.
- Verdict: merge-with-decision.

### meetsmore/meetsone#24126 - CI/automation chore (zengin auto-update)
- HIGH-1: Dependabot may not raise the date-prerelease bump (detection buggy for non-standard prerelease tags); the whole notify chain is downstream of a bump that may never fire.
- MEDIUM: `open-pull-requests-limit:1` -> review latency == data staleness.
- MEDIUM: import-time supply-chain integrity (consumer builds bank list at module load; a bad bump parses at boot).
- LOW: PR-title -> Slack mrkdwn injection. LOW: any-actor trigger. Latent: same-dir Dependabot collision.
- Verified the `zengin-code` label EXISTS (`gh label list`). Verdict: SHIP WITH FIXES.
- NOTE: the agent did NOT flag the GH-Actions-secrets-under-dependabot-actor issue (the skill's F1) - a possible agent MISS (contested, see below).

### meetsmore/meetsone#24145 - large refactor (extract @proone/lib-accounting)
- HIGH: server `toFixed` non-finite -> `"0"` behavior delta vs AC "identical"; AND the parity ORACLE `__fixtures__/legacy/shared.ts#toFixed` is a copy of the FE toFixed, not the BE source -> 185 green tests validate the change against the WRONG reference. (The connected finding.)
- MEDIUM: parity divergence-classifier strips `unitCost` (lax assertion).
- LOW: `toformat` PR-description wrong (already a dep of both apps on master, not new/FE-only). + design review, external-rule (tax rate pre-existing).
- Verdict: SHIP WITH FIXES.

## Runs

### Run 0 (#24151) - pr-review v0 (before stage-03 fix)
- Skill: SHIP WITH FIXES; F1 N+1 MEDIUM, F2 defensive LOW; traceability PASS.
- Classification: MATCH N+1, MATCH defensive; **SKILL-MISSED the HIGH over-strict gate** (rated traceability PASS - trusted the Notion ticket's stated rule).
- Score: misses=1 (the HIGH), fp=0, unique_real=0. -> Below the agent.

### Run 1 (#24151, blind) - pr-review v1 (after improvement I1, commit cfa42e2)
- Blind sub-agent following improved stage-03, not told the answer -> independently produced the HIGH (over-strict gate, 002 AND 004), traceability FAIL, flagged tests-lock-behavior. VERIFIED against source (validate.ts createYupTaxCode = full master; 004 defaultIsAvailable:false).
- Score: misses=0, fp=0, unique_real>=0 (caught 004 too). -> Closed the gap on #24151.

### Run 2 (#24126) - pr-review v1
- Skill: F1 CRITICAL (Slack notify dead - Actions secrets unavailable under dependabot[bot] actor; agent MISSED this), F2/F3/F4/F5.
- Classification: SKILL-UNIQUE F1 (CONTESTED - needs verifying that a dependabot-applied-label `labeled` event runs in the secrets-restricted context). MATCH bump-may-not-fire (skill F4 = agent HIGH-1), any-actor trigger. **SKILL-FALSE-POSITIVE F3** ("label may not exist" - agent verified it DOES via gh label list). **SKILL-MISSED**: injection, import-time integrity (agent's specialists).
- Score: misses=2 (injection, integrity), fp=1 (F3), unique_real=1 if F1 verified. -> Mixed; below agent on breadth + 1 false-positive.

### Run 3 (#24145) - pr-review v1
- Skill: F1 toFixed non-finite delta (MEDIUM), F2 parity binds decimal.js-only/Prisma-engine-not-tested (MEDIUM), F3 postinstall LOW. Traced old code at merge-base; dispatched 2 sub-reviews; verified external tax-constant scope.
- Classification: MATCH the toFixed delta. **SHALLOWER**: agent connected delta -> "oracle is the FE copy, validates wrong reference"; skill CLAIMED "fixtures faithful" and **missed the one infidel fixture** (SKILL-MISSED + a fidelity false-claim). **SKILL-MISSED**: unitCost lax assertion, toformat description error. 
- Score: misses>=2, fp=0, depth < agent (didn't connect). -> Below agent (solid but not as deep).

## Gap-classes

- **G1 [CLOSED, generalizes]** - over-trusts ticket/tests as ground truth. FIX: improvement I1 (commit cfa42e2) - stage-03 "trace the actual failure site; the ticket is a hypothesis; a fix broader than the bug is a finding even if it matches the ticket; verify the gate is keyed on the exact set the failing path consumes." Proven on #24151 (blind), held on #24126 (F1/F4) + #24145 (F1/F2).
- **G2 [OPEN]** - under-verifies checkable facts. Flags hypotheses without the cheap check (label existence #24126 F3 false-pos; fixture fidelity #24145 false-claim). The agent runs `gh`/`grep`/diffs the actual artifact.
- **G3 [OPEN]** - inconsistent specialist breadth/dispatch. Missed injection+supply-chain (#24126), unitCost+toformat (#24145); dispatched specialists on #24145 but not #24126.
- **G4 [OPEN, harder]** - atomized findings; doesn't synthesize/connect (the agent's #24145 delta+wrong-oracle = one finding).

## Improvements

- **I1** (commit `cfa42e2`) - closes G1. Stage-03 failure-site discipline. PROVEN (Run 1 blind catch, verified).
- **I2** (this iteration) - targets G2 + G3 (see iteration log below).

## Contested (flagged per scars #7, not scored until verified)
- #24126 F1 (secrets-under-dependabot-actor): skill says CRITICAL, agent silent. Verify GitHub's behavior for a dependabot-applied-label `labeled` event.
- #24145 oracle fidelity: skill said "fixtures faithful", agent said `shared.ts#toFixed` is the FE copy. Direct contradiction; verify by diffing the fixture vs master BE/FE `decimal.ts`. (Either way reinforces G2.)

## Iteration log
- (below, appended each loop iteration)
