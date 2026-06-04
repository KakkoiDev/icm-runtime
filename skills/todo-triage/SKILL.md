---
name: todo-triage
description: >
  Pull the latest OKR/todo list from the user's Slack self-DM, enrich every
  linked ticket/PR/doc with real metadata, triage each item by effort,
  difficulty, and dual-lens impact (review-narrative value + OKR-criticality)
  into keep/delegate/drop verdicts, then publish a dated planning doc to private
  Notion. Use for delegation planning, performance-review prep, or recurring
  todo triage. 4 stages: ingest, enrich, triage, publish.
---

# Todo Triage

## Pipeline
Pull latest todo snapshot from Slack self-DM -> enrich linked items with real
metadata -> triage by effort / difficulty / dual-lens impact -> upsert into the
Task Triage DB + refresh the living plan page (private Notion).

## Commands
| Command | What it does |
|---------|-------------|
| `/todo-triage` | Start a new run - all stages |
| `/todo-triage run` | Continue latest run |
| `/todo-triage run stage <N>` | Re-run a specific stage |
| `/todo-triage diff` | Diff last two runs (what changed week-over-week) |
| `/todo-triage list` | Show run history |
| `/todo-triage clean` | Remove old completed runs (keeps latest 5) |

## Conventions
- All output is markdown. Read the full stage contract before executing.
- Load only what the Inputs table specifies.
- Effort estimates assume a MID-LEVEL engineer (junior ~1.5-2x, senior ~0.6x). State this in the output.
- Never invent deadlines: a ticket with no due date is "none set", not a guess.
- Reconcile: every distinct todo line in == exactly one row out (flag duplicates and umbrella/child links).
- Impact is scored on OKR-criticality, NOT task type. A bug fix on a weighted OKR's critical path is high-criticality.
- Output is the **Task Triage** Notion database (data source `d478903f-73eb-42a3-a670-83208fc4681f`), upserted by Link key - NOT a dated markdown page. Re-runs update rows in place; never duplicate rows or create dated pages. The strategic narrative lives on one living page that embeds the DB. Keep the OKR Delivery Tracker + Quarters scorecard (measurement layer) untouched.
- If a stage's output/ already exists from a previous run, ask: overwrite or skip?
- After all stages complete, summarize what was produced and surface the top 2-3 strategic calls.

## Runtime
This workspace uses the ICM runtime. Do not scaffold directories manually.
- **Never** create state directories, copy files, or format timestamps yourself.
- **Always** delegate filesystem operations to `icm.sh` via the bash tool:
  ```
  bash ~/.agents/skills/icm/runtime/icm.sh <command> todo-triage
  ```
- After `icm.sh init`, read the run path from stdout. Check stderr for gitignore warnings and inform the user.
- Each stage's contract is at `<run_path>/<stage>/CONTEXT.md`.
- After each stage, call `icm.sh next todo-triage` to find the next empty stage.
