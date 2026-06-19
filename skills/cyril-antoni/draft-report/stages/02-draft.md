# Stage 02: Draft

<!-- ICM-TOOLS expect="(Read|Write)" -->

Write the report in the house style, at the altitude fixed in stage 01. Do not re-decide scope
here; serve the frame.

## Inputs
| Source | Location | Scope |
|--------|----------|-------|
| Frame | ../01-frame/output/frame.md | decision, altitude, thesis, idea-disposition, names policy |
| Material | Chat or file/path | the substance to render |

## Process
Write `output/report.md` in this order, cutting anything the altitude does not justify:
1. The one-line thesis from the frame, first.
2. A no-context intro line for a reader who was not in the discussion.
3. The gist: the core points, briefly. At a 10-second altitude this may be the whole report.
4. Only if the altitude allows, the concrete layer: examples, one table, one diagram. At most one
   diagram per idea - `flowchart LR`, a stadium `([...])` START node, quote-free labels.
5. One ground-rule callout for the single non-negotiable, if there is one. Only one.
6. The idea-disposition (keep / replace / defer) so each contributor is addressed, honoring the
   names policy.
Style: terse, no filler, honest (say "approach" not "working solution" when nothing is built),
no em dashes.

## After Output (MANDATORY)
```bash
bash ~/.agents/skills/icm/runtime/icm.sh stage-done cyril-antoni/draft-report \
  --stage 02-draft
```

## Outputs
| Artifact | Location | Format |
|----------|----------|--------|
| Report draft | output/report.md | the report in house style, destination-agnostic markdown |
