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

### Run 4 (#24126, blind) - pr-review v2 (after improvement I2, commit bc4e65c)
- Skill v2: F1 HIGH (secrets-unreachable, now VERIFIED: `gh api dependabot/secrets`->0, `git show origin/master:.github/dependabot.yml`->no labels key, docs fetched), F2 MEDIUM (PR-title->Slack injection - NEW catch), F3 MEDIUM (#24127 test is human-actor, verified author=mofiky-mm - the rigged-test finding). "Verified-and-cleared" section: label EXISTS (no false-positive), bot's 4-space nit FALSE, paths correct. Synthesis: F1+F3 = "silently inert feature whose only test is rigged." Verdict BLOCK.
- Classification vs agent baseline + v1:
  - **G2 CLOSED**: v1's F3 false-positive ("label may not exist") GONE -> v2 verified+cleared it. All findings cite verification; honestly flagged the one unverifiable item.
  - **G3 PARTIAL**: v2 NOW caught the injection (F2) v1 missed / agent caught (mandatory dispatch worked). STILL MISSED agent's import-time-integrity, limit-1 staleness, dir-collision (specialist ran but shallow).
  - **G4 APPLIED**: synthesized the connected F1+F3 conclusion.
- Score vs agent: misses~3 (down from ~2 + a false-positive + no-synthesis), fp=0 (was 1), unique_real=1 (F1, verified harder), synthesis=yes. Much closer to parity; residual gap = specialist DEPTH, not dispatch.

## Gap-classes

- **G1 [CLOSED, generalizes]** - over-trusts ticket/tests as ground truth. FIX: improvement I1 (commit cfa42e2) - stage-03 "trace the actual failure site; the ticket is a hypothesis; a fix broader than the bug is a finding even if it matches the ticket; verify the gate is keyed on the exact set the failing path consumes." Proven on #24151 (blind), held on #24126 (F1/F4) + #24145 (F1/F2).
- **G2 [CLOSED by I2, measured #24126 Run 4]** - under-verifies checkable facts. FIX: stage-03 verify-before-flag / verify-fidelity-before-trusting. Result: the #24126 label false-positive is gone (verified+cleared); findings cite verification. Cross-shape validation on #24145 pending (does verify-fidelity catch the FE-copy oracle it claimed-faithful?).
- **G3 [PARTIAL after I2]** - specialist breadth. Mandatory dispatch (I2) made v2 catch the injection it missed before. RESIDUAL: specialist DEPTH - v2 still missed import-time-integrity, limit-1 staleness, dir-collision (agent's supply-chain/config lens reasoned deeper). Next: enrich the lens prompts with generalizable risk patterns (consumption model eager-vs-lazy; operational failure modes: staleness/limits/ownership; latent config collisions) WITHOUT overfitting - validate on another shape first.
- **G4 [APPLIED by I2, held #24126]** - synthesize connected findings. v2 produced the F1+F3 synthesis. Watch it holds on other shapes.

## Improvements

- **I1** (commit `cfa42e2`) - closes G1. Stage-03 failure-site discipline. PROVEN (Run 1 blind catch, verified).
- **I2** (this iteration) - targets G2 + G3 (see iteration log below).

## Contested (flagged per scars #7, not scored until verified)
- #24126 F1 (secrets-under-dependabot-actor): skill says CRITICAL, agent silent. Verify GitHub's behavior for a dependabot-applied-label `labeled` event.
- #24145 oracle fidelity: skill said "fixtures faithful", agent said `shared.ts#toFixed` is the FE copy. Direct contradiction; verify by diffing the fixture vs master BE/FE `decimal.ts`. (Either way reinforces G2.)

## Iteration log

### Iteration 1 (2026-06-30) - I2 shipped, measurement launched
- Set up `docs/skill-improvement/` (method README + this log). Committed `202a00b`.
- Shipped improvement I2 (commit `bc4e65c`, prose-only, structure eval green): stage-03 gains (G2) verify-checkable-facts-before-flagging + verify-fidelity-before-trusting; (G3) MANDATORY specialist dispatch by changed-file bucket with the bucket->specialist map; (G4) a synthesize-connections step.
- Launched blind skill-v2 measurement run on #24126 (the PR where G2's F3 false-positive + G3's missed injection/supply-chain appeared). Tests: does v2 now (a) verify the label exists instead of flagging "may not exist", (b) dispatch insecure-defaults+supply-chain and catch the injection + import-time integrity the agent caught? Compare to the saved #24126 agent baseline. RESULT PENDING (wakes the loop on completion).
- Open after this: if I2 closes G2/G3 on #24126, re-verify on a different shape (#24145 - did it stop claiming fidelity / catch the oracle infidelity?); then settle the 2 contested findings; then assess parity.

### Iteration 2 (2026-06-30) - I2 measured on #24126, cross-shape validation launched
- Graded Run 4 (v2 on #24126): G2 CLOSED (false-positive gone, verification throughout), G3 PARTIAL (caught injection via dispatch; still missed import-time-integrity / limit-1 / dir-collision = specialist DEPTH gap), G4 APPLIED (F1+F3 synthesis). Much closer to parity; residual = specialist depth.
- Launched blind skill-v2 run on #24145 (the refactor) to validate I2's verify-fidelity cross-shape: does v2 now diff the parity oracle and catch that `shared.ts#toFixed` is the FE copy (the infidelity v1 missed while claiming "fixtures faithful")? Compare to saved #24145 agent baseline. RESULT PENDING.
- Decision held: do NOT pile on a G3-depth edit yet - validate I2 on #24145 first (avoid overfitting to #24126), THEN decide whether to enrich specialist lenses.
