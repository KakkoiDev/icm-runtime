---
name: icm
description: >
  ICM runtime - manage Interpretable Context Methodology workspaces.
  Handles initialization, stage discovery, run listing, and run diffing.
  Used internally by workspace skills. Not invoked directly by users.
disable-model-invocation: true
---

# ICM Runtime

This skill provides the filesystem mechanics for all ICM workspace skills.
Workspace skills (like `ai-folder-research`) delegate deterministic filesystem operations here.

## Convention

All filesystem operations are handled by `icm.sh`. The LLM never creates directories,
copies files, or formats timestamps directly. Always call:

```
bash <icm-runtime-path>/icm.sh <command> <workspace-name>
```

## Runtime path

`~/.agents/skills/icm/runtime/icm.sh`

## Telemetry

Every `icm.sh` invocation in a project with `.icm/` writes a structured log line
to `.icm/telemetry/tool-calls.jsonl`. Each run's `telemetry/events.jsonl` is the
single append-only source of truth: `run_init`, `usage`, `stage_done`, and `reify`
events. `telemetry/run.json` is the static, sealed header (workspace, run_id,
created, stages, cwd, optional caller).

**Per-stage token tracking is MANDATORY.** After every stage completes, workspace
skills call `icm.sh stage-done`. It snapshots the stage's usage from the live
session transcript and appends one `usage` event per deduped API call plus a
`stage_done` boundary to `events.jsonl`, so counts survive harness transcript
cleanup. Each event carries four token fields kept separate: `tokens_in` (new
input only), `cache_creation`, `cache_read`, `tokens_out` (token counts only, no
conversation content). The audit command flags any completed stage that lacks a
`stage_done`.

Two things are derived FROM `events.jsonl` and kept outside it on purpose: the
global index `~/.icm/telemetry/skill-runs.jsonl` (one line per run) and the tamper
anchor `.icm-seals.log` (project root, committable while `.icm/` stays gitignored).
Nothing joins across files at read time.

## Commands

### init workspace-name [--caller <parentWs>/<parentRunId>/<stage>]
Creates a new timestamped run directory, copies all stage contracts from the skill
into the run as frozen `CONTEXT.md` files, copies the skill's `checks/` and `tools/`
dirs in, writes a sha256 `.manifest` over all frozen files, and creates empty
`output/` dirs per stage. Writes the static header to `telemetry/run.json` and the
first `run_init` event to `telemetry/events.jsonl`. Prints the run directory path to
stdout.

`--caller` records the parent run that invoked this one, for skills that invoke
other ICM skills as a sub-step. The value is written as a `caller` field in the
child's `telemetry/run.json` and propagated to `skill-runs.jsonl`. Because
`run.json` is in the sealed set, the child's own seal makes the link
tamper-evident. Omit it for standalone runs. The runtime neither enforces nor
auto-detects it: there is no reliable "currently-executing run/stage" signal, so a
nesting skill's frozen stage contract supplies the value. The link is ground truth,
not a guess written into sealed data. Child runs are NOT physically nested under the
parent; they keep their own `.icm/<ws>/<run_id>/` dir so every command can still
address them.

**Side effect:** Checks if `.icm/` is in `.gitignore`. Warnings on stderr; tell the user.

### next workspace-name
Finds the latest run and returns the path of the first stage whose `output/` is empty.
If all stages have output, prints "done".

### list workspace-name
Prints all runs with a per-stage completion mark.

### diff workspace-name
Diffs output files between the last two completed runs.

### stages workspace-name
Prints stage names in order.

### clean workspace-name [--keep N]
Removes old completed runs, keeping the N most recent (default: 5).
**Never removes incomplete runs** - work in progress is always preserved.
Also rotates `.icm/telemetry/tool-calls.jsonl` to its last 10000 lines when it
has grown past that. Audit runs you care about before cleaning: rotation drops old
actual-tool records.

### stage-done workspace-name --stage <name> [--full] [--transcript <path>] [--cwd <dir>]
MANDATORY. Appends a `stage_done` boundary event to `events.jsonl` plus one `usage`
event per deduped API call in the stage window (previous boundary to now). Token
counts and the model are read from the session transcript automatically; the legacy
`--model/--tokens-in/--tokens-out` flags are only a no-transcript fallback. Audit
flags any completed stage without a `stage_done`.

The transcript is located deterministically (session id under Claude Code, else the
path recorded by `gate-hook.sh`, else newest session by cwd); `--transcript`
overrides. Requires jq for snapshotting; without it the boundary is still recorded
with null counts (reify-telemetry can fill them later).

`--full` additionally freezes the raw transcript window into
`<stage>/transcript.jsonl`. That is full conversation content: prompts, fetched
pages, everything. Do not commit runs containing `--full` snapshots without
deciding that deliberately.

### reify-telemetry workspace-name [--cwd dir] [--transcript path]
Post-run recompute: reads the now-complete transcript and recomputes each stage's
exact four-field counts, appending a `reify` event per stage to `events.jsonl`. It
does NOT rewrite the original `stage_done` events, so a seal taken earlier stays
valid; readers prefer the last `reify` over the `stage_done`. Use it when the live
`stage-done` snapshot was incomplete (no jq, or the transcript was not yet flushed).
Requires jq. Transcript located like stage-done; `--transcript` overrides. No-op with
a warning if no transcript is found. Must run while the harness still has the session
file.

### telemetry workspace-name [--cwd dir]
Writes or refreshes this run's one-line summary in the global index
`~/.icm/telemetry/skill-runs.jsonl` (derived from `events.jsonl`). Legacy
`--model/--tokens-in/--tokens-out/--cost` flags are accepted but ignored; counts
come from the events. Prints the global telemetry file path on success.

### audit workspace-name [--strict] [--cwd dir]
Reads `events.jsonl` and does three checks: (1) every completed stage has a
`stage_done` event; (2) expected tools, declared per stage via
`<!-- ICM-TOOLS expect="..." -->` (whitespace-separated EREs, matched unanchored),
are compared against actual harness tool calls recorded by the enforcement adapter
in `.icm/telemetry/tool-calls.jsonl`; (3) any `ICM-CALL` execution spec is checked
against the args recorded in `tool-args.jsonl`. Attribution is PER-STAGE: each stage
is matched only against tool calls whose timestamp falls in its window. If a stage
has no `stage_done` or boundaries are non-monotonic (a re-run), attribution is
reported "unreliable" and not counted rather than risk silent mis-attribution.
Actual tool records exist only where an adapter is registered; with none in the run
window, audit reports "gates were advisory only" and does not count deviations.
Produces a deviation report with a per-stage token-usage summary. Bare `audit` exits
0 even with deviations (informational); `audit --strict` exits 1 when deviations > 0,
so CI and publish-stage preconditions can gate on it.

### seal workspace-name [--cwd dir]
Appends a digest line for the latest run's evidence (`telemetry/run.json`,
`telemetry/events.jsonl`, and `.manifest`) to `.icm-seals.log` at the project root.
The log is committable while `.icm/` stays gitignored; commit it after each sealed
run. Tamper evidence, not prevention: until the log is committed and pushed it is an
editable file like any other. Call at run end, after the final `stage-done`.

### verify-seal workspace-name|--all [--cwd dir]
Recomputes digests against the last seal line. Per workspace: latest run only.
`--all`: every (workspace, run) ever sealed; runs pruned by `clean` print
`SEAL SKIP` and do not fail. Prints `SEAL OK` (exit 0) or `SEAL MISMATCH`
per altered/missing file (exit 1). Exit 1 too when no seal exists.

### children workspace-name [run_id]
Lists runs that recorded `<workspace>/<run_id>` as their `--caller` (default
`run_id`: latest). Read-only top-down view of the explicit parent-to-child links:
prints each child run dir and the parent stage that invoked it. Direct children
only. Says so when there are none.

### gate-check --tool tool-name [--cwd dir]
Evaluates frozen ICM-GATE lines for the ACTIVE stage of the latest run under cwd's
`.icm/`. Exit 0 (silent): no gate matches the tool, or all matching gates pass.
Exit 1 with `DENY` lines on stdout: a matching gate's checker failed, the run's
`.manifest` does not verify (tampered frozen contract or checker), or a gate line is
malformed. Called by the PreToolUse hook (`gate-hook.sh`) on every tool call,
built-ins included; also callable directly. Kept fork-lean (batched sha256, no
per-file subshells); keep it that way when editing.

### gate-status [--cwd dir]
Lists gates declared by installed skills and by active runs in cwd, evaluates the
active ones, and reports enforcement registration per scope: Claude Code settings
(`~/.claude/settings.json`, project `.claude/settings.json`,
`.claude/settings.local.json`) and pi extension paths
(`~/.pi/agent/extensions/icm-gate.ts`, project `.pi/extensions/icm-gate.ts`). Exit 1
iff active runs declare gates and either no scope registers enforcement, or the
process runs inside Claude Code (`CLAUDECODE` set) without a Claude-scope
registration. Publish-stage contracts should run this before sending anything.

### eval workspace-name
Runs the skill's `eval/*.test.sh` checks from the skill dir, aggregates pass/fail,
and exits non-zero on any failure.

### new-skill <namespace>/<name> --stages a,b,c [--desc <one-liner>]
Scaffolds a new skill: a `SKILL.md`, one stub per stage under `stages/`, a `tools/`
dir, and an `eval/` (README + a smoke test). Fill in each stage's Process, push
bash-reachable work into `tools/`, and replace the stub eval.

### catalog
Prints a markdown index of installed skills.

## Deterministic Tools

Skills may include a `tools/` directory with deterministic shell scripts.
`icm.sh init` freezes `tools/` into the run (like `checks/`) and adds them to
the `.manifest` for tamper evidence. Gate checkers can reference them:
`run="tools/verify.sh"`.

Scripts the agent runs directly via bash are NOT recorded in
`tool-calls.jsonl` (only `icm.sh` invocations log). To make a stage's expected
harness tools auditable, declare them explicitly in the stage contract:

```
<!-- ICM-TOOLS expect="(search_web|WebSearch) (fetch_url|WebFetch)" -->
```

One line per contract; tokens are whitespace-separated EREs matched unanchored
against harness tool names. Frozen with the contract and covered by `.manifest`,
so expectations cannot be quietly edited mid-run. Use alternation to cover
per-harness tool naming differences, same as the ICM-GATE naming caveat.

## Stage gates

A stage contract may declare a gate on a single line (attribute values double-quoted,
single line, no embedded double quotes):

```
<!-- ICM-GATE tools="<ERE over tool names>" run="<checker command>" -->
```

Semantics:
- `tools` is matched unanchored against the harness tool name, raw or normalized:
  the `mcp__<server>__` wrapper is stripped and built-in aliases folded, so one
  canonical name matches every harness. Anchor with `^...$` for exact matching.
- `run` executes with cwd = the run's stage dir. If its first token is a relative path
  to a file frozen at the run root (the skill's `checks/` dir is copied there by
  `init`), the token resolves against the run root. Exit 0 = pass.
- Checkers must be deterministic, read-only, and fast (well under the hook's 15s timeout).
- Gates are scoped to the ACTIVE stage (the first stage with no `stage_done`): a later
  stage's gate cannot deny an earlier stage's tool, and a completed run denies nothing.
- `init` writes `.manifest` (sha256 of every frozen file). `gate-check` verifies all
  entries before honoring anything; mismatch denies, so a gate cannot be weakened
  mid-run by editing frozen files. Edit the live skill and re-init instead.
- Do not put a literal `ICM-GATE` example inside a stage contract's prose; it will be
  parsed as a real gate (and a malformed one denies).

Enforcement requires a harness adapter (`installer.sh --hooks` registers all of
them): `gate-hook.sh` for Claude Code (PreToolUse), `icm-gate.ts` for pi
(`tool_call` extension). Agents without an adapter see gates as advisory; contracts
should still call `gate-check`/`gate-status` explicitly before publish steps as
defense in depth.

### Execution specs (ICM-CALL)

A stage may also declare `<!-- ICM-CALL tool="..." args="f1,f2" -->`. With an adapter
installed, `audit` verifies the named tool was called in the stage window with every
required arg field present; the `field@path` form additionally checks the arg value
equals a run-root-relative file's content. Where a gate checks an output condition,
an execution spec checks the call itself.

## Workspace naming

Workspace names support two forms:
- **Bare:** `ai-folder-research` - recursive search (backward compatible)
- **Namespaced:** `kakkoidev/icm-demo` - deterministic path resolution under a namespace

Namespaced syntax is preferred for workspaces installed under a team/personal directory.

## How workspace skills use this

1. User invokes a workspace skill (e.g. `/ai-folder-research`)
2. The workspace `SKILL.md` tells the agent to call `icm.sh init`
3. The agent reads the init stdout to get the run directory path
4. It checks init stderr for gitignore warnings and tells the user if `.icm/` is not gitignored
5. For each stage: read `CONTEXT.md`, execute the Process, write output, call `stage-done`
6. Call `icm.sh next` to find what is left; when it returns "done", reify, audit, and seal
