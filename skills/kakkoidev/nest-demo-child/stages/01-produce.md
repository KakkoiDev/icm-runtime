# Stage 01: produce evidence, then publish

<!-- ICM-TOOLS expect="(Read|Write)" -->
<!-- ICM-GATE tools="publish" run="checks/child-ready.sh" -->

The child's whole job: produce its evidence, then publish it. The `publish` tool
is gated until `output/child-evidence.md` exists - the child's own precondition.

## Process
1. Write `output/child-evidence.md` (the child's work product).
2. Call the `publish` tool. The gate now passes because the evidence exists.

## After Output (MANDATORY)
```bash
bash ~/.agents/skills/icm/runtime/icm.sh stage-done kakkoidev/nest-demo-child \
  --stage 01-produce
```

## Outputs

| Artifact | Location | Format |
|----------|----------|--------|
| Child evidence | output/child-evidence.md | any non-empty content |
