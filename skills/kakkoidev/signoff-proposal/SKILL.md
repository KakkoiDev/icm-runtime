---
name: signoff-proposal
description: >
  Build an evidence-backed decision proposal for manager sign-off and publish it
  as a Notion sub-page under a ticket. Format: a minimal manager-altitude proposal
  (objective, scope, decision, target, success definition, ask) on top, then a
  divider, then a Basis/evidence section with one diagram, one data table, and a
  Sources list where every number links to the source data. Use when a decision
  needs sign-off before work proceeds and the case rests on real metrics.
  3 stages: gather, compose, publish.
---

# Sign-off Proposal

## Pipeline
Gather evidence (real numbers + clickable source links) then compose the proposal in
Notion-flavored markdown then publish as a Notion sub-page under the ticket and verify.

## Commands
| Command | What it does |
|---------|-------------|
| `/signoff-proposal` | Start new run, all stages |
| `/signoff-proposal run` | Continue latest run |
| `/signoff-proposal run stage <N>` | Re-run specific stage |
| `/signoff-proposal diff` | Diff last two runs |
| `/signoff-proposal list` | Show run history |
| `/signoff-proposal clean` | Remove old completed runs (keeps latest 5) |

## The format (what makes this proposal good)
A reviewer (manager) should get the decision in 30 seconds and be able to drill to
the proof in one click. Two layers, separated by a `---` divider:

1. **Proposal (manager-altitude, minimal).** A bold "For sign-off" lead line, then:
   - **Objective**: one sentence, the outcome.
   - **Scope**: exactly what is measured or changed (e.g. one endpoint, one service).
   - **Decision**: the choice being made, plus a one-line why-not for the rejected option.
   - **Target**: a concrete number anchored to the baseline.
   - **Success definition**: the bar this will be judged against.
   - **Ask**: the explicit approval requested.
   Keep investigation internals OUT of this layer. No trace ids, no query strings, no anti-pattern detail.

2. **Basis / evidence (one click down).** Below the divider:
   - **One diagram**: a mermaid chart that shows the single most important shape (e.g. where latency goes). Not two; one.
   - **One data table**: the baseline or distribution the target is anchored to.
   - **Sources**: a bullet per claim, each `[label](url)` linking to the live source (dashboard query, trace, report row). Every headline number must be a clickable link.

## Conventions
- Manager proposal stays minimal; evidence carries the proof. If a line is execution
  detail, it belongs in evidence or the repo, not the proposal.
- Every figure in the evidence section links to its source. An unlinked number is a defect.
- Notion authoring: read the `notion://docs/enhanced-markdown-spec` MCP resource BEFORE
  writing. Tables use `<table>/<tr>/<td>` (never pipe tables). Mermaid node labels with
  special chars must be double-quoted; use `<br>` not a literal newline. Outside code blocks, escape
  these characters: backslash asterisk tilde backtick dollar brackets angle-brackets braces pipe caret. NEVER use emojis.
- After EVERY Notion write (create or update), fetch the page back and confirm each edit
  landed. Notion silently drops edits whose `old_str` does not match and still returns success.
- Source links built with fixed `start`/`end` timestamps are point-in-time snapshots, not
  rolling windows. State this to the user; for always-current, link a saved view instead.
- Read the full stage contract before executing. Load only what the Inputs table specifies.
- If `output/` exists from a previous run of this stage, ask: overwrite or skip?
- Execute and close each stage in real time, in order: do the work, then call `stage-done`,
  then move on. Do NOT batch `stage-done` calls or back-fill copied outputs - closing stages
  in the same instant yields zero-width telemetry windows and null per-stage token counts.

## Runtime
This workspace uses the ICM runtime. Do not scaffold directories manually.
- **Never** create state directories, copy files, or format timestamps yourself.
- **Always** delegate filesystem operations to `icm.sh` via the bash tool:
  ```
  bash ~/.agents/skills/icm/runtime/icm.sh <command> kakkoidev/signoff-proposal
  ```
- After `icm.sh init`, read the run path from stdout. Check stderr for gitignore warnings and inform the user.
- Each stage's contract is at `<run_path>/<stage>/CONTEXT.md`.
- After each stage, call `icm.sh next kakkoidev/signoff-proposal` to find the next empty stage.

## Per-Stage Telemetry (MANDATORY)
After writing output for each stage, immediately call:
```
bash ~/.agents/skills/icm/runtime/icm.sh stage-done kakkoidev/signoff-proposal \
  --stage <stage-name>
```
After the full run, call `reify-telemetry` to fill in exact counts:
```
bash ~/.agents/skills/icm/runtime/icm.sh reify-telemetry kakkoidev/signoff-proposal
```
The audit command will flag stages that skip the marker.

## Audit
After a run completes, verify all steps were followed:
```
bash ~/.agents/skills/icm/runtime/icm.sh audit kakkoidev/signoff-proposal
```

## Seal
After audit, seal the run's evidence and tell the user to commit the log:
```
bash ~/.agents/skills/icm/runtime/icm.sh seal kakkoidev/signoff-proposal
```
Appends digests to `.icm-seals.log` at the project root. Suggest committing it; do not commit it yourself without being asked.
