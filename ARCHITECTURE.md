# Architecture

How the ICM runtime is built. For the conceptual pitch and exhaustive edge cases,
see [README.md](README.md); this doc is the implementer's map.

## The idea in one line

Folder structure is the agent architecture. Numbered markdown files are frozen
stage contracts; a timestamped run directory holds state; a single agent reads
the right file at the right moment. The runtime owns all state. The model is the
non-deterministic glue between deterministic checkpoints.

## Five layers

1. **Skill** - a namespaced workflow, `skills/<namespace>/<name>/`, defined by a
   `SKILL.md` plus `stages/`, optional `checks/`, `tools/`, and `eval/`.
2. **Stages** - numbered markdown files (`01-...`, `02-...`). At `init` each is
   frozen into the run as that stage's `CONTEXT.md` contract.
3. **Run** - a timestamped directory, `.icm/<ns>/<skill>/<YYYY-MM-DD_HH-MM-SS>/`,
   holding per-stage `output/` and `telemetry/`.
4. **Tracking** - the per-run event stream, the manifest, the derived global
   index, and the seal log.
5. **Enforcement** - a harness hook consulted on every tool call.

## Components

| Path | Role |
|---|---|
| `skills/icm/runtime/icm.sh` | The runtime. All commands: init, next, stage-done, reify-telemetry, audit, seal, verify-seal, gate-check, eval, new-skill, catalog. POSIX sh; must parse under bash 3.2. |
| `skills/icm/runtime/gate-hook.sh` | Claude Code adapter. A `PreToolUse` hook (matcher `.*`) that delegates to `icm.sh gate-check` and records tool names/args. |
| `skills/icm/runtime/icm-gate.ts` | pi adapter. A `tool_call` extension that blocks while `gate-check` denies. Same contract as the hook. |
| `installer.sh` | Symlinks (or copies) skills into `~/.agents/skills/` (pi/Codex, namespaced) and `~/.claude/skills/` (Claude Code, flattened). `--hooks` registers the enforcement adapters. |
| `tests/gate.test.sh` | Hermetic regression suite (sandboxes `$HOME`). CI on Linux + macOS. |

## Lifecycle (the happy path)

```
icm.sh init <ns>/<skill>
  -> freezes each stage's CONTEXT.md + checks/ + tools/
  -> writes .manifest (sha256 of every frozen file)
  -> writes telemetry/run.json (static header) + events.jsonl (run_init)

for each stage:
  agent reads <stage>/CONTEXT.md  ->  does work -> <stage>/output/
  icm.sh stage-done --stage <name>
    -> snapshots token usage from the session transcript
    -> appends usage events + a stage_done boundary to events.jsonl

icm.sh reify-telemetry   -> exact per-stage counts (reify events, last-wins)
icm.sh audit             -> stage_done present? expected tools seen? gates enforced?
icm.sh seal              -> sha256 of run.json + events.jsonl + .manifest -> .icm-seals.log
```

## Three cross-cutting subsystems

**Gates (enforcement).** A stage contract declares
`<!-- ICM-GATE tools="ERE" run="checker" -->`. On every tool call the harness
adapter calls `gate-check --tool <name>`, which: verifies the manifest, finds the
active stage (first with no `stage_done`), and if that stage's gate `tools=`
matches the tool name (raw or normalized), runs the checker. Non-zero = DENY.
Gates are scoped to the active stage so a later stage cannot deadlock an earlier
one. Tool names are normalized (strip `mcp__<server>__`, fold built-in aliases)
so one canonical pattern matches Claude Code, pi, and Codex.

**Telemetry.** `events.jsonl` is the per-run source of truth: an append-only
stream of `run_init`, `usage`, `stage_done`, and `reify` events. Each carries
four token fields (`tokens_in` = new input, `cache_creation`, `cache_read`,
`tokens_out`), read from the session transcript - never passed by the model.
`skill-runs.jsonl` (global) and `.icm-seals.log` are derived from it; nothing
joins across files at read time.

**Seals (tamper-evidence).** Two independent layers: the `.manifest` catches
edits to frozen contracts/checkers/tools (gate-check DENIES "contract tampered");
the seal catches edits to the recorded evidence (`verify-seal` shows MISMATCH).
This is evidence, not prevention - the threat model is a negligent agent, not a
malicious one. Committing `.icm/` (or at least `.icm-seals.log`) makes edits
visible in git history.

## Authoring a skill

`icm.sh new-skill <ns>/<name> --stages a,b,c` scaffolds a `SKILL.md`, one stub
per stage, a `tools/` dir, and an `eval/`. Fill in each stage's Inputs/Process,
declare `ICM-TOOLS`/`ICM-GATE`/`ICM-CALL` where verification matters, and put
deterministic logic in `tools/` (frozen and manifest-covered). See
[CONTRIBUTING.md](CONTRIBUTING.md) and `skills/kakkoidev/icm-demo/` (the canonical
annotated template).
