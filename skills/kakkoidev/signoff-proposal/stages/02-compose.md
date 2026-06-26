# Stage 02: Compose the proposal

<!-- ICM-TOOLS expect="(ReadMcpResourceTool|mcp__.*Notion.*)" -->

Turn the evidence into the two-layer proposal document, in Notion-flavored markdown,
ready to publish. Do not publish here.

## Inputs
| Source | Location | Scope |
|--------|----------|-------|
| Evidence | output/../01-gather/output/evidence.md | Numbers + source URLs + the decision |
| NFM spec | `notion://docs/enhanced-markdown-spec` | Read via ReadMcpResource BEFORE authoring |

## Process
1. Read the `notion://docs/enhanced-markdown-spec` MCP resource. Do not guess Notion syntax.
2. Compose `output/proposal.md` in Notion-flavored markdown, two layers split by `---`:
   - **Lead:** bold "For sign-off" line stating what happens once approved.
   - **Proposal** (`## Proposal`): Objective, Scope, Decision (+ one-line why-not for the
     rejected option), Target (concrete number anchored to baseline), Success definition,
     Ask. Manager-altitude only. No trace ids, query strings, or anti-pattern detail here.
   - `---`
   - **Basis / evidence** (`## Basis / evidence`):
     - One `mermaid` diagram of the single most important shape. Quote node labels with
       special chars; use `<br>` not a literal newline inside labels.
     - One data table using `<table header-row="true">` with `<tr>/<td>` rows (NEVER pipe tables).
     - `### Sources`: one bullet per claim, each `[label](url)` linking to the live source
       from evidence.md. Every headline number must be a clickable link.
3. Apply the escape + no-emoji rules from SKILL.md Conventions for all text outside code blocks.
4. Validate before finishing: (a) every figure in the evidence section has a clickable link;
   (b) no emojis; (c) the proposal layer carries no execution internals.

## After Output (MANDATORY)
```bash
bash ~/.agents/skills/icm/runtime/icm.sh stage-done kakkoidev/signoff-proposal \
  --stage 02-compose
```

## Outputs
| Artifact | Location | Format |
|----------|----------|--------|
| Proposal | output/proposal.md | Notion-flavored markdown: lead + Proposal + divider + Basis/evidence (diagram, table, linked Sources) |
