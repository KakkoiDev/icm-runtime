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

### How trustworthy are the token counts?

Two separate questions:

- **The numbers are authoritative.** They are the API's own `usage` fields
  (`input_tokens`, `cache_creation_input_tokens`, `cache_read_input_tokens`,
  `output_tokens`), read straight from the session transcript - the same numbers you
  are billed, never self-reported by the model. Claude Code logs each message several
  times as it streams, so the runtime dedupes by `message.id` (keep last) or counts
  would inflate 2-3x.
- **Per-stage attribution is best-effort, and flagged when uncertain.** A stage's
  counts are the usage events in its time window. Three things can skew that split,
  all surfaced: a wrong session (no deterministic transcript -> newest-session guess;
  the chosen `transcript_source` is recorded and `audit` flags a guess), zero-width
  windows (two stages closed in the same second -> null counts; close stages in real
  time), and no transcript (sandbox runs record `counts: estimated`, null fields).

So: trust the totals; check `transcript_source` before trusting a per-stage split.
`reify-telemetry` is the post-run pass that recomputes each stage's window from the
now-complete transcript and appends `reify` events - it never rewrites the original
`stage_done`, so an earlier seal stays valid.

## Three things people call "the demo"

- **`kakkoidev/gate-demo`** - the minimal, talk-sized demo: one stage, one gate.
  `init`, then `gate-check --tool publish` DENIES (no `receipt.md`); create the
  file; `gate-check` ALLOWS. Files persist in `.icm/`, so the precondition is
  visible. This is the clean one to show live.
- **`kakkoidev/icm-demo`'s `tools/sandbox-tour`** - the comprehensive offline
  self-test. Calls `icm.sh gate-check` directly (no hook, no model), in a temp dir
  it deletes on exit, exercising scoping, normalization, seal, and manifest-tamper
  in one shot. It proves the *decision logic* is real, but is too much for a live
  demo. The gate it pokes names a **fabricated tool, `demo_publish`, that nothing
  ever calls** - inert in a live run, triggered by hand in the tour.
- **A real `/icm-demo` run** persists under `.icm/...`, goes through the hook (if
  `--hooks` is installed), and a model drives the stages - where all four
  mechanisms play together.

To see a gate fire on a *real* tool call, look at `kakkoidev/publish-to-notion`
(its stage 03 gates `notion-fetch` on a real publish receipt).

## What the demo's three stages do

`/icm-demo` is itself an ICM skill with three stages. Each runs one frozen,
deterministic script (so the evidence is reproducible and eval-checkable) and asks
the model only for the judgement the script cannot do. That split - script for facts,
model for explanation - is the whole ICM idea in miniature.

1. **`01-lifecycle`** - "what did `init` just create?" Runs `tools/run-report`, which
   captures this run's facts: stage order, the next empty stage, the run header
   (`run.json`), the enforcement posture (`gate-status`), and the five tracking
   artifacts (`.manifest`, `run.json`, `events.jsonl`, the global `skill-runs.jsonl`,
   `.icm-seals.log`). The model then explains what each artifact is.
   Output: `output/lifecycle.md`.
2. **`02-enforcement`** - "does enforcement actually fire?" Runs `tools/sandbox-tour`,
   which builds a throwaway copy of the run and exercises the gate + seal directly:
   stage scoping, gate DENY (precondition unmet), cross-harness normalization, a
   non-gated ALLOW, gate ALLOW, SEAL OK, SEAL MISMATCH, contract-tampered DENY. This
   stage carries the inert `demo_publish` gate described above.
   Output: `output/enforcement.md`.
3. **`03-telemetry-seal`** - "what did it cost, then lock it." Runs
   `tools/show-telemetry` to print the four-field per-stage token accounting (real,
   because stages 01-02 were closed against the live transcript), closes its own
   stage, then - as a POST-RUN step - runs `tools/close-run` to audit, seal,
   verify-seal, and index the run. Order matters: a stage cannot seal itself (its own
   `stage-done` is not recorded until after its work), so sealing happens after the
   final `stage-done`. Output: `output/telemetry.md` + a line in `.icm-seals.log`.

## Where to go next

- [README.md](../README.md) - the elevator pitch and quick start.
- [ARCHITECTURE.md](../ARCHITECTURE.md) - the five layers and component map.
- [REFERENCE.md](REFERENCE.md) - every gate/telemetry/seal/edge-case detail.
- [CONTRIBUTING.md](../CONTRIBUTING.md) - add a skill, run the tests, build the deck.
- `skills/kakkoidev/icm-demo/` - the annotated, runnable reference skill. Read its
  `SKILL.md` and stage contracts alongside this doc.
