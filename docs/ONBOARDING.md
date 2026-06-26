# Onboarding: how the ICM runtime works

For anyone new to this repo (or the author, six months from now). It teaches the
system as one end-to-end story. For the component map see
[ARCHITECTURE.md](../ARCHITECTURE.md); for exhaustive mechanics see
[REFERENCE.md](REFERENCE.md). Read this first.

## The one idea

A normal coding agent is one blob: the model decides everything and you trust it
did what you asked. ICM splits that into **deterministic checkpoints with a model
in the gaps**. The runtime (`icm.sh`) owns all the state and all the decisions;
the model only does the fuzzy work inside each stage. Everything the model does
is recorded, gated, and sealed, so afterwards you can prove what happened.

## The moving pieces

- **`skills/icm/runtime/icm.sh`** - the runtime. One POSIX shell script; every
  command (init, stage-done, gate-check, audit, seal) lives here.
- **`gate-hook.sh`** (Claude Code) / **`icm-gate.ts`** (pi) - the enforcement
  adapters. They run *inside the harness*, call `icm.sh gate-check`, and can block
  a tool call before it executes.
- **A skill** - a folder `skills/<namespace>/<name>/` containing:
  - `SKILL.md` - metadata + how the agent should drive it
  - `stages/NN-*.md` - the numbered stage contracts
  - `checks/*.sh` - gate checkers (optional)
  - `tools/*.sh` - deterministic stage scripts (optional)
  - `eval/*.test.sh` - offline tests (optional)

## A run, start to finish

**0. Install.** `installer.sh` symlinks skills into `~/.agents/skills/` (pi/Codex)
and `~/.claude/skills/` (Claude Code). `--hooks` registers the enforcement
adapters. Without `--hooks`, gates are *advisory* - declared but not enforced
(that is the "NOT REGISTERED / advisory only" note `audit` prints).

**1. Invoke** `/icm-demo`. The skill's `SKILL.md` tells the agent: drive
everything through `icm.sh`; never create directories or format timestamps
yourself.

**2. `icm.sh init kakkoidev/icm-demo`** creates a timestamped run and freezes the
contract. After init the run dir looks like:

```
.icm/kakkoidev/icm-demo/2026-06-26_02-30-20/
  .manifest                 # sha256 of every frozen file (tamper anchor)
  telemetry/
    run.json                # static header: workspace, run_id, created, stages, cwd
    events.jsonl            # append-only event stream; starts with run_init
  01-lifecycle/
    CONTEXT.md              # frozen copy of stages/01-lifecycle.md (the contract)
    output/                 # the agent writes here
  02-enforcement/  CONTEXT.md  output/
  03-telemetry-seal/ CONTEXT.md output/
```

The stage `.md` files are **frozen** into the run as `CONTEXT.md`. The agent reads
the frozen copy, not the source, so it cannot silently rewrite its own contract.

**3. The stage loop** (this is where the model works). For each stage:
- read the active stage's `CONTEXT.md`
- do the work: call tools, write files into `<stage>/output/`
- **`icm.sh stage-done --stage NN`** - closes the stage. It reads token usage
  *from the session transcript* (not from the model) and appends `usage` events +
  a `stage_done` boundary to `events.jsonl`. One stage's output is the next
  stage's input.

**4. Gates run on a parallel track** - on *every* tool call, not just at stage
boundaries:
- harness is about to run a tool -> `gate-hook.sh` fires -> calls
  `icm.sh gate-check --tool <name>`
- `check_run()` (`skills/icm/runtime/icm.sh:361`) decides: is the `.manifest`
  intact? is this the run's active stage? does the tool name match the active
  stage's `tools=` regex? does the `run=` checker pass? Any failure prints a
  `DENY` line; silence means allow.
- the hook turns a `DENY` into `permissionDecision: deny`, so the harness never
  executes the tool. The model gets the reason back and decides what to do
  (usually: satisfy the precondition, then retry the call).

**5. Close out the run.**
- `icm.sh reify-telemetry` recomputes exact per-stage token counts (appends
  `reify` events; nothing is rewritten, so an earlier seal stays valid).
- `icm.sh audit` checks: every stage has a `stage_done`? expected tools were
  called? gates enforced or only advisory? Prints a deviation report.
- `icm.sh seal` writes a sha256 digest of `run.json + events.jsonl + .manifest`
  to `.icm-seals.log` at the project root (commit that file).

## Four mechanisms, kept separate

These are easy to conflate. They are different things:

| Mechanism | Where | What it does |
|---|---|---|
| **Decision** | `check_run()` in `icm.sh` | Pure logic. Prints `DENY` or nothing. Knows nothing about the harness. |
| **Enforcement** | `gate-hook.sh` / `icm-gate.ts`, *outside the model* | Applies the decision - actually blocks the tool call. |
| **Telemetry** | `events.jsonl` (per run) | Source of truth. Counts read from the transcript, so the model cannot fake cost. |
| **Tamper-evidence** | `.manifest` + `.icm-seals.log` | Two layers: manifest catches edits to frozen contracts; seal catches edits to recorded evidence. Evidence, not prevention. |

A useful detail: a *genuine* `DENY` fails closed (blocks), but if `icm.sh` itself
*crashes*, the hook fails **open** (allows, with a warning) so one bug behind the
`.*` matcher cannot trap a whole session. "Checker says no" and "checker is
broken" are deliberately different outcomes.

## The demo vs a real run

- **`tools/sandbox-tour`** (the command in the deck) calls `icm.sh gate-check`
  **directly** - no hook, no model. It builds a throwaway run in a temp dir, shows
  DENY/ALLOW/seal/tamper, and deletes the temp dir on exit. It proves the
  *decision logic* is real. It does **not** show enforcement, a model reacting, or
  a real workflow. Nothing persists. Note the gate it exercises names a
  **fabricated tool, `demo_publish`, that nothing ever calls** - so in a live run
  the gate is inert; the tour triggers it by hand with `gate-check --tool
  demo_publish`. To see a gate fire on a *real* call, look at
  `kakkoidev/publish-to-notion` (its stage 03 gates `notion-fetch` on a real
  publish receipt).
- **A real `/icm-demo` run** persists under `.icm/...`, goes through the hook (if
  `--hooks` is installed), and a model drives the stages. That is where all four
  mechanisms play together. Stage 01 runs `tools/run-report`, which prints the
  actual artifacts so you can point at them.

## Where to go next

- [README.md](../README.md) - the elevator pitch and quick start.
- [ARCHITECTURE.md](../ARCHITECTURE.md) - the five layers and component map.
- [REFERENCE.md](REFERENCE.md) - every gate/telemetry/seal/edge-case detail.
- [CONTRIBUTING.md](../CONTRIBUTING.md) - add a skill, run the tests, build the deck.
- `skills/kakkoidev/icm-demo/` - the annotated, runnable reference skill. Read its
  `SKILL.md` and stage contracts alongside this doc.
