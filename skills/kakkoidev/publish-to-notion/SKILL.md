---
name: publish-to-notion
description: >
  Publish a finished markdown document to Notion correctly and verifiably:
  convert it to Notion-flavored markdown, create or update the page, fetch it
  back to confirm every edit landed, and make sure sharing is set before handing
  back a link. Use when you already have the content and need it reliably
  published to Notion (a design doc, proposal, report, runbook). Does NOT
  research or draft - you bring the content. Triggers: "publish to Notion",
  "put this in Notion", "push this doc to Notion", "update the Notion page".
  3 stages: render, publish, verify-and-share.
---

# Publish to Notion

## Pipeline
Render the provided content into Notion-flavored markdown, then create or update the page
with the Notion MCP, then fetch the page back to verify every edit landed and confirm
sharing is set before returning a link.

## Commands
| Command | What it does |
|---------|-------------|
| `/publish-to-notion` | Start new run, all stages |
| `/publish-to-notion run` | Continue latest run |
| `/publish-to-notion run stage <N>` | Re-run specific stage |
| `/publish-to-notion diff` | Diff last two runs |
| `/publish-to-notion list` | Show run history |
| `/publish-to-notion clean` | Remove old completed runs (keeps latest 5) |

## What this skill is (and is not)
This is a mechanics skill. You bring finished content (a markdown body or a path to one) and
a target (a new page under a parent, or an existing `page_id`). The skill handles correct
Notion-flavored markdown, reliable writes, post-write verification, and the sharing gate.
It does NOT research, draft, or decide the content. If the content does not exist yet, write
it first (or use a drafting skill), then call this.

One deliberate exception, added 2026-09-08 on the captain's ruling: the skill DOES enforce
density. It will not publish prose where a bullet, table, or diagram carries the same facts.
That is a form change, not a content change - no fact is added, removed, or reinterpreted.
See "Density" below and stage 01-render step 3.

## Density (standing rule - the reader's attention is the scarce resource)
Captain's ruling, 2026-09-08: "The thing is to not make people waste time on prose. time and
attention are very limited." A published page is a reference, not an essay. These are hard rules,
not preferences:
- **Bullets and diagrams are the default. Prose is the exception.** Before writing a paragraph,
  ask whether it is a bullet list, a table, or a mermaid diagram instead. It usually is.
- **Every section that describes a flow, a branch, or a set of states gets a mermaid diagram.**
  A lifecycle, a decision, a state machine, a pipeline: diagram first, then the detail table.
- **No sentence that only restates the previous sentence.** Concluding restatements ("the
  conclusion is unchanged", "and both are legitimate", "stated plainly rather than hidden")
  are pure cost. Cut them.
- **No rhetorical framing.** Not "the one thing everyone gets wrong" (you do not know that),
  not "the worst cell on the board" as a section opener. State the fact, drop the flourish.
  Technical information, not poetry.
- **A bullet is one line.** If it needs two, it is two bullets or it belongs in a table cell.
- **Opening sections state what is live and what is not**, in bullets. Do not explain what the
  document is about at length; the title does that.
- Before publishing, re-read every paragraph and ask: does deleting this lose a fact? If not,
  delete it.

## Page width (standing rule)
Captain's ruling, 2026-09-08: "Published pages in 2 languages should be full width by default",
"all shared tables like this one with 2 languages should be full width by default."
- **Every `<table>` on a bilingual page gets `fit-page-width="true"` AND an explicit
  `<colgroup>`.** The attribute alone is stored but does NOT visually widen the table - verified
  2026-09-08 by comparing a table the captain widened by hand against two the skill had written:
  his carried a `<colgroup>` of explicit `<col width="...">`, the skill's did not, and only his
  rendered full width. The widths are what Notion actually honors.
  Total content width is ~1034px. Divide it by the column count and give every column that value:
  3 columns -> `344.6666666666667`, 4 -> `258.5`, 5 -> `206.8`. Write the `<colgroup>` as the first
  child of `<table>`, one `<col width="...">` per column.
### Two things that are MANUAL, permanently. Do not try to automate them.
Captain's ruling, 2026-09-08: "not need to try to force the full width with no clean non-hacky
way of doing it. just document in the skill that it has to be done manually. same for the mermaid
diagram previews." That is settled. Do not go looking for an undocumented route again.

- **Page-level full width.** No width field on `update-page`, no markdown attribute, and the
  fetched page does not report width either - so there is no way to tell a working undocumented
  property from a silently ignored one. Probed 2026-09-08 with a `full_width` property: accepted,
  unverifiable, abandoned by the captain's ruling.
  Manual step: page `...` menu, toggle "Full width".
- **Mermaid preview-only display.** Notion renders a mermaid block in split view (code beside
  preview) by default; the captain wants preview only. Probed 2026-09-08 with a code fence
  attribute list (`{preview="true" code_preview_format="preview"}`): silently STRIPPED, confirmed
  by fetching back a plain ```mermaid fence. It is a per-block UI toggle.
  Manual step: per diagram, switch the block's display to preview.

For both: list them in the verify receipt as outstanding manual steps for the human, never assert
they are set, and never block on them beyond saying they are outstanding.

## Notion authoring rules (read before any write)
- Reading review comments: `notion-get-comments` returns PAGE-LEVEL discussions only by default.
  Anchored comments (the normal case for feedback on a paragraph, heading, or table) need
  `include_all_blocks: true`, and closed threads need `include_resolved: true`. An empty result
  without those flags is NOT proof there are no comments - verified 2026-09-08, where the default
  call returned nothing while 7 threads existed.
- Read the `notion://docs/enhanced-markdown-spec` MCP resource via `ReadMcpResourceTool`
  BEFORE writing. Do not guess Notion-flavored markdown syntax.
- Inline code tokens: any variable/field/function/type name, keyword, or literal that appears in
  prose gets backticks (`expenseLineId`, `undefined`, `calcBalanceSummary`), matching how it reads
  in code. Leave display labels and feature names plain (e.g. 経費, 粗利, 予実比較) - they are UI
  terms, not identifiers.
- Cross-references + code examples: hyperlink EVERY page/ticket/document/PR/spec the content names -
  internal Notion pages AND external references (Figma, GitHub, Slack, spec sites) - via
  `[text](url)`; keep the literal reference (e.g. `SOBA-306`) as the anchor rather than a
  `<mention-page>` chip when the id itself matters. A named reference left as bare text is a defect.
  When the content explains code behavior, embed the relevant snippet VERBATIM in a fenced code
  block with a `file:line` caption so a reader (or Claude Code) can trace it; code blocks stay
  full-width. To caption a full-width block (code/table/diagram) bilingually, put the neutral label
  (`file:line`/path) on its own full-width line, then the JA/EN explanation in a per-pair
  `<columns>` block above the block - never `JA / EN` on one line. Details in stage 01-render step 7.
- Provenance callout: every page published through this skill is AI-authored, so the FIRST block
  states AI authorship + human review with the robot icon. On a bilingual page that is TWO
  callouts in ONE `<columns>` block (JA `この資料はAIが生成し、人間がレビューしています。` left,
  EN `This document was AI-generated and reviewed by a human.` right), both
  `<callout icon="🤖" color="gray_bg">`; a monolingual page gets one plain callout.
  Prepend on CREATE; on UPDATE add only if absent - never duplicate, never stamp a page not
  authored through this skill. Details in stage 01-render step 6.
- Tables use `<table>/<tr>/<td>`, NEVER pipe tables. Cells hold rich text only - use
  `**bold**`, not HTML tags.
- Mermaid goes in a ```mermaid code fence. Keep node labels quote-free where possible; if a
  label has special characters, double-quote it. Use `<br>` for line breaks in labels, never
  a literal newline. For a clear entry point use `flowchart LR` with a stadium `([...])`
  START node. `style`/color lines may not render in every Notion build - do not rely on them.
- Bilingual content (same text paired in two languages) ALWAYS uses a two-column layout for the
  paired PROSE: `<columns><column>` language A `</column><column>` language B `</column></columns>`,
  first language left. This is the default for bilingual docs, not an option to offer. Wrap EACH
  pair in its OWN `<columns>` block - Notion anchors columns at the TOP of each block, so one block
  batching all of language A left and all of language B right drifts out of alignment as soon as two
  paired items differ in length; a block per pair re-anchors alignment at every row. For labeled
  points (Issue / Cause / Impact ...), one block per point with a bold `**label**:` lead-in in both
  columns. Prefer per-pair `<columns>` over a two-column `<table>` for paired prose. Diagrams,
  code fences, and tables stay FULL-WIDTH - never nest them in a column (mermaid in a half-width
  column renders cramped and can fail to parse). Bilingual diagram labels (`JA<br>EN` inside a
  node) stay inline as-is. A bilingual CALLOUT splits the same way: ONE `<columns>` block holding
  TWO callouts, same icon and colour, language A left. NEVER stack both languages inside a single
  callout - a stacked bilingual callout is a defect, not a style choice (captain's standing rule,
  2026-09-14). The ONLY blocks that stay joined and full-width are ```mermaid fences, images,
  code fences, and `<table>` blocks. Monolingual content: no columns. Column children are tab-indented; pass
  REAL tabs, not `\t`.
- Wrap paths, globs, and code tokens in backticks. Bare `*` and `~` are markdown delimiters
  and will eat your text. Outside code blocks, escape: backslash asterisk tilde backtick
  dollar square-brackets angle-brackets braces pipe caret.
- Inside code fences, content is literal - do NOT escape, and write real newlines.

## Write reliability (these are not optional)
- In `content` / `new_str` / `content_updates`, pass REAL newlines and real indentation.
  Do NOT pass `\n` or `\t` escape sequences - they get taken literally and can collapse the
  page.
- `update_content` silently SKIPS any edit whose `old_str` does not EXACTLY match the page,
  and still returns success. Build every `old_str` from a FRESH `notion-fetch`, not from what
  you previously sent (Notion normalizes URLs and markers).
- After EVERY write (create or update), `notion-fetch` the page back and confirm each edit
  landed. No fetch, no "done".

## Sharing (the link is useless if no one can open it)
- A page created with no `parent` is a PRIVATE workspace page. A private-page link shared in
  Slack or elsewhere means the recipient gets "no access".
- There is no MCP permission API. Setting sharing is a MANUAL step the human does in the
  Notion UI (move to a teamspace, or Share -> "anyone at <org> can view").
- Do NOT hand back a link as shareable until the human confirms sharing is set. Record the
  confirmed sharing state in the verify receipt.
- Same shape for full width on a bilingual page: not settable through the API, so name it as an
  outstanding manual step in the receipt rather than claiming the page is done. See "Page width".

## Conventions
- Read the full stage contract before executing. Load only what the Inputs table specifies.
- If `output/` exists from a previous run of this stage, ask: overwrite or skip?
- Execute and close each stage in real time, in order: do the work, then call `stage-done`,
  then move on. Do NOT batch `stage-done` calls or back-fill outputs - closing stages in the
  same instant yields zero-width telemetry windows and null per-stage token counts.

## Runtime
This workspace uses the ICM runtime. Do not scaffold directories manually.
- **Never** create state directories, copy files, or format timestamps yourself.
- **Always** delegate filesystem operations to `icm.sh` via the bash tool:
  ```
  bash ~/.agents/skills/icm/runtime/icm.sh <command> kakkoidev/publish-to-notion
  ```
- After `icm.sh init`, read the run path from stdout. Check stderr for gitignore warnings and inform the user.
- Each stage's contract is at `<run_path>/<stage>/CONTEXT.md`.
- After each stage, call `icm.sh next kakkoidev/publish-to-notion` to find the next empty stage.

## Per-Stage Telemetry (MANDATORY)
After writing output for each stage, immediately call:
```
bash ~/.agents/skills/icm/runtime/icm.sh stage-done kakkoidev/publish-to-notion \
  --stage <stage-name>
```
After the full run, call `reify-telemetry` to fill in exact counts:
```
bash ~/.agents/skills/icm/runtime/icm.sh reify-telemetry kakkoidev/publish-to-notion
```
The audit command will flag stages that skip the marker.

## Audit
After a run completes, verify all steps were followed:
```
bash ~/.agents/skills/icm/runtime/icm.sh audit kakkoidev/publish-to-notion
```

## Seal
After audit, seal the run's evidence and tell the user to commit the log:
```
bash ~/.agents/skills/icm/runtime/icm.sh seal kakkoidev/publish-to-notion
```
Appends digests to `.icm-seals.log` at the project root. Suggest committing it; do not commit it yourself without being asked.
