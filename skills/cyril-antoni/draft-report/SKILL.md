---
name: draft-report
description: >
  Shape existing substance (analysis, notes, a Slack thread, raw findings) into a
  short, actionable stakeholder report in a specific house style: lead with one
  thesis, a no-context intro, gist before detail, at most one diagram, a ground
  rule for the single non-negotiable, every input idea mapped to keep/replace/defer,
  and honest claims. Use when you have the material and need a crisp report a busy
  reader gets in seconds (a design proposal, decision brief, recommendation). Does
  NOT research (use a research skill) and does NOT publish (hand off to a publish
  skill). Triggers: "draft a report", "write this up", "turn this into a short
  doc", "make a gist of this". 3 stages: frame, draft, tighten.
---

# Draft Report

## Pipeline
Frame the report (audience, altitude, one thesis), draft it in the house style, then tighten
it to length and honesty. Output is destination-agnostic markdown - hand it to a publish
skill or paste it where it goes.

## Commands
| Command | What it does |
|---------|-------------|
| `/draft-report` | Start new run, all stages |
| `/draft-report run` | Continue latest run |
| `/draft-report run stage <N>` | Re-run specific stage |
| `/draft-report diff` | Diff last two runs |
| `/draft-report list` | Show run history |
| `/draft-report clean` | Remove old completed runs (keeps latest 5) |

## What this skill is (and is not)
This shapes substance into a report. You bring the material (analysis, notes, a thread, a set
of findings). It does NOT research (use `jake-van-clief/ai-folder-research` upstream) and does
NOT publish (hand the output to `cyril-antoni/publish-to-notion` or paste it). One run produces
one canonical report; if you need it in two places (e.g. a long-form doc and a chat TL;DR),
adapt per destination in stage 03 - do not re-derive the substance.

## House style (the point of this skill)
- **Decide audience and altitude FIRST.** State the target read-time (e.g. "10 seconds",
  "2 minutes", "full spec") and the single decision the reader must walk away with. Most
  rewrite-thrash comes from not deciding this up front. Everything below serves the altitude.
- **Lead with one thesis line.** The reframe or recommendation, in one sentence, before
  anything else.
- **Then a no-context intro line** for a cold reader who was not in the discussion.
- **Gist before detail.** Concrete examples, tables, and code come AFTER the gist lands, never
  before. At a 10-second altitude, they may not appear at all.
- **At most one diagram per idea.** If used: `flowchart LR`, a stadium `([...])` START node so
  the entry is unmissable, quote-free labels. A second diagram must earn its place.
- **One ground-rule callout** for the single non-negotiable. Not three. One.
- **Map every input idea to keep / replace / defer**, so each contributor sees their idea
  addressed. Decide names-in vs names-out with the requester before anything leaves a private
  draft - replacing or deferring a named person's idea in a broadcast reads as a callout.
- **Honest claims.** Say "approach" or "on the way to", not "working solution", when nothing
  is built. State what the report does NOT cover. Flag overclaims rather than smoothing them.
- **Terse.** No filler, no throat-clearing, no encouragement closers. No em dashes - use
  regular dashes, periods, or restructure.

## Conventions
- Read the full stage contract before executing. Load only what the Inputs table specifies.
- If `output/` exists from a previous run of this stage, ask: overwrite or skip?
- Execute and close each stage in real time, in order: do the work, then call `stage-done`,
  then move on. Do NOT batch `stage-done` calls.

## Runtime
This workspace uses the ICM runtime. Do not scaffold directories manually.
- **Never** create state directories, copy files, or format timestamps yourself.
- **Always** delegate filesystem operations to `icm.sh` via the bash tool:
  ```
  bash ~/.agents/skills/icm/runtime/icm.sh <command> cyril-antoni/draft-report
  ```
- After `icm.sh init`, read the run path from stdout. Check stderr for gitignore warnings and inform the user.
- Each stage's contract is at `<run_path>/<stage>/CONTEXT.md`.
- After each stage, call `icm.sh next cyril-antoni/draft-report` to find the next empty stage.

## Per-Stage Telemetry (MANDATORY)
After writing output for each stage, immediately call:
```
bash ~/.agents/skills/icm/runtime/icm.sh stage-done cyril-antoni/draft-report \
  --stage <stage-name>
```
After the full run, call `reify-telemetry` to fill in exact counts:
```
bash ~/.agents/skills/icm/runtime/icm.sh reify-telemetry cyril-antoni/draft-report
```
The audit command will flag stages that skip the marker.

## Audit
After a run completes, verify all steps were followed:
```
bash ~/.agents/skills/icm/runtime/icm.sh audit cyril-antoni/draft-report
```

## Seal
After audit, seal the run's evidence and tell the user to commit the log:
```
bash ~/.agents/skills/icm/runtime/icm.sh seal cyril-antoni/draft-report
```
Appends digests to `.icm-seals.log` at the project root. Suggest committing it; do not commit it yourself without being asked.
