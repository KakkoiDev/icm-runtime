# Stage 01: Render to Notion-flavored markdown

<!-- ICM-TOOLS expect="(ReadMcpResourceTool|Read)" -->

Take the content the user brings and produce a Notion-flavored markdown body that will render
correctly, plus a target spec saying where it goes and who must read it. This stage is pure
mechanics - do not change the meaning, argument, or wording of the content. Convert syntax
only.

Read the `notion://docs/enhanced-markdown-spec` MCP resource first. Then apply the authoring
rules from SKILL.md: tables become `<table>` blocks, mermaid goes in fences with quote-free
or double-quoted labels, paths and code tokens get backticks, special characters outside code
fences get escaped, and code-fence content stays literal with real newlines.

## Inputs
| Source | Location | Scope |
|--------|----------|-------|
| Content | Chat message or a file path | The finished document to publish (markdown) |
| Target | Chat message | New page under a parent `page_id`, or an existing `page_id` to update |
| Audience | Chat message | Who must be able to read it (just me / a team / anyone at org) |

## Process
1. Read the `notion://docs/enhanced-markdown-spec` resource via `ReadMcpResourceTool`.
2. Convert the content to Notion-flavored markdown: pipe tables to `<table>/<tr>/<td>` (rich
   text cells, `**bold**` not HTML); fence every mermaid block and make labels quote-safe;
   backtick paths/globs/code tokens; escape stray special characters outside code fences.
   Do NOT alter the content's meaning or phrasing.
3. Write `output/page.md`: the Notion-flavored markdown body, exactly as it will be sent
   (real newlines, real indentation, no `\n` or `\t` escape text).
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
| Page body | output/page.md | Notion-flavored markdown body, send-ready (real newlines) |
| Target spec | output/target.md | mode (create/update), parent or existing page_id, title, audience |
