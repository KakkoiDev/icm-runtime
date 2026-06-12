# Stage 01: Research

<!-- ICM-TOOLS expect="(search_web|web_search|WebSearch) (fetch_url|web_fetch|WebFetch)" -->

## Inputs
| Source | Location | Scope |
|--------|----------|-------|
| User query | Chat message | The topic to research |

## Process
1. Identify the topic from user input
2. Use the web search tool to find relevant sources (aim for 5-10 results)
3. Use the URL fetch tool to read the most important pages
4. Synthesize structured notes into the output file

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
