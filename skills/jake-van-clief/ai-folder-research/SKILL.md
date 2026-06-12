---
name: ai-folder-research
description: >
  Research any topic using web search, draft a structured analysis,
  and polish into publication-ready markdown. Use for research tasks,
  article drafting, competitive analysis, or summarizing papers.
  3 stages: research, draft, polish.
---

# AI Folder Research

## Pipeline
Research a topic → draft analysis → polish into final output.

## Commands
| Command | What it does |
|---------|-------------|
| `/ai-folder-research` | Start new run — all stages |
| `/ai-folder-research run` | Continue latest run |
| `/ai-folder-research run stage <N>` | Re-run specific stage |
| `/ai-folder-research diff` | Diff last two runs |
| `/ai-folder-research list` | Show run history |
| `/ai-folder-research clean` | Remove old completed runs (keeps latest 5) |
| `/ai-folder-research clean --keep 3` | Keep only 3 most recent |

## Conventions
- All output is markdown. Log every tool call in the output file as a `{TOOL}` block.
- Read the full stage contract before executing.
- Load only what the Inputs table specifies.
- If output/ exists from a previous run of this stage, ask: overwrite or skip?
- After all stages complete, summarize what was produced.

## Runtime
This workspace uses the ICM runtime. Do not scaffold directories manually.
- **Never** create state directories, copy files, or format timestamps yourself.
- **Always** delegate filesystem operations to `icm.sh` via the bash tool:
  ```
  bash ~/.agents/skills/icm/runtime/icm.sh <command> jake-van-clief/ai-folder-research
  ```
- After `icm.sh init`, read the run path from stdout. Check stderr for gitignore warnings and inform the user.
- Each stage's contract is at `<run_path>/<stage>/CONTEXT.md`.
- After each stage, call `icm.sh next jake-van-clief/ai-folder-research` to find the next empty stage.

## Per-Stage Telemetry (MANDATORY)

After writing output for each stage, immediately call:
```
bash ~/.agents/skills/icm/runtime/icm.sh stage-done jake-van-clief/ai-folder-research \
  --stage <stage-name> --model <current-model>
```

Token counts are OPTIONAL — the model cannot access them mid-session.
After the full run, call `reify-telemetry` to fill in exact counts:
```
bash ~/.agents/skills/icm/runtime/icm.sh reify-telemetry jake-van-clief/ai-folder-research
```

This is MANDATORY. The audit command will flag stages that skip the marker.

## Run Telemetry

After all stages complete, call:
```
bash ~/.agents/skills/icm/runtime/icm.sh telemetry jake-van-clief/ai-folder-research \
  --model <current-model> --tokens-in <total-tokens-in> --tokens-out <total-tokens-out> --cost <amount>
```

## Audit

After a run completes, verify all steps were followed:
```
bash ~/.agents/skills/icm/runtime/icm.sh audit jake-van-clief/ai-folder-research
```
