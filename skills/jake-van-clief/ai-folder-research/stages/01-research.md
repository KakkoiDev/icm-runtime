# Stage 01: Research

## Inputs
| Source | Location | Scope |
|--------|----------|-------|
| User query | Chat message | The topic to research |

## Process
1. Identify the topic from user input
2. Call `tools/search.sh "<query>"` to find relevant sources (aim for 5-10 results)
3. Use `search_web` to find relevant sources (aim for 5-10 results)
4. Use `fetch_url` to read the most important pages
5. Call `tools/synthesize.sh <stage_dir>` to produce structured notes

## After Output (MANDATORY)
Call `stage-done` immediately after writing output:
```bash
bash ~/.agents/skills/icm/runtime/icm.sh stage-done jake-van-clief/ai-folder-research \
  --stage 01-research --model <current-model> \
  --tokens-in <approx> --tokens-out <approx>
```

## Outputs
| Artifact | Location | Format |
|----------|----------|--------|
| Research notes | output/research-notes.md | Markdown: Summary, Key Findings (bulleted), Sources (with URLs) |
