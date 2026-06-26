# Stage 03: Telemetry, then seal (the run's finalization)

<!-- ICM-TOOLS expect="Bash" -->

Stages 01 and 02 each called `stage-done`, so THIS run now has honest per-stage token
telemetry from the live session transcript (unlike the throwaway sandbox in stage 02,
which has no transcript and reports estimated/zero counts). This stage shows that
telemetry, then closes and seals the run.

ORDER MATTERS HERE, and it teaches a real ICM rule: a stage cannot audit or seal
itself, because its own `stage-done` is not recorded until after its work. So the
telemetry view is this stage's body (before `stage-done`), and the audit + seal +
verify run as a POST-RUN finalization AFTER `stage-done 03-telemetry-seal` - exactly
where every ICM skill seals (see the Seal section in SKILL.md). Running audit inside
the stage would flag the stage as "not done yet" and seal a run missing its last
boundary.

## Inputs
| Source | Location | Scope |
|--------|----------|-------|
| Run telemetry | `<run>/telemetry/events.jsonl` | `stage_done` + `usage` events from stages 01-02 |
| Prior evidence | `<run>/01-lifecycle/output/`, `<run>/02-enforcement/output/` | indexed by the finalizer so the pipeline's data flow is visible |

## Process
1. BODY - from the PROJECT ROOT, recompute exact counts and show the four-field token
   accounting for the stages closed so far. `<run>` is the run path `icm.sh init`
   printed:
   ```bash
   ~/.agents/skills/kakkoidev/icm-demo/tools/show-telemetry > <run>/03-telemetry-seal/output/telemetry.md 2>&1
   ```
2. Close this stage:
   ```bash
   bash ~/.agents/skills/icm/runtime/icm.sh stage-done kakkoidev/icm-demo --stage 03-telemetry-seal
   ```
3. FINALIZE (post-run, AFTER step 2 - all stages are now closed). Run the finalizer; it
   audits (clean now, or one framed advisory-only deviation without the hook), seals,
   verifies, and indexes the stage 01-03 evidence:
   ```bash
   ~/.agents/skills/kakkoidev/icm-demo/tools/close-run
   ```
4. In your reply, state the outcome: did `verify-seal` print `SEAL OK`, and how many
   audit deviations (0 with the enforcement hook installed, or exactly 1 - the framed
   "advisory only" note - without it). Remind the user to commit `.icm-seals.log`
   (project root, outside the gitignored `.icm/`); do not commit it yourself.

## Outputs
| Artifact | Location | Format |
|----------|----------|--------|
| Telemetry view | output/telemetry.md | Deterministic `show-telemetry` capture: reify result + the per-stage four-field token accounting |
| Seal | `.icm-seals.log` (project root) | Tamper anchor written by the post-run `close-run`; the audit + SEAL OK confirmation is shown in your reply |
