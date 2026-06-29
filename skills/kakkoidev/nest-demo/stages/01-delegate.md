# Stage 01: delegate to a child run, then finish

<!-- ICM-TOOLS expect="(Read|Write)" -->
<!-- ICM-GATE tools="publish" run="checks/parent-ready.sh" -->

Delegate a subtask to the child skill, wait for it, then produce this run's own
evidence and publish. The `publish` tool is gated until
`output/parent-evidence.md` exists - the parent's own precondition. While the
child run is open, this gate is suspended (caller-scoping), so the child can
publish its own work; it resumes once the child closes.

## Process
1. **Delegate** to the child as a real child run, recording this run as its caller:
   ```bash
   bash ~/.agents/skills/icm/runtime/icm.sh init kakkoidev/nest-demo-child \
     --caller kakkoidev/nest-demo/<this run id>/01-delegate
   ```
2. Execute the child's `01-produce` stage (it writes `output/child-evidence.md`
   and publishes), then `icm.sh stage-done kakkoidev/nest-demo-child --stage
   01-produce` and `icm.sh seal kakkoidev/nest-demo-child`.
3. **Finish**: write `output/parent-evidence.md` (this run's work product), then
   call `publish`. The gate now passes because the evidence exists.

## After Output (MANDATORY)
```bash
bash ~/.agents/skills/icm/runtime/icm.sh stage-done kakkoidev/nest-demo \
  --stage 01-delegate
```

## Outputs

| Artifact | Location | Format |
|----------|----------|--------|
| Parent evidence | output/parent-evidence.md | any non-empty content |
