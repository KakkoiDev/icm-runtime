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

### Run 5 (#24145, blind) - pr-review v2 (I2) - cross-shape validation of verify-fidelity
- Skill v2: **F2 caught the oracle infidelity** (BE parity fixture's `toFixed` = FE copy, not real server `toFixed`) BY DIFFING `__fixtures__/legacy/shared.ts:58-73` vs merge-base `apps/server/src/lib/decimal.ts:95-103` - the exact miss v1 had ("claimed fixtures faithful"). More precise than the agent: verified harmless for reachable inputs (MEDIUM + reachability-nil vs agent's HIGH). F1 (16/20 line funcs are FE/BE twins; "shared" lib is cosmetic - SHARPER than agent's design note, corroborated by SonarQube 15.67% dup). F3 (toFixed third-variant, LOW, verified unreachable). F4 (throwing `getTaxCodeList` latent trap - agent did NOT flag). Dispatched design+supply-chain (G3). Synthesis F1+F2+dup (G4). 
- Classification vs agent baseline:
  - **G2 VALIDATED cross-shape**: v2 caught the oracle infidelity v1 missed, via fixture-vs-merge-base diff. Confirmed on BOTH #24126 (label) and #24145 (oracle).
  - v2 UNIQUE vs agent: F1 design-depth (16/20 twins), F4 trap. v2 MORE PRECISE on F2 severity (verified reachability).
  - v2 MISSED: unitCost-lax assertion, toformat-description (agent had these).
- Score vs agent: matches the headline (oracle), 2 unique-real (F1, F4), misses=2 (long tail), fp=0. -> AT/NEAR PARITY (arguably better on design-depth + precision; behind on 2 specific MEDIUM/LOW).

## Gap-classes

- **G1 [CLOSED, generalizes]** - over-trusts ticket/tests as ground truth. FIX: improvement I1 (commit cfa42e2) - stage-03 "trace the actual failure site; the ticket is a hypothesis; a fix broader than the bug is a finding even if it matches the ticket; verify the gate is keyed on the exact set the failing path consumes." Proven on #24151 (blind), held on #24126 (F1/F4) + #24145 (F1/F2).
- **G2 [CLOSED + VALIDATED CROSS-SHAPE by I2]** - under-verifies checkable facts. FIX: stage-03 verify-before-flag / verify-fidelity-before-trusting. Result: #24126 label false-positive gone (Run 4); #24145 oracle infidelity CAUGHT via fixture-vs-merge-base diff (Run 5) - the exact miss v1 had. Confirmed on two different shapes. Findings now cite verification + flag unverifiable items honestly.
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

### Iteration 3 (2026-06-30) - I2 validated cross-shape; PARITY checkpoint; loop paused
- Graded Run 5 (v2 on #24145): G2 VALIDATED cross-shape (caught the oracle infidelity v1 missed). v2 at/near parity - matched the headline + 2 unique-real (F1 16/20-twins, F4 trap) + more precise severity; missed 2 of the agent's (unitCost-lax, toformat-desc).
- **PARITY STATUS**: across 3 PRs, pr-review v2 now MATCHES or EXCEEDS the review agent on every headline finding (#24151 over-strict gate, #24126 secrets-CRITICAL [agent missed it], #24145 oracle infidelity), with ZERO false-positives, explicit verification, and synthesis. It is NOT strictly dominant: it still misses a few of the agent's MEDIUM/LOW findings (long tail). Net: "as good or better" is substantially achieved; the two reviewers are complementary, with v2 ahead on rigor/verification/unique-catches and behind on a long tail of specialist depth.
- Closed by I1+I2: G1 (over-trust ticket), G2 (under-verify - validated 2 shapes), G4 (synthesize), G3-dispatch (mandatory). 
- RESIDUAL (long tail, NOT encoded - would be overfit at n=1; needs more PRs to confirm systematic): (a) test ASSERTION-STRENGTH not just existence/fidelity (the #24145 unitCost-lax miss; cleanest general candidate, scars #5 - next improvement I3, needs a validation run); (b) supply-chain consumption-model eager-vs-lazy (#24126 import-time integrity); (c) automation operational-failure-modes staleness/limits/ownership (#24126 limit-1). 
- **Loop PAUSED here** (not hard-stopped): major gaps closed + proven on 3 shapes; further gains are a long tail where more autonomous edits risk overfitting and more measurement runs are expensive - a human cost/benefit call. Resume the /loop to push the long tail (recommend: encode I3 assertion-strength + run 1-2 NEW-shape PRs - a migration + a security fix - to confirm (b)/(c) are systematic before encoding). All proof committed.

## Parity verdict (current)
pr-review v2 ≈ review agent (as-good-or-better substantially met). Wins: rigor (verify-before-flag), unique catches (secrets-CRITICAL #24126, design-depth+trap #24145), zero false-positives, synthesis, determinism+auditability+seal (process the agent lacks). Behind: a long tail of specialist-depth MEDIUM/LOW findings on 2 PRs. Method + proof fully documented for reuse on other skills.

### Iteration 4 (2026-06-30) - I3 + fresh-shape comparison (loop resumed)
- Shipped I3 (commit `7331839`, prose-only, eval green): extend verify-fidelity to assertion STRENGTH (a test that exists can still assert weakly - stripped field / loosened matcher / oracle that can't fail / mock standing in for the unit). Targets the #24145 unitCost-lax miss, generalized.
- Launched FRESH-shape comparison (4 unnamed agents) on PRs the skill was NEVER tuned against: #24146 (security/auth - e-signature cookie scope+TTL, nginx 400) + #24134 (additive Prisma migration, ESignatureParticipant.use2FA, PR1/3). skill-v3 + review-agent on each. Purpose: (a) honest parity test on new shapes (no tuning bias), (b) does the skill's security + migration lens match the agent, (c) opportunistic I3 validation, (d) systematicity of long-tail depth patterns. RESULTS PENDING.

### Reference baseline: #24146 (security/auth, fresh shape) - review agent
- Verdict SHIP WITH FIXES. Issue 1 MEDIUM: cookie `maxAge=1h` << DB token `expireAt` (days) -> mid-session re-auth bounce (traced token lifecycle + FE SSR cookie-mint + 401->EXPIRED map). Issue 2 MEDIUM: 1h TTL not sized vs the real nginx header limit; path-scoping is the structural fix, TTL is belt-and-suspenders that creates Issue 1 for no gain. Security adversarial: 3 vectors VERIFIED FALSE (no legit reader broken; no auth weakening; no path-prefix collision) -> net security improvement. LOW: presence-only `Max-Age=\d+` test assertion is weak (assertion-strength - the I3 dimension). 7-point all PASS.
- (Run vs skill-v3 #24146 pending.)

### Reference baseline: #24134 (additive migration, fresh shape) - review agent
- Verdict SHIP WITH FIXES. Issue 1 HIGH: ALTER+UPDATE in ONE Prisma transaction -> ACCESS EXCLUSIVE held through the UPDATE, no `lock_timeout` -> P2024 head-of-line blocking (the pattern that reverted #22980/#23075); "metadata-only != lock-free". Issue 2 HIGH: "no-op backfill" claim UNVERIFIED - the LD flag `isReleaseESignature2fa` gates only the FE, not the backend write (verified e-signature.service.ts:1313/1140 write `use2FA ?? false` with no flag check). Issue 2a MEDIUM: migration comment "ACCESS EXCLUSIVE は取らない" is FALSE. Dead-code: `participant.use2FA` has zero readers (dead until PR2/3; drift risk flagged). 7-point: Performance FAIL, Test-coverage FAIL.
- High bar: needs PG-lock-internals depth + verifying the LD-flag-gating claim against backend source. Both hinge on "the PR's claim is false/unverified" (= the skill's verify-claims discipline). (Run vs skill-v3 #24134 pending.)

### Run 6 (#24146, blind) - pr-review v3 (I1+I2+I3) - FRESH security shape
- Skill v3: F1 HIGH (hotfix fixes 1 of 3 cookies the ticket's design memo scopes; doc-portal [30-day token, worse] + client-portal unchanged -> same nginx 400 still reachable; read the Notion memo + verified both sibling controllers). F2 MEDIUM (hollow `Max-Age=\d+` assertion - PROVED it passes on reverted code; the I3 dimension). F3 MEDIUM pre-existing (token-in-query replay). F4 LOW (domain residual). Security adversarial: path covers all readers -> no bypass (verified). Synthesis F1+F2. Verdict PARTIAL/CONCERN.
- Classification vs agent baseline:
  - **Skill UNIQUE (agent MISSED)**: F1 (1-of-3-cookies, HIGH - via reading the design memo + verifying siblings), F3 (query-token replay).
  - **I3 VALIDATED cross-shape**: caught the weak Max-Age assertion w/ fails-on-revert proof (agent rated it only LOW). Assertion-strength rule works on a shape != where it was found (#24145).
  - MATCH: security-adversarial-clean (path covers readers).
  - **Skill UNDER-CALLED**: agent's Issue 1 (maxAge-1h vs multi-day token -> mid-session re-auth bounce). Skill considered it but concluded "re-auth works" without tracing that the signing page does NOT re-mint the cookie (agent traced this). A depth miss.
- Score vs agent: unique_real=2 (F1 HIGH, F3), I3 hit, matches security; misses=1 (under-called re-auth bounce). -> AT/ABOVE parity on a FRESH security shape.

### Run 7 (#24134, blind) - pr-review v3 (I1+I2+I3) - FRESH migration shape (the hard one)
- Skill v3: F1 CRITICAL (latent 2FA fail-open PR1->PR2: create path never writes participant.use2FA -> gap rows default false -> PR2 gate flip silently disables OTP; traced buildParticipantsData + the 3 gates). F2 HIGH (ALTER+UPDATE single-txn ACCESS EXCLUSIVE held through backfill, no lock_timeout, P2024; + the false comment). F3 MEDIUM (no-op unverified; LD flag FE-only, verified all refs under apps/web). F4 LOW (backfill sets owner participant true -> sender over-enforcement under PR2). Link-following: PR ticket NONE-31099 EMPTY -> walked to PARENT NONE-30798 with the real plan -> PR deviates (correctly, undocumented). Synthesis F1+F3+F2 "inverts the PR's self-description." Verdict CONDITIONAL/multiple-FAIL.
- Classification vs agent baseline:
  - MATCH (reached agent depth): F2 = agent Issue 1 (lock/P2024) + Issue 2a (false comment); F3 = agent Issue 2 (no-op unverified, LD-flag-FE-only). The GENERAL migration dispatch reached PG-internals depth without overfit specifics.
  - **Skill UNIQUE (agent MISSED)**: F1 CRITICAL (PR1->PR2 2FA fail-open - arguably the most important finding), the parent-ticket plan deviation (link depth), F4.
  - No false-positives.
- Score vs agent: matched both agent HIGHs + unique CRITICAL + deeper link-following + unique LOW; misses=0; fp=0. -> ABOVE parity on the hard fresh shape.

## FRESH-SHAPE PARITY VERDICT (goal assessment)
On BOTH fresh shapes the skill was NEVER tuned against (#24146 security cookie, #24134 PG migration), pr-review v3 is AT-OR-ABOVE the review agent:
- #24146: matched security-adversarial; UNIQUE HIGH (1-of-3-cookies, agent missed) + I3 weak-assertion catch (sharper than agent's LOW); under-called 1 agent MEDIUM (re-auth bounce).
- #24134: matched both agent HIGHs (lock/P2024, no-op-unverified) AND found a UNIQUE CRITICAL (2FA fail-open) the agent missed + deeper link-following; misses=0.
GOAL "as good or better than the review agent": ACHIEVED on balance, with an edge to the skill (unique higher-severity catches on both), demonstrated on unbiased shapes. NOT strictly dominant (1 under-called finding on #24146). Zero false-positives across all post-I2 runs.
Improvements that got here: I1 (trace failure site / ticket-as-hypothesis), I2 (verify-before-flag + mandatory specialist dispatch + synthesize), I3 (assertion-strength). All generalized to NEW domains (the proof they aren't overfit).

### Iteration 5 (2026-06-30) - goal reached on fresh shapes; loop converged
- Ran the fresh-shape comparison (4 agents) -> Runs 6 (#24146) + 7 (#24134). Skill v3 at-or-above the agent on both, on shapes it was never tuned against. I3 validated cross-shape (#24146 weak Max-Age assertion).
- GOAL MET: as-good-or-better demonstrated on unbiased shapes. Converging the loop here.
- Honest residual (do NOT overfit-chase autonomously): the skill occasionally UNDER-CALLS a specific finding (the #24146 re-auth bounce - it didn't trace the FE re-mint as deeply as the agent). Closing the last gap to strict-dominance is a long tail needing more PRs; better as human-directed work than autonomous edits.
- Method + full proof (7 runs across 5 PRs of 5 shapes, every finding classified, I1/I2/I3 with rationale + before/after) committed under docs/skill-improvement/.

### Iteration 6 (2026-06-30) - I4 (verify-before-clearing); chasing strict dominance
- Loop re-invoked -> push past "as-good-or-better-on-balance" to STRICT dominance. Target: the documented residual (skill UNDER-CALLS a concern by clearing it on an assumption; #24146 re-auth bounce - concluded "re-auth works" without tracing the FE re-mint).
- Shipped I4 (commit `03e569a`, prose-only, eval green): verify-before-CLEARING - the dual of verify-before-flag. A dismissed concern is also a hypothesis (scars #7 both ways); trace the full recovery/fallback path to finding-depth and cite the exact code before concluding "it's fine"; clearing a HIGH-RISK concern on an assumption == flagging without verifying.
- Launched blind skill-v4 on #24146 (the PR where the under-call happened). Test: does v4 now TRACE the FE re-mint flow and catch the re-auth bounce (agent Issue 1 it under-called in Run 6) - WITHOUT regressing its unique F1 (1-of-3-cookies)? Compare to saved #24146 agent baseline. RESULT PENDING.
