# Stage 01: Lifecycle and tracking artifacts

<!-- ICM-TOOLS expect="(Read|Write|Bash)" -->

Show what `icm.sh init` already did for THIS run, and what tracks it. This stage
reads its own frozen contract and the run's telemetry, then writes a short tour of
the run lifecycle and the artifacts the runtime maintains. It is the "what just
happened" stage: no gate, pure narration backed by real files on disk.

The single machine comment above is a TEMPLATE construct: `ICM-TOOLS expect="..."`
declares (as an unanchored ERE) the harness tools this stage is expected to use, so
`icm.sh audit` can check the recorded tool calls in this stage's window against it.

## Inputs
| Source | Location | Scope |
|--------|----------|-------|
| This contract | `<run>/01-lifecycle/CONTEXT.md` | The frozen stage contract you are reading now |
| Run header | `<run>/telemetry/run.json` | workspace, run_id, stages, cwd, caller |
| Event stream | `<run>/telemetry/events.jsonl` | The append-only source of truth (so far: `run_init`) |

## Process
1. Run `icm.sh stages cyril-antoni/icm-demo` and `icm.sh next cyril-antoni/icm-demo`
   to show the stage order and which stage is next.
2. Read this run's `telemetry/run.json` and `telemetry/events.jsonl` (paths above).
3. Write `output/lifecycle.md`: a short tour covering (a) what `init` froze for this
   run (each stage's `CONTEXT.md` plus the skill's `checks/` and `tools/`, all hashed
   into a sha256 `.manifest`), and (b) the five things that track a run, one line
   each: `run.json` (static sealed header), `events.jsonl` (per-run source of truth),
   `.manifest` (frozen-file hashes), `.icm/telemetry/tool-calls.jsonl` (every icm.sh
   call in this project), `.icm-seals.log` (committable tamper anchor). Quote this
   run's real `run_id` and stage list, read from `run.json`.

## After Output (MANDATORY)
```bash
bash ~/.agents/skills/icm/runtime/icm.sh stage-done cyril-antoni/icm-demo --stage 01-lifecycle
```

## Outputs
| Artifact | Location | Format |
|----------|----------|--------|
| Lifecycle tour | output/lifecycle.md | Short markdown: what init froze + the 5 tracking artifacts, with this run's real values |
