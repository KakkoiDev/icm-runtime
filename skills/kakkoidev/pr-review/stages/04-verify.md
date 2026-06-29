# Stage 04: Execution-backed verification

<!-- ICM-TOOLS expect="(Bash)" -->
<!-- ICM-GATE tools="Write" run="test -s ../03-review/output/findings.md" -->

Back the findings with execution: run the changed area's suite, mutation-test the
HIGH-risk findings, and confirm any live-metric claims read-only. The gate blocks
writing the verification until findings exist.

This is the only stage that touches the filesystem beyond `output/` - and ONLY
inside a throwaway `git worktree` that is removed afterward. The tracked tree is
never modified. Never implement a fix, commit, push, or POST to any live service.

## Inputs
| Source | Location | Scope |
|--------|----------|-------|
| Findings | ../03-review/output/findings.md | what to back with execution |
| PR repo | the local checkout of `<owner>/<repo>`, if present | to run the suite |

## Process
1. **Detect runner**: package.json `test` / vitest|jest|mocha config / pytest / a `scripts/**/run-all.sh`. If the PR's repo is not checked out locally or no runner is found, write `no runner: static coverage only` and skip steps 2-3 (do NOT fabricate results).
2. **Suite**: run the changed area's tests; record total / passed / failed / skipped.
3. **Mutation** (HIGH-risk findings + questioned symbols only):
   - `git worktree add <tmp> HEAD` (throwaway; tracked tree untouched).
   - In the worktree, inject ONE representative fault (flip a condition, drop a guard, change the constant).
   - Run the suite in the worktree. RED = caught (good). GREEN = the fault SURVIVED -> behavior untested -> finding + 7-Point #6 FAIL.
   - `git worktree remove --force <tmp>` ALWAYS (even on error).
4. **Live (read-only MCP)**: for any phantom-metric finding, confirm the metric/log exists (Datadog/Sentry read-only). A dashboard referencing a never-emitted metric is HIGH.

## After Output (MANDATORY)
```bash
bash ~/.agents/skills/icm/runtime/icm.sh stage-done kakkoidev/pr-review --stage 04-verify
```

## Outputs
| Artifact | Location | Format |
|----------|----------|--------|
| Verification | output/verification.md | Suite: `N passed, M failed, K skipped` via `<runner>` (or `no runner: static coverage only`); Mutation: per finding `caught` / `SURVIVED` (a SURVIVED fails 7-Point #6); Live: per metric `has-data` / `phantom` / `unverified`. |
