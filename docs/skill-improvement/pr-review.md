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

### Run 8 (#24146, blind) - pr-review v4 (I1+I2+I3+I4) - validate verify-before-clearing
- Skill v4: F6 CLEARED-as-defect but FULLY TRACED the recovery path (cookie minted only by SSR auth/index.page.tsx:38-65; participant page does NOT re-mint; mid-flow 401 -> EXPIRED screen; recovery = re-click email link; no lockout) = the agent's Issue 1 depth, the Run-6 under-call NOW CLOSED. Also CLEARED F2 (path reaches all readers - depth-2 reader census) + F3 (PDF on separate CDN) WITH cited evidence = verify-before-clearing on the positive side. UNIQUE: F1 (1h cookie doesn't bound the credential - server token 30d regardless; sharper than agent TTL note), F4 (dead expireAt field). MATCH: F5 (hollow Max-Age assertion, I3). Synthesis F1+F5.
- Classification:
  - **I4 GOAL MET**: re-auth-bounce under-call from Run 6 is GONE - v4 traced the full re-mint/recovery path to agent depth and cited it. verify-before-clearing also produced evidence-backed CLEARS (F2/F3).
  - vs agent: v4 unique F1 (sharper) + F4; matched I3 (F5); matched the re-auth trace (cleared-as-product-note vs agent's MEDIUM - same substance, different label).
  - **REGRESSION vs v3 (run-variance)**: v4 did NOT re-flag the "1-of-3-cookies" HIGH v3 caught - cleared the siblings as "deferred" without verifying a follow-up ticket tracks them (an I4-adherence miss on a deferral-clear + run-variance).
- Score vs agent: per-run AT/ABOVE (unique F1/F4, matched re-auth trace + I3); the v3-unique HIGH didn't recur.

## TERMINAL FINDING: the ceiling is run-variance, not a prose gap
Across 8 runs / 5 PRs / 5 shapes, improvements I1-I4 closed every IDENTIFIED gap-class (over-trust ticket, under-verify flags, specialist dispatch, synthesize, assertion-strength, verify-before-clearing). Result: pr-review per-run MATCHES-OR-EXCEEDS the review agent, with unique catches and zero false-positives. BUT the skill - like the agent itself - catches a DIFFERENT SUBSET of findings each run (v3 caught 1-of-3-cookies; v4 caught credential-not-bounded + the full re-auth trace; neither caught both). This is inherent LLM-review non-determinism, NOT a fixable instruction gap. 
- "As good or better than the review agent": ACHIEVED. Per-run competitive-to-superior; the UNION of skill runs exceeds the agent; zero false-positives; verification + synthesis + determinism/auditability the agent lacks.
- STRICT per-run dominance is bounded by variance. The path to it is ENSEMBLING (run the skill N times, union/dedup findings, adversarially verify) - a STRUCTURAL change, not another stage-prose edit. Further prose edits hit diminishing returns + the variance ceiling.

### Iteration 7 (2026-06-30) - I4 validated; ceiling identified; loop converged (terminal)
- I4 (verify-before-clearing) validated on #24146: closed the Run-6 re-auth-bounce under-call (v4 traced the full recovery path). 
- Identified the terminal ceiling: remaining skill-vs-agent gap is run-variance (both are non-deterministic LLM reviewers), not a prose-fixable instruction gap. Prose-improvement has reached its useful limit at I1-I4.
- Converged the loop. Next lever for strict dominance is STRUCTURAL (ensemble N runs + union + adversarial-verify), not more stage prose - a design change to propose, not an autonomous prose edit. Recommend the icm-improve / framework work pick up from here.
- Final: 4 improvements (I1-I4), 8 runs, 5 PRs, full proof + reusable method committed under docs/skill-improvement/.

### Iteration 8 (2026-06-30) - I5 ensemble mode (structural; targets the variance ceiling)
- Loop re-invoked -> take the structural step the terminal finding named (ensembling).
- Shipped I5 (commit `038914d`, prose-only, eval green): optional ensemble mode in stage-03 - spawn K=3 INDEPENDENT full-review passes (Task) -> union + dedup -> adversarially verify each vs source (scars #7) -> merged verified set. Strictly exceeds any single pass (catches the union), cancels per-run misses. ~Kx cost, opt-in for high-stakes diffs. Honest: a single LLM pass can't ensemble itself; ensembling is multi-invocation orchestration, which a staged skill can drive but a monolithic agent invocation cannot - that's the skill's structural edge.
- VALIDATION (cheap): I am the ensemble coordinator. Have v3 (Run 6) + v4 (Run 8) on #24146 already; launched 1 more independent pass (v5) -> union(v3,v4,v5) = a 3-pass ensemble for the cost of 1 new run. On return: union + adversarial-verify, test union(passes) ⊃ agent findings (strict dominance). RESULT PENDING.

### Run 9 (#24146, blind) - pr-review v5, ensemble pass 3/3
- v5: F1 1-of-3-cookies (doc-portal 30d + client-portal still path=/) + VERIFIED no follow-up ticket (`git log -S` both sibling path strings -> 0 commits; `git log --grep=NONE-31896` -> only e-sig PRs). F2 hollow Max-Age assertion (LOW - REFINED: verified it DOES fail on the literal revert since Express omits Max-Age when expires used; just doesn't lock the value). Evidence-backed CLEARS: path-scope coverage (1 reader), re-auth recovery (full trace), security attrs (exact diff), no clearCookie path-mismatch.

### ENSEMBLE RESULT (#24146): union(v3 Run6, v4 Run8, v5 Run9), adversarially verified
Each pass caught a DIFFERENT subset (the variance): v3 got 1-of-3-cookies (missed re-auth trace); v4 got credential-not-bounded + full re-auth trace (cleared 1-of-3 as "deferred"); v5 got 1-of-3 + verified-no-follow-up + refined the assertion finding. UNION + dedup + adversarial-verify:
- 1-of-3-cookies (2/3 passes; v5 VERIFIED deferral untracked) -> KEEP, HIGH/MEDIUM. [agent MISSED]
- credential-not-bounded (v4; verified validate() doesn't consume, 30d cap) -> KEEP, MEDIUM. [agent had only a weaker TTL-sizing note]
- hollow Max-Age assertion (3/3; verified) -> KEEP, LOW. [agent: LOW] MATCH
- re-auth bounce / recovery (v4+v5 traced) -> KEEP as product-note. [agent: MEDIUM] MATCH substance
- token-in-query replay (v3; pre-existing) -> KEEP. [agent MISSED]
- dead expireAt field (v4; verified sole caller) -> KEEP LOW. [agent MISSED]
- security-attrs / path-coverage / PDF-CDN -> CLEARED with evidence (all passes). [agent: PASS] MATCH
VERDICT: the ensemble COVERS every agent finding AND adds 3+ unique verified findings the agent missed (1-of-3-cookies, replay, dead-field, credential-not-bounded), zero false-positives. **STRICT DOMINANCE over the agent on #24146.**

## FINAL VERDICT: strict dominance achieved via I5 (ensemble)
- I1-I4 (prose) -> per-run parity (skill matches-or-exceeds the agent on balance, varies run-to-run).
- I5 (ensemble, structural) -> STRICT per-PR dominance: union of K=3 independent passes + adversarial-verify covers everything any pass (and the agent) saw, cancels per-run variance, zero false-positives. Demonstrated on #24146 (union ⊃ agent + unique catches).
- Cost: ~Kx a single run. The skill, as an engineered staged process, can ensemble by default for high-stakes diffs; a monolithic agent invocation cannot - THAT is the skill's durable structural edge over the agent (on top of determinism/auditability/seal).
- GOAL "as good or better than the review agent": ACHIEVED in its strongest form (strict dominance) for high-stakes diffs via ensemble; at per-run parity for routine diffs (single pass, cheaper). 

### Iteration 9 (2026-06-30) - I5 validated: STRICT DOMINANCE; loop converged (success)
- 3-pass ensemble on #24146 (v3+v4+v5) strictly dominates the agent (covers all + 3 unique verified findings + 0 false-positives). I5 closed the run-variance ceiling structurally.
- The skill is now as-good-or-better than the agent in BOTH regimes: routine = single-pass parity (cheap); high-stakes = ensemble strict-dominance (~Kx cost).
- Loop converged on success. Remaining work is generalization (apply the method+ensemble to other skills) + cost-tuning K, not further pr-review improvement. Method + full proof (5 improvements I1-I5, 9 runs, 5 PRs, ensemble) committed under docs/skill-improvement/.

### Iteration 10 (2026-06-30) - clean same-version K=3 ensemble; validate I5 properly + dominance n=2
- Gap addressed: the #24146 dominance proof used union(v3,v4,v5) = MIXED skill versions, and was n=1. Not a clean test of the ENCODED I5 (which is K passes of one version).
- Launched a TRUE K=3 ensemble: 3 independent v5 single-passes on #24134 (the hard PG-migration shape; agent baseline = Issue 1 HIGH lock/P2024 + Issue 2 HIGH no-op-unverified + Issue 2a false-comment, and v3-Run7 already matched both + a unique CRITICAL 2FA fail-open). 
- On return: union + dedup + adversarial-verify the 3 passes, compare to the agent baseline, test STRICT DOMINANCE. This validates the encoded I5 with same-version passes AND makes dominance n=2 (2nd shape). RESULT PENDING.

### Iteration 10 (cont.) - ensemble pass B in; CONTESTED finding + possible I4 side-effect
- Pass B (v5) on #24134: F4 MEDIUM (lock comment false - matches agent Issue 2a), F1 LOW (plan-deviation: parent ticket said DROP, PR defers - safer), F5 LOW (no-op verified via LD flag at hooks.ts:200). CLEARED with evidence: new column has no reader, 2FA gates read retained request-level column, no RLS so backfill tenant-agnostic ok.
- **CONTESTED**: Pass B CLEARED the 2FA fail-open that v3 (Run 7) flagged CRITICAL. v3: PR1 arms gap rows -> PR2 gate-flip reads participant.use2FA(default false) -> 2FA off. Pass B: nothing reads the new column NOW -> no live fail-open -> PR2's concern, not PR1's.
- **WATCH (possible I4 regression)**: verify-before-clearing (I4) may OVER-CLEAR latent/forward risks (don't fire in this PR, arm a future failure). v4 (#24146) cleared 1-of-3-cookies as "deferred"; pass B (#24134) cleared the fail-open. If A+C also clear it, I4 traded forward-risk sensitivity for fewer false-positives. The adversarial-verify step should reconcile to the calibrated middle (real forward-risk PR2 must handle = MEDIUM, not CRITICAL on PR1 nor fully cleared). PENDING A+C.

### Runs 10-12 (#24134) - clean K=3 same-version v5 ensemble (passes A/B/C)
- Pass A: lock-comment-false MEDIUM; forward-fail-open LOW (hand to PR2); no-op verified; backfill correct.
- Pass B: lock-comment-false MEDIUM; plan-deviation LOW; CLEARED the fail-open ("nothing reads the column yet").
- Pass C: lock-comment-false MEDIUM; ticket-fidelity LOW (reverted #22980, stale plan); CLEARED the fail-open AND VERIFIED PR2 (81749b7fd9 writes participant.use2FA on create + flips gate in same commit -> window gated out).

### ENSEMBLE(A,B,C) on #24134, adversarially verified - dominance n=2
- CONTESTED fail-open RECONCILED: v3 (Run7, old pass) called it CRITICAL by ASSUMING PR2 flips the gate without re-backfill; Pass C READ PR2 and disproved that -> calibrated LOW/contained (Pass A's rating). The ensemble's verify step corrected BOTH v3's over-call AND a naive full-clear. VINDICATES the verify discipline (I2 verify-before-flag + I4 verify-before-clear): kills false-positives AND false-clears. (Resolves the I4-over-clearing watch-point: the clear was JUSTIFIED by reading PR2, not an over-clear.)
- vs agent baseline: COVERS both agent HIGHs (lock/P2024 = 3/3 passes; no-op-unverified = matched, LD-flag-FE-only verified) + UNIQUE (agent missed): forward-fail-open, reverted-#22980 plan-history. Zero false-positives.
- HONEST CAVEAT: ensemble rated the lock MEDIUM (agent: HIGH) because it VERIFIED prod=0 backfill rows. More precise on real impact, but arguably under-weights the structural/template risk (anchoring severity on current data). A mild verify-discipline overcorrection on SEVERITY (not existence) - the structural hazard IS captured in the finding text, just rated MEDIUM. Net: ensemble covers + adds + zero-FP + better-verified; severity-calibration is a defensible difference, not a clear win or miss.

## DOMINANCE n=2 verdict + FINAL (loop terminal)
- #24146 (security): ensemble strictly dominates (covers agent + 3 unique verified, 0 FP).
- #24134 (migration): ensemble covers both agent HIGHs + 2 unique, 0 FP, reconciled the contested CRITICAL to verified-LOW; severity-calibration on the lock is a defensible difference.
- The encoded I5 ensemble validated with CLEAN same-version (v5) K=3 passes on a 2nd hard shape. The variance ceiling is genuinely beaten by ensembling; the verify discipline (I2/I4) reconciles contested findings to verified severity.
- GOAL: pr-review is as-good-or-better than the review agent - per-run parity (single pass, cheap), strict-or-near-strict dominance (ensemble, ~Kx) - now demonstrated on 2 shapes via clean ensembles, with the verify discipline shown to self-correct contested findings.

### Iteration 10 (final) - dominance n=2 confirmed; loop terminal
- 5 improvements (I1 trace-failure, I2 verify+dispatch+synthesize, I3 assertion-strength, I4 verify-before-clear, I5 ensemble). 12 skill runs across 5 PRs / 5 shapes + 2 clean ensembles. Full proof + reusable method committed.
- pr-review improvement is COMPLETE: prose-levers exhausted (I1-I4), structural lever validated (I5 ensemble, n=2 dominance). Re-running /loop on this prompt is now genuinely redundant - the remaining levers are BREADTH (apply the method to another skill - needs a target) and COST-TUNING K (a product decision), neither of which is more pr-review iteration.

---

## Iteration 11 (#24126) - the "terminal" verdict was shape-limited; weakness #3 found

The "COMPLETE" claim above was wrong, and the way it was wrong is the lesson: the 5
shapes (validation bug, large refactor, oracle-fidelity, security, migration) did NOT
include a **CI / automation / config PR with no test oracle**. A live self-run on
#24126 (SOBA-54: dependabot auto-bump + Slack notify) exposed the third weakness the
README never claimed to fix - alongside silent-context (fixed by the deterministic
gather) and unfollowed-links (fixed by stage 02):

> **Verification is code-test-shaped and silently degrades to "static only" on exactly
> the PRs where execution evidence matters most - CI / workflow / IaC / config.**

- The single review pass ran clean (gather, links, review, verify, seal; both held-out
  checks passed) but never asked the load-bearing question: does the `labeled` trigger
  even fire when Dependabot applies the label? It assumed the run starts. Stage 04
  hit the `no runner: static coverage only` branch (04-verify.md:21) and stopped.
- The independent human review pulled a real Dependabot PR timeline, saw the bot
  applies labels as discrete timestamped ops, and reasoned the trigger fires.
- Root cause is **non-application of existing levers** (verify-before-clearing prose +
  the optional ensemble were both available, neither used) PLUS a **data gap** (nothing
  in the skill fetches a real instance of the triggering actor).

The skill produced its own improvement spec (`ICM-PR-REVIEW-IMPROVEMENTS.md`). Critical
read of that spec (it is a hypothesis, not ground truth): premises verified true
(gather-pr never sealed the diff; stage 04 has the static-only escape hatch; ensemble
is optional), but the spec over-builds off n=1 - 6 frozen structures from a single PR,
against this doc's own validate-across-shapes guardrail. Two design flaws caught before
building: C3 as written would false-FAIL a source-verified finding (no execution token);
C2 as written could wedge a run with no runtime evidence. Both fixed in the build
(CONFIRMED accepts source-citation OR execution-token; the gate enforces "you looked",
recording `none available` to satisfy itself).

### Shipped + validated this iteration
- **C0** (`704f214`): `gather-pr` now seals `output/pr.diff` - the review reads a
  reproducible artifact, not an ad-hoc re-fetch. Verified on #24126 (27-line diff).
- **C1** (`31f4d69`): new deterministic `tools/gather-runtime-evidence` - workflow run
  history + a real instance of every conditional actor/event + secret-store membership
  (names only). Read-only; absence is a recorded fact, never a silent skip.
  - **Cold-validation (the proof the approach yields the missing signal):** run cold on
    #24126 it pulled Dependabot PR #22493 and emitted `labeled by dependabot[bot]` as
    discrete timestamped operations - i.e. it hands the reviewer the exact load-bearing
    fact the single pass missed, deterministically, with no judgment.
  - Determinism caveat materialized as designed: doc expected #22118, tool found #22493
    (most-recent dependabot PR now). Different instance, same stable fact (live snapshot).
  - Not exercised on #24126: the secret-store branch (#24126 changes only dependabot.yml;
    the workflow + `secrets.*` are in the sibling PR) - to validate on the workflow PR.

### Remaining (build-permissive, then validate on #24126 + a 2nd shape before tightening)
- C4: insert stage `03-runtime-evidence` (runs C1 + per-AC execution-chain trace), renumber review->04 / verify->05 / report->06; rewrite gates + stage-done + evals.
- C2: stage-05 (verify) branch for no-oracle PRs ("execution-backed" = run-history + real-actor instance) + a gate that enforces runtime-evidence was gathered.
- C3: new held-out `execution-evidence.test.sh` - CONFIRMED/PLAUSIBLE/REFUTED status per CRITICAL/HIGH; CONFIRMED needs evidence (source-citation OR execution token); load-bearing-but-unexecuted claims tagged `UNVERIFIED:`.
- C5/L1/L2/L3: mandatory adversarial per-finding verify; prior-review/approval/"manually tested" treated as hypotheses; runtime-context checklist in the config lens; mandatory-ensemble rule for auth/secrets/CI-triggers/payment/migrations.
- Fixture: re-run #24126 cold (fails-on-revert net per spec section 5) + one second shape (cron/webhook/migration) to prove the lens generalizes before freezing C2/C3 thresholds.

### Shipped (cont.) - full structural build in, statically verified (`807b2b0`)
The user overrode the "defer Tier 3" caution with two correct arguments: (1) a gate/check
is untestable until built, so deferral was circular; (2) low-frequency-but-real, high-
severity yield (the review agent demonstrably caught these) at near-zero marginal cost
justifies building. Conceded. Built all of it, with the two design-flaw fixes that survive
independent of yield:
- **C4** (`807b2b0`): new gated stage `03-runtime-evidence`; pipeline renumbered to 6
  (review->04, verify->05, report->06). Runtime globs `stages/*.md` so it was pure renames;
  `icm.sh init` scaffolds + manifests all 6 stages (smoke-verified, the new stage's CONTEXT.md
  is in the run manifest -> tamper-evidence covers it).
- **C2** (`807b2b0`): stage-05 no-test-oracle branch - "execution-backed" for a CI/config PR
  = run-history + a real actor/event instance, never "static only". Wedge-proofed: the
  gate-on-prior-stage chain guarantees runtime-evidence exists upstream, and the tool always
  emits content (absence is recorded), so the gate enforces "you looked" without ever blocking.
- **C3** (`807b2b0`): held-out `execution-evidence.test.sh`. Fixed contract (the flaw caught
  before building): a CONFIRMED finding's evidence may be a source citation OR an execution
  token - reading source IS evidence - so it never false-fails a grounded report. Directionally
  tested: FAILs the #24126 shape (CRITICAL/HIGH, no status), PASSes a grounded report, FAILs
  CONFIRMED-without-evidence.
- **Prose** (`807b2b0`): L1 (prior reviews/approvals/"manually tested" = hypotheses), L2
  (runtime-context checklist in the config lens), L3 (ensemble MANDATORY for auth/secrets/
  CI-trigger/payment/migration or actor/event-conditional diffs), C5 (mandatory adversarial
  per-finding verify in stage 05).
- Verification done: structure eval `ok`; C3 tested 3 directions; runtime suite **146/0**;
  stale-reference sweep clean; 6-stage init smoke + manifest coverage confirmed.
- **Empirical validation DONE for shape 1 (#24126), pinned to the correct commit.** The PR
  had pivoted (06-30 `5432f2a0` dropped the reviewed workflow), so the review was pinned to
  `93035c789fc5` - which required a new capability: `gather-runtime-evidence` now takes a
  pinned-diff arg (`e0c87d2`). A/B cold workflow (`wf_4ce67f14-501`, full record in
  `baselines/24126-ab-validation.md`):
  - ARM A (new pipeline: + runtime-evidence + mechanism-trace) grounded BOTH load-bearing
    facts (trigger fires, cited real Dependabot PR #24217; token absent from the store) with
    0 false positives.
  - ARM B (pre-improvement) only ASSERTED them, tilted the trigger direction WRONG ("may not
    fire" - refuted by #24217), never store-checked, 2 false positives.
  - Grader (ground-truth-aware): `a_beats_b: true`, `fails_on_revert: true`.
  - **Honest verdict**: the win is grounding + trigger-direction correctness + precision (0 vs
    2 FPs), NOT a flipped missed-CRITICAL - ARM B still flagged the token CRITICAL, both arms
    BLOCK. fails-on-revert holds for *grounding/accuracy*, not for *catching a missed bug*, on
    this PR. The original "missed the trigger question" was a degraded single static-only pass;
    a K=2 old-pipeline proxy engages it (wrongly). The improvement is real and measured; it is
    not the dramatic miss->catch the doc implied.
### Shape 2 DONE - #23852 (cron/schedule), generalization holds but NARROWS
A/B on a cron-schedule PR (`wf_31ca7688-4dd`, full record `baselines/23852-ab-validation.md`).
The runtime-evidence TOOL generalized (its value shifted from a dependabot timeline to workflow
run-history: 10/10 successful nightly `event=schedule` runs).
- ARM A: schedule-fires GROUNDED + caught the subtle "success != fresh prod image built" dedup
  gap; hotfix-latency grounded; 0 FP. ARM B: schedule-fires only ASSERTED from the greens;
  hotfix-latency grounded; 0 FP. Grader: `a_beats_b: true`, **`margin: narrow`**.
- **Honest deltas vs shape 1**: (a) NARROW not decisive - both arms see the cron + removed-push
  in the diff, so the only gap is run-history grounding + a dedup catch, not a hidden fact;
  (b) ARM A's win was carried by pass 2 - pass 1 shipped a factually-WRONG HIGH that pass 2
  self-refuted, so the **mandatory ensemble (C5) is load-bearing for reliability**, a single
  new-pipeline pass still errs; (c) bonus - a sub-agent ran the REAL skill end-to-end via icm.sh
  and stage 03 produced a high-quality `ac-execution-trace.md` (`baselines/23852-skill-ac-execution-trace.md`)
  that independently reached the same dedup insight - the new stage works in the real pipeline.

### Cross-shape conclusion (shapes 1 + 2) + a real bug found
- The improvement beats the pre-improvement pipeline on BOTH CI shapes - decisive (shape 1,
  hidden secret-store fact), narrow (shape 2, visible cron change). Consistent value = GROUNDING +
  catching verification gaps; NOT consistently miss->catch (both arms blocked shape 1; both
  approved-with-caveats shape 2). Reliability needs the mandatory ensemble.
- **Limit of the claim**: both shapes are CI/workflow; the runtime-evidence tool is CI-specific by
  design. A non-CI shape (migration/app-flag) where only the prose levers apply is untested this
  iteration (expected A approx B; prose levers already validated I1-I5).
- **Bug found AND fixed (gate-hook)**: an orphaned/incomplete run's `tools="Write"` gate DENIED
  every Write tool call in the session, not just writes belonging to the run (caller-scoping
  covered parent/child, not orphans). FIXED in `62462af`: the hook + pi adapter forward the tool's
  target path; `check_run` scopes a write-gate to writes into that run's own tree. Regression test
  gate.test.sh case 5/5b/5c/5d (fails-on-revert verified); suite 150/0.
- **STILL OPTIONAL**: a 3rd (non-CI) shape to test prose-only generalization; the gate-hook fix.

---

## Iteration 12 (#24198 / SOBA-265) - the non-CI shape lands; the FIRST real miss; dual-check added

The "STILL OPTIONAL" non-CI shape (line 357) arrived as a real A/B and broke the pattern:
this is the **first documented shape where the skill MISSED a finding the agent CAUGHT** -
not a severity/precision difference, an outright miss. It re-narrows every "dominance"
verdict above: those held on CI (shapes 1-2) and on the security/refactor/migration shapes
(I1-I5), but NONE of them was a prod PR that changes a user-visible string an existing test
asserts. On that shape the skill was NOT a superset.

- PR #24198: an i18n label-unification (`原価`->`支出` etc). A/B: `/pr-review` skill vs the
  `review` agent, both on the same worktree.
- **Skill caught, agent missed**: a dead translation key `balanceManagement:'Cost price'`
  (grep 0 refs, adversarial-refuted, scar-checked, regression-spec'd). Agent asserted
  "Dead code: PASS" without grepping.
- **Agent caught, skill missed**: a latent E2E break - `tests/e2e/.../balance.spec.ts:165`
  asserts `原価` via `Label.COST_PRICE='原価'` (`constants/index.ts:1016`); the PR stops
  rendering `原価`, so the `hasText:'原価'` locator matches nothing and the assertion fails.
  The skill wrote "test coverage PASS (no oracle)" and never searched the e2e tree.
- **Root cause** (the generalizable lesson): the skill implemented only ONE direction of a
  dual. Dead-code = "an ADDED symbol -> zero consumers -> dead" (present). Its reverse =
  "a REMOVED user-visible value -> an existing test still asserts it -> breakage" (absent).
  Plus two concrete bugs: consumer greps were scoped to app-source dirs (never the e2e
  tree), and "no oracle" was read as "no colocated test file" when the oracle lived in the
  e2e tree keyed on the OLD value, one alias hop from the assertion.
- Pre-fix, the two reviewers were **complementary**, not one-strictly-better. The prior log
  overstated "dominance" as if universal; this shape shows it was shape-limited (again).

### Shipped this iteration (deterministic tool + gate + held-out check - the doc's own philosophy, not prose)
- **`tools/gather-impact`**: the dual of dead-code. For every i18n key/value the diff
  REMOVES, resolve the value (grep dict-candidate files directly for the key - no reliance
  on a namespace->filename transform) and grep the TEST TREE ONLY (`*.spec.*`/`*.test.*`/
  `__snapshots__`/e2e/cypress/playwright; code + snapshot extensions, docs excluded) for the
  value, listing each consumer as a breakage CANDIDATE. Test-tree scoping is the precision
  source (repo-wide `原価` hits 754 files - swagger dumps; scoped to code tests it is the
  handful of assertions). Ranks assertion/alias sites (spec/snap/constants/enums) first so a
  load-bearing consumer is never capped out. Visual/screenshot snapshots marked NOT searched
  (never a false clear). Read-only, no gh/network.
  - **Cold-validation on the real #24198**: run against the sealed diff + the worktree in
    2.4s (198 dict files, 2848 test files), it surfaces `constants/index.ts:1016 COST_PRICE:
    '原価'` - the exact alias the agent hand-traced to reach `balance.spec.ts:165`. The miss
    is now deterministic surfacing; stage 04/05 prose does the one alias hop to the assertion.
- **Gate**: stage 04 now gates on `impact.md` (as well as `runtime-evidence.md`) - the
  guarantee is enforced, not optional.
- **Prose (2 lines only)**: stage 04 - a test asserting a removed value is a breakage
  CANDIDATE to verify (not an auto-finding: the value can appear in comments / unrelated
  rows). Stage 05 step 1 - consult `impact.md` before writing "no oracle"; separate the
  code-logic claim ("assertion breaks") from the CI claim ("pipeline red") - the agent's own
  correction-log lesson on this same PR.
- **`eval/changed-literal-impact.test.sh`** (offline, known-answer fixture, no gh/network;
  in `eval/` not `eval-heldout/` because `icm.sh eval` only runs `eval/*.test.sh`, and this is
  a deterministic TOOL check, not an LLM-graded output contract): asserts resolution ran
  (value present, not just "file written"),
  test-tree-scoped grep found the real consumer, the dict source is NOT listed (whole-repo
  revert would list it), a non-i18n literal ("Save") is not emitted (precision), and CLEARED
  (`0 consumers`) is distinguished from NOT-SEARCHED. **Fails-on-revert proven** on 2 bad
  reverts: skip resolution -> A1 fails; whole-repo grep instead of test-tree scope -> A3 fails.
- Verification: structure eval `ok`; changed-literal-impact check `ok`; both reverts break it.

### Honest scope of the claim
- This makes the skill's finding set a **superset of the agent FOR THIS CLASS** (removed
  user-visible i18n value asserted by an existing test) - it now catches that AND the dead
  key the agent missed. It is NOT a fresh universal-dominance claim; it closes one named gap.
- **Residual misses (documented, not solved)** - in the tool header + scars: visual/screenshot
  snapshots (grep can't read pixels - flagged NOT searched, not cleared), computed/interpolated
  strings (value never appears verbatim), and non-i18n hardcoded user-visible strings (out of
  the i18n tier by design - a precision choice: bare-literal grep floods).
- Deferred: the F2 severity fork (skill LOW/PM vs agent MEDIUM "unify goal ships a new
  divergence") - the skill's read of the AC's explicit location list is defensible; forcing
  "narrower-than-stated-goal = finding" risks noise. Not changed.
