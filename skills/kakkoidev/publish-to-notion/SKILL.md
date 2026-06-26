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

## Notion authoring rules (read before any write)
- Read the `notion://docs/enhanced-markdown-spec` MCP resource via `ReadMcpResourceTool`
  BEFORE writing. Do not guess Notion-flavored markdown syntax.
- Tables use `<table>/<tr>/<td>`, NEVER pipe tables. Cells hold rich text only - use
  `**bold**`, not HTML tags.
- Mermaid goes in a ```mermaid code fence. Keep node labels quote-free where possible; if a
  label has special characters, double-quote it. Use `<br>` for line breaks in labels, never
  a literal newline. For a clear entry point use `flowchart LR` with a stadium `([...])`
  START node. `style`/color lines may not render in every Notion build - do not rely on them.
- Bilingual content (same text paired in two languages) ALWAYS uses a two-column layout for the
  paired PROSE: `<columns><column>` language A `</column><column>` language B `</column></columns>`,
  first language left. This is the default for bilingual docs, not an option to offer. Diagrams,
  code fences, and tables stay FULL-WIDTH - never nest them in a column (mermaid in a half-width
  column renders cramped and can fail to parse). Bilingual diagram labels (`JA<br>EN` inside a
  node) stay inline as-is. Monolingual content: no columns. Column children are tab-indented; pass
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
