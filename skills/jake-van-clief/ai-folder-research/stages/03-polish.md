# Stage 03: Polish

## Inputs
| Source | Location | Scope |
|--------|----------|-------|
| Draft | ../02-draft/output/draft.md | Full file |

## Process
1. Read the draft
2. Proofread: grammar, spelling, clarity
3. Format: consistent headings, proper link formatting, metadata header
4. Generate table of contents if document exceeds 3 sections
5. Save final output

## After Output (MANDATORY)
Call `stage-done` immediately after writing output:
```bash
bash ~/.agents/skills/icm/runtime/icm.sh stage-done jake-van-clief/ai-folder-research \
  --stage 03-polish --model <current-model> \
  --tokens-in <approx> --tokens-out <approx>
```

## Outputs
| Artifact | Location | Format |
|----------|----------|--------|
| Final | output/final.md | Polished markdown with metadata header |
