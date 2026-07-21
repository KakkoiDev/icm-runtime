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
job is the content judgement the script cannot make: making mermaid node labels quote-safe,
escaping stray literal special characters outside code fences, and laying out any bilingual prose
in two columns.

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
   ~/.agents/skills/kakkoidev/publish-to-notion/tools/render output/source.md > output/page.md
   ```
3. Review `output/page.md` for the content-level items the renderer does not judge: wrap
   mermaid node labels containing special characters (e.g. parentheses) in double quotes and
   use `<br>` not `\n` inside labels; escape stray literal special characters that appear
   OUTSIDE code fences. Read `notion://docs/enhanced-markdown-spec` via `ReadMcpResourceTool`
   if unsure of a construct. Also style inline code tokens: any variable/field/function/type name,
   keyword, or literal that appears in prose (e.g. `expenseLineId`, `undefined`) gets backticks;
   leave display labels and feature names (経費, 予実比較) plain. Edit `output/page.md` in place. Do
   NOT alter meaning or phrasing.
4. Readability spacing (default, not an option to ask about): in PROSE paragraphs that pack
   several distinct points, separate the logical segments with `<br><br>` (a double in-block
   break). An ordinary newline would split the paragraph into separate blocks; `<br><br>` keeps
   it ONE block with a blank line between segments, turning a dense wall of text into scannable
   groups. Apply ONLY to multi-point prose paragraphs. Do NOT add breaks inside single-point or
   short paragraphs, list items, `<table>` cells, code / ```mermaid fences, or headings. This is
   layout only - never change wording, order, or meaning.
5. Bilingual layout: if the content pairs the same text in two languages, wrap EACH pair in its
   OWN `<columns>` block - `<columns><column>` lang A `</column><column>` lang B `</column></columns>`,
   first language left, tab-indented children with REAL tabs. One block per pair is what keeps the
   two languages aligned: Notion anchors columns at the TOP of each `<columns>` block, so a single
   block that batches all of lang A into the left column and all of lang B into the right drifts out
   of alignment the moment two paired items differ in length. A separate block per pair re-anchors
   alignment at every row. For a report that is a set of labeled points (e.g. Issue / Cause /
   Impact), give each point its own block with a bold `**label**:` lead-in in both columns. Prefer
   per-pair `<columns>` over a two-column `<table>` for paired prose - the table aligns too, but
   columns are the native bilingual layout and read cleaner. This is the default, not an option to
   ask about. Leave diagrams, ```mermaid fences, code blocks, and `<table>` blocks FULL-WIDTH
   (outside any column); leave bilingual diagram labels (`JA<br>EN`) inline. Skip this step entirely
   for monolingual content.
6. Provenance callout (default, not an option to ask about): every page published through this
   skill is AI-authored, so stamp it. Make the FIRST block of `output/page.md` a callout with the
   robot icon and a gray background declaring AI authorship + human review:
   ```
   <callout icon="🤖" color="gray_bg">
   	この資料はAIが生成し、人間がレビューしています。
   	This document was AI-generated and reviewed by a human.
   </callout>
   ```
   Match the document's language(s): a bilingual doc gets both lines (the doc's first language
   first); a monolingual doc gets only the matching line. On CREATE, prepend it as the first block.
   On UPDATE, fetch the page first and add it ONLY if no such callout already exists at the top -
   never duplicate it, and never add it to a page that was not authored through this skill.
7. Cross-references and code examples (add what the source is missing - do not just pass content
   through):
   - Links: hyperlink EVERY page, ticket, document, PR, or spec the content names - not only
     internal Notion pages but EXTERNAL references too (Figma, GitHub, Slack, requirement/spec
     sites). Internal Notion page: `[reference text](notion-url)`, keeping the anchor the reader
     expects (e.g. keep the literal ticket id `SOBA-306` as the link text, not the page's long
     title - a bare `<mention-page>` chip swaps the visible text for the title, so prefer a text
     link when the id itself matters). External: `[label](url)`. A named reference left as plain
     text is a defect; if you do not have the URL, ask for it or flag it - never silently ship a
     bare mention.
   - Code examples: when the content explains how code behaves, include the relevant snippet in a
     fenced code block (```lang) with a `file:line` caption above it, so the reader - or an agent
     like Claude Code - can jump straight to the source. Quote code VERBATIM (re-read the file;
     never paraphrase or reconstruct from memory). Code blocks stay FULL-WIDTH - never inside a
     `<columns>` or `<table>` cell.
   - Captioning a FULL-WIDTH block bilingually (code, table, diagram): never cram `JA / EN` onto one
     line. Put the language-neutral label (a `file:line`, path, or figure number) on its own
     full-width line, then the bilingual explanation in its OWN per-pair `<columns>` block (JA left,
     EN right, real tabs), then the full-width block. The caption reads side by side; the block it
     labels stays full-width.
8. Write `output/target.md`: `mode` (create or update); for create, the parent (`page_id` or
   "none = private workspace page") and the title; for update, the existing `page_id`; and the
   `audience` (who must be able to read it).

## After Output (MANDATORY)
```bash
bash ~/.agents/skills/icm/runtime/icm.sh stage-done kakkoidev/publish-to-notion \
  --stage 01-render
```

## Outputs
| Artifact | Location | Format |
|----------|----------|--------|
| Source | output/source.md | The user's content verbatim, the renderer's input |
| Page body | output/page.md | Notion-flavored markdown body, send-ready (real newlines) |
| Target spec | output/target.md | mode (create/update), parent or existing page_id, title, audience |
