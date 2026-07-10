# Stage 05: Execution-backed verification

<!-- ICM-TOOLS expect="(Read|Bash|Task)" -->
<!-- ICM-GATE tools="Write" run="test -s ../04-review/output/findings.md" -->

Back the findings with execution: run the changed area's suite, mutation-test the
HIGH-risk findings, confirm any live-metric claims read-only, and adversarially verify
each finding. The gate blocks writing the verification until findings exist.

This is the only stage that touches the filesystem beyond `output/` - and ONLY
inside a throwaway `git worktree` that is removed afterward. The tracked tree is
never modified. Never implement a fix, commit, push, or POST to any live service.

## Inputs
| Source | Location | Scope |
|--------|----------|-------|
| Findings | ../04-review/output/findings.md | what to back with execution + statuses to confirm/refute |
| Checklist audit | ../04-review/output/checklist-audit.md | the checklist items marked `asserted` - the judgment claims this stage must exercise, not trust |
| Runtime evidence | ../03-runtime-evidence/output/runtime-evidence.md | the execution oracle for no-test-oracle (CI/config/IaC) PRs |
| Changed-value impact | ../03-runtime-evidence/output/impact.md | existing tests that assert a value the diff removes - an oracle you must not miss |
| PR repo | the local checkout of `<owner>/<repo>`, if present | to run the suite |

## Process
1. **Detect runner**: package.json `test` / vitest|jest|mocha config / pytest / a `scripts/**/run-all.sh`. If the PR's repo is not checked out locally or no runner is found, write `no runner: static coverage only` for the SUITE line and skip steps 2-3 (do NOT fabricate results) - BUT do not stop there (see step 1b).
   **Consult `impact.md` BEFORE writing "no oracle".** If any existing test/snapshot asserts a value this PR removes (a breakage candidate in impact.md), that test IS an oracle for this change - "no oracle / no test for this component" is then FALSE. Trace each candidate: does the assertion or page locator depend on the removed value? If yes it is a latent break (test-coverage finding), even when that suite is `workflow_dispatch`/deploy-only and stays green on the PR pipeline - separate the code-logic claim ("the assertion breaks") from the CI claim ("the pipeline goes red"); assert only the one you verified.
1b. **No-test-oracle PRs (CI / workflow / IaC / config / integration): "execution-backed" does NOT mean static.** A diff with no code test oracle is exactly where the worst misses hide. For such a PR, execution-backing means: the workflow run-history + the real-actor/event instance gathered in stage 03's `runtime-evidence.md`, plus an event/security-context analysis (does the trigger fire for the real actor? does the secret resolve in the store that context uses?). A verification MUST NOT be marked verified for a no-oracle PR on static reads alone - cite the runtime-evidence facts that confirm or refute each mechanism finding. If runtime-evidence genuinely had nothing to show (e.g. brand-new workflow, no history), say so explicitly and mark the relevant findings `UNVERIFIED`, not verified.
1c. **Worktree bootstrap (the expensive step - do it ONCE, then reuse for suite + mutation + probes).** `git worktree add <abs-run-dir>/work/<name> HEAD` places the throwaway worktree under the run's `work/` dir so a session restart does NOT delete it mid-run (never the harness scratchpad - that cost run #24374 a full rebuild). `git worktree add` alone is the easy 5%; for a real monorepo whose PR head sits on a moved master the deps/codegen do NOT carry over the gap: (1) `pnpm install --prefer-offline` (or the repo's manager) - never assume node_modules symlinks suffice across a base-branch gap; (2) run the codegen the repo needs when its inputs differ from the tracked tree (`prisma generate`, openapi) - a stale client references models that no longer exist or misses new ones; (3) secrets: SYMLINK env files (`ln -s`), never read or copy their contents (a hook rightly blocks reading `.env` - symlink, respect it); (4) if jest-setup migrates a SHARED local test DB forward, DISCLOSE that mutation in verification.md; (5) before trusting a `@workspace`-style package that resolves through a relative symlink into the original tree, verify its diff is irrelevant to the change. Remove the worktree with `git worktree remove --force` before the run's `work/` is cleaned, or git leaves a stale registration.
2. **Suite**: in the bootstrapped worktree, run the changed area's tests; record total / passed / failed / skipped.
3. **Mutation** (HIGH-risk findings + questioned symbols only), in the bootstrapped worktree (1c) - the tracked tree is never modified:
   - inject ONE representative fault (flip a condition, drop a guard, change the constant).
   - Run the suite. RED = caught (good). GREEN = the fault SURVIVED -> behavior untested -> finding + 7-Point #6 FAIL.
   - Revert the fault between mutations; `git worktree remove --force` when the stage is done (even on error).
3b. **Probe specs (for each CRITICAL/HIGH whose failure scenario is constructible with the repo's test harness).** In the bootstrapped worktree, write a disposable probe spec that exercises the failure, and run it against BOTH the PR head AND the reverted code (checkout the pre-PR state of the touched files). The two-direction result distinguishes a NEW regression (fails on head, passes on revert) from a PRE-EXISTING issue (fails on both). Probes NEVER ship to the PR branch; record each probe's fixture + assertion in verification.md as a ready-made regression spec. A CRITICAL confirmed by a two-direction probe is execution-proven, not merely source-confirmed - the strongest evidence this stage can produce (it is what flipped #24374 to BLOCK).
4. **Live (read-only MCP)**: for any phantom-metric finding, confirm the metric/log exists (Datadog/Sentry read-only). A dashboard referencing a never-emitted metric is HIGH.
5. **Adversarial per-finding verify (MANDATORY).** For each CRITICAL/HIGH finding from stage 04, run an INDEPENDENT pass that tries to REFUTE it against source/runtime-evidence (not to confirm it) - default to refuted if the evidence is not actually there. Resolve each to a final `CONFIRMED` / `PLAUSIBLE` / `REFUTED` + the evidence that settled it. For HIGH-stakes diffs (auth/secrets/CI-triggers/payment/migrations, or actor/event/environment-conditional behavior) use perspective-diverse verifiers (correctness / security / does-it-actually-execute) via parallel Task, not one. This is the second pass that makes a finding "done"; a finding that survives a genuine refutation attempt is real, one that collapses is dropped or downgraded with the reason recorded.
6. **Exercise the `asserted` checklist items (MANDATORY when checklist-audit.md has any).** Every `asserted` MET from stage 04 is an unverified judgment until exercised here - promote it to `verified` only after you actually do the thing the item claims, or downgrade it to `GAP`. Never let a proxy stand in: "documentation sufficient / understandable without context" -> READ the changed/added doc content end to end (not the diffstat), and say whether a newcomer could act on it; "enough test coverage *for the risk*" -> inspect the tests that cover the changed logic and name which branches/edge-cases of the new code are and are NOT exercised (a count is not coverage); "observability / failures easily debugged" -> look at the actual error/log/output surface the change emits and state what a failure would show; "no secrets" -> grep the diff; "deps up-to-date" / "env-var config" -> diff the manifest / grep for `process.env`. Record each as `verified: <what you did + result>` or `GAP: <what the exercise showed>`. If exercising is impossible here (needs a running service, human judgment), mark it `UNVERIFIED: <why>` - never silently `verified`. Then re-run the stage-04 **bias alarm** against the exercised results: if the gaps still cluster only on the scannable items, look harder at the ones you passed.

## After Output (MANDATORY)
```bash
bash ~/.agents/skills/icm/runtime/icm.sh stage-done kakkoidev/pr-review --stage 05-verify
```

## Outputs
| Artifact | Location | Format |
|----------|----------|--------|
| Verification | output/verification.md | Suite: `N passed, M failed, K skipped` via `<runner>` (or `no runner: static coverage only`); for no-oracle PRs, the runtime-evidence facts that back each mechanism finding (never "static only" as the whole verification); Mutation: per finding `caught` / `SURVIVED` (a SURVIVED fails 7-Point #6); Live: per metric `has-data` / `phantom` / `unverified`; Adversarial verify: per CRITICAL/HIGH a final `CONFIRMED` / `PLAUSIBLE` / `REFUTED` + the evidence that settled it; Checklist exercise: per `asserted` item from 04 a final `verified: <what you did>` / `GAP: <what it showed>` / `UNVERIFIED: <why>`, plus the re-run bias-alarm line. |
