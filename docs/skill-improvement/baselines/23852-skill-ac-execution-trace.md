# AC execution trace - PR #23852

The PR body states four mechanism claims. Each traced
`trigger -> condition -> step -> external effect` against the post-change file
and runtime-evidence.md.

## M1: push to release/release-TG no longer rebuilds+restarts prod
- trigger: push to release / release-TG
- post-change: the `on.push` block is DELETED (diff lines 24-28 removed).
- chain: push event -> (no workflow trigger matches) -> no build -> no ECR push
  -> no pod roll. **executes** - removal is total; no residual push path in this
  file. (Caveat: only governs THIS workflow. A separate workflow could still
  build on push - checked in findings; only deploy-operation.yml exists for
  operation, confirmed via `ls .github/workflows | grep oper`.)

## M2: all four targets build on the nightly schedule
- trigger: schedule cron '0 18 * * *' (03:00 JST)
- condition: `github.event_name == "schedule"` -> MATRIX = [STAGING, TG_STAGING,
  PROD, TG_PROD] (diff line 37).
- chain: cron fires -> targets job emits 4-element matrix -> build job fans out
  4 legs. **executes for the real actor** - runtime-evidence.md shows 10/10
  recent nightly runs `event=schedule conclusion=success`. (Those runs predate
  the diff's merge into the scheduled-on-default-branch path for prod; the cron
  itself is proven live. The 4-leg fan-out is proven by the matrix literal.)

## M3: ECR-exists check makes nightly a no-op for unchanged branches
- trigger: each matrix leg (scheduled)
- condition: checkout `matrix.target.ref` (line 82) -> `git rev-parse HEAD`
  (line 90) -> `aws ecr describe-images imageTag=<sha>` (lines 103-105).
- chain: if the branch HEAD sha's tag is already in ECR -> `exists=true` ->
  Build step `if: steps.exists.outputs.exists != 'true'` is skipped (lines
  113/118). **executes** - the gating `if` is on both the node-read and the
  build-and-push step. An unchanged branch => same HEAD sha => tag present =>
  build skipped. No redundant rebuild, no pod roll. Verified the `if` guards the
  push step, so "exists" truly prevents the ECR push.

## M4: manual workflow_dispatch on release/release-TG remains for immediate build
- trigger: workflow_dispatch on release / release-TG
- condition: non-schedule path -> `case github.ref_name` -> release => [PROD],
  release-TG => [TG_PROD] (lines 54-55).
- chain: dispatch on release -> matrix [PROD] -> build leg for prod. **executes**
  - the case arms are unchanged by this diff (only the schedule arm changed).
  NOTE: an immediate prod build via dispatch still rebuilds + can roll the prod
  pod - same effect the PR is trying to avoid on push, just now operator-
  initiated. That is the intended escape hatch, not a defect.

## Value-only / non-mechanism
- Header comment block (diff lines 11-16): documentation. constant - checked in 04.
