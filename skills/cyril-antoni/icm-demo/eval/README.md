# Eval: icm-demo

Checks run by `icm.sh eval cyril-antoni/icm-demo` (each runs from the skill dir and
exits 0 on pass). They cover the deterministic surface only - no live model, no network
- which is the whole surface a demo skill should be able to assert.

- `smoke.test.sh` - structure: SKILL.md frontmatter, the three numbered stages, the
  three executable `tools/` scripts and `checks/ready.sh`, the `ICM-GATE` construct in
  stage 02, and that NO stage file hosts a scrapable `<!-- ICM-CALL` comment.
- `run-report.test.sh` - stage 01's `tools/run-report` against a fresh synthetic run:
  asserts it reports the stage order, this run's `run.json`, the enforcement posture,
  and the five tracking artifacts.
- `sandbox-tour.test.sh` - stage 02's `tools/sandbox-tour`: asserts the runtime still
  denies an unmet gate, normalizes a wrapped `mcp__` name (same gate matches), leaves a
  non-gated tool alone, allows once the precondition holds, verifies a seal, and catches
  BOTH tamper layers (`SEAL MISMATCH` for a sealed file, `contract tampered` for a
  frozen file).
- `show-telemetry.test.sh` - stage 03's `tools/show-telemetry`: asserts it reifies and
  shows the per-stage `stage_done` events with the four token fields kept separate.
- `close-run.test.sh` - the post-run finalizer `tools/close-run` (run after every stage
  is closed): asserts reify/audit/seal/verify (`SEAL OK`), the framed advisory-only
  deviation note, and the indexing of all three stages' evidence.

Each test runs its tool against a throwaway run under an isolated `$HOME` + cwd, so the
suite never touches the user's real `.icm/`. They fail on a real runtime regression -
revert the change rather than weakening an assertion. Only the model's chat narration
(its spoken explanation per stage) is non-deterministic and so not eval-tested; confirm
that with a live `/icm-demo` run.
