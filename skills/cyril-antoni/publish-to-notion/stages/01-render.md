# Stage 01: Render to Notion-flavored markdown

<!-- No ICM-TOOLS / ICM-CALL: the syntax conversion is a deterministic bash script
     (tools/render), not a harness tool call. render is covered by eval/render.test.sh
     and the output (page.md) is the receipt; audit notes tools/render via prose scrape. -->

Take the content the user brings and produce a Notion-flavored markdown body that will render
correctly, plus a target spec saying where it goes and who must read it. This stage is pure
mechanics - do not change the meaning, argument, or wording of the content. Convert syntax
only.

The deterministic syntax conversion (GitHub pipe tables to Notion `<table>` blocks, code
fences left literal) is done by the `tools/render` script, NOT by hand. Your only remaining
job is the content judgement the script cannot make: making mermaid node labels quote-safe and
escaping stray literal special characters outside code fences.

## Inputs
| Source | Location | Scope |
|--------|----------|-------|
| Content | Chat message or a file path | The finished document to publish (markdown) |
| Target | Chat message | New page under a parent `page_id`, or an existing `page_id` to update |
| Audience | Chat message | Who must be able to read it (just me / a team / anyone at org) |

## Process
1. Write the user's content verbatim (unchanged markdown) to `output/source.md`.
2. Run the deterministic renderer - it rewrites GitHub pipe tables into Notion `<table>`
   blocks and passes everything else (headings, bold, lists, links, code, ```mermaid fences)
   through untouched:
   ```bash
   ~/.agents/skills/cyril-antoni/publish-to-notion/tools/render output/source.md > output/page.md
   ```
3. Review `output/page.md` for the content-level items the renderer does not judge: wrap
   mermaid node labels containing special characters (e.g. parentheses) in double quotes and
   use `<br>` not `\n` inside labels; escape stray literal special characters that appear
   OUTSIDE code fences. Read `notion://docs/enhanced-markdown-spec` via `ReadMcpResourceTool`
   if unsure of a construct. Edit `output/page.md` in place. Do NOT alter meaning or phrasing.
4. Write `output/target.md`: `mode` (create or update); for create, the parent (`page_id` or
   "none = private workspace page") and the title; for update, the existing `page_id`; and the
   `audience` (who must be able to read it).

## After Output (MANDATORY)
```bash
bash ~/.agents/skills/icm/runtime/icm.sh stage-done cyril-antoni/publish-to-notion \
  --stage 01-render
```

## Outputs
| Artifact | Location | Format |
|----------|----------|--------|
| Source | output/source.md | The user's content verbatim, the renderer's input |
| Page body | output/page.md | Notion-flavored markdown body, send-ready (real newlines) |
| Target spec | output/target.md | mode (create/update), parent or existing page_id, title, audience |
