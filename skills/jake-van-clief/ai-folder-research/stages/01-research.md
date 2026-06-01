# Stage 01: Research

## Inputs
| Source | Location | Scope |
|--------|----------|-------|
| User query | Chat message | The topic to research |

## Process
1. Identify the topic from user input
2. Use `search_web` to find relevant sources (aim for 5-10 results)
3. Use `fetch_url` to read the most important pages
4. Synthesize findings into structured notes

## Outputs
| Artifact | Location | Format |
|----------|----------|--------|
| Research notes | output/research-notes.md | Markdown: Summary, Key Findings (bulleted), Sources (with URLs) |
