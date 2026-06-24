# Eval: icm-demo

Checks run by `icm.sh eval cyril-antoni/icm-demo` (each runs from the skill dir and
exits 0 on pass). They test the deterministic surface only - no live model, no
network - which is exactly the surface a demo skill can fully assert.

- `smoke.test.sh` - structure: SKILL.md frontmatter, the three numbered stages, the
  executable `tools/sandbox-tour` and `checks/ready.sh`, and the ICM-GATE / ICM-CALL
  template constructs in stage 02.
- `sandbox-tour.test.sh` - behaviour: runs `tools/sandbox-tour` and asserts the
  runtime still denies an unmet gate, normalizes a wrapped `mcp__` tool name (so the
  same gate matches), leaves a non-gated tool alone, allows once the precondition is
  met, verifies a seal, and catches BOTH tamper layers (`SEAL MISMATCH` for a sealed
  file, `contract tampered` for a frozen file). This fails on a real runtime
  regression, so revert any change that breaks it rather than weakening the assertion.

The model-mediated stages (the prose tours written in 01 and 03) are not eval-tested;
verify those with a live `/icm-demo` run.
