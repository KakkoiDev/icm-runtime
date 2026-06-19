# Stage 02: Draft

## Inputs
| Source | Location | Scope |
|--------|----------|-------|
| Research notes | ../01-research/output/research-notes.md | Full file |

## Process
1. Read the research notes
2. Identify the narrative arc
3. Write a draft with: Introduction, Body (3-5 sections), Conclusion
4. Follow voice-rules if present (check for `../../_config/voice-rules.md` in the run dir)

## After Output (MANDATORY)
Call `stage-done` immediately after writing output:
```bash
bash ~/.agents/skills/icm/runtime/icm.sh stage-done jake-van-clief/ai-folder-research \
  --stage 02-draft
```

## Outputs
| Artifact | Location | Format |
|----------|----------|--------|
| Draft | output/draft.md | Markdown with heading hierarchy |
