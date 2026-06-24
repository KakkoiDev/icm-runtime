# Stage 03: Telemetry, audit, and seal (on this real run)

<!-- ICM-TOOLS expect="Bash" -->

Stages 01 and 02 each called `stage-done`, so THIS real run now has honest per-stage
token telemetry snapshotted from the live session transcript (unlike the throwaway
sandbox in stage 02, which has no transcript and reports estimated/zero counts).
Close the run out: recompute exact counts, audit, seal, and verify.

## Inputs
| Source | Location | Scope |
|--------|----------|-------|
| Event stream | `<run>/telemetry/events.jsonl` | `stage_done` boundaries + `usage` events recorded by stages 01-02 |

## Process
1. `icm.sh reify-telemetry cyril-antoni/icm-demo` - recompute exact per-stage counts
   from the full transcript (appends `reify` events; last reify wins, so an earlier
   seal stays valid).
2. `icm.sh audit cyril-antoni/icm-demo` - capture the per-stage four-field token
   summary (`tokens_in` / `cache_creation` / `cache_read` / `tokens_out`, kept
   separate so cost is computable) and the tool-expectation report. Expect ONE
   deviation iff the enforcement hook is not installed: audit prints "GATES NOT
   ENFORCED ... gates were ADVISORY ONLY" and counts it. That is the runtime
   correctly reporting your setup, not a skill failure - it clears once you run
   `installer.sh --hooks` (then audit can see the recorded tool calls and match the
   ICM-TOOLS expectations). State plainly in the receipt whether hooks were on.
3. `icm.sh seal cyril-antoni/icm-demo`, then `icm.sh verify-seal cyril-antoni/icm-demo`
   (expect `SEAL OK`).
4. Write `output/telemetry-seal.md`: paste the real audit token summary and the
   `SEAL OK` line, then one line telling the user to commit `.icm-seals.log` (it lives
   at the project root, outside the gitignored `.icm/`). Do not commit it yourself.

## After Output (MANDATORY)
```bash
bash ~/.agents/skills/icm/runtime/icm.sh stage-done cyril-antoni/icm-demo --stage 03-telemetry-seal
```

## Outputs
| Artifact | Location | Format |
|----------|----------|--------|
| Telemetry + seal receipt | output/telemetry-seal.md | Real audit token summary, the SEAL OK line, and a commit reminder |
