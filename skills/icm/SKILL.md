---
name: icm
description: >
  ICM runtime — manage Interpretable Context Methodology workspaces.
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
to `.icm/telemetry/tool-calls.jsonl`. Each ICM run gets a `telemetry/run.json` with
metadata and stage names.

**Per-stage token tracking is MANDATORY.** After every stage completes, workspace
skills call `icm.sh stage-done`. This writes to the run's `telemetry/stages.jsonl`,
drops a `.stage-telemetry` marker, and snapshots the stage's usage events
(token counts per API call, no conversation content) into `telemetry/usage.jsonl`
so counts survive harness transcript cleanup and can be recomputed anytime.
The audit command flags any completed stage that lacks this telemetry.

Workspace skills MUST also call `icm.sh telemetry` after completion to write
a summary to `~/.icm/telemetry/skill-runs.jsonl`.

## Commands

### init workspace-name
Creates a new timestamped run directory, copies all stage contracts from the skill
into the run as frozen `CONTEXT.md` files, and creates empty `output/` dirs per stage.
Prints the run directory path to stdout.

**Side effect:** Checks if `.icm/` is in `.gitignore`. Warnings on stderr — tell the user.

### next workspace-name
Finds the latest run and returns the path of the first stage whose `output/` is empty.
If all stages have output, prints "done".

### list workspace-name
Prints all runs with ✓ or ✗ per stage.

### diff workspace-name
Diffs output files between the last two completed runs.

### stages workspace-name
Prints stage names in order.

### clean workspace-name [--keep N]
Removes old completed runs, keeping the N most recent (default: 5).
**Never removes incomplete runs** - work in progress is always preserved.
Also rotates `.icm/telemetry/tool-calls.jsonl` to its last 10000 lines when it
has grown past that (the wide hook matcher logs one line per tool call).
Audit runs you care about before cleaning: rotation drops old actual-tool records.

### stage-done workspace-name --stage <name> --model <m> [--tokens-in <N> --tokens-out <N>] [--full] [--transcript <path>]
MANDATORY. Records a stage boundary marker to `telemetry/stages.jsonl` and drops
a `.stage-telemetry` marker. Audit flags any completed stage without it.

Snapshots the session transcript for the stage window (previous boundary to now)
while the file still exists: usage events (timestamps and token counts only, no
conversation content) are appended to `telemetry/usage.jsonl`, and token counts
are computed on the spot when `--tokens-in/--tokens-out` are not passed
(`"counts": "transcript"`). The transcript is located via the path recorded by
`gate-hook.sh`, falling back to harness session dirs; `--transcript` overrides.
Requires jq for snapshotting; without it the boundary is still recorded with
null counts.

`--full` additionally freezes the raw transcript window into
`<stage>/transcript.jsonl`. That is full conversation content: prompts, fetched
pages, everything. Do not commit runs containing `--full` snapshots without
deciding that deliberately.

### reify-telemetry workspace-name [--cwd dir] [--transcript path]
Post-hoc fallback for runs where `stage-done` could not snapshot (no jq, no
transcript at the time): reads the conversation transcript and fills in exact
token counts per stage in `stages.jsonl` (sums `usage.*` between consecutive
stage-done timestamps). Replaces `"counts": "estimated"` with
`"counts": "transcript"`. Requires jq. Transcript located like stage-done
(hook-recorded path, then newest session by mtime; warns when several qualify);
pass `--transcript` to override. No-op with warning if no transcript is found.
Must run while the harness still has the session file.

### telemetry workspace-name --model <name> --tokens-in <N> --tokens-out <N> --cost <amount>
Writes a summary of the completed run to `~/.icm/telemetry/skill-runs.jsonl`.
Called by workspace skills after all stages are done. Prints the global telemetry
file path on success.

### audit workspace-name [--cwd dir]
Two-part check: (1) verifies every completed stage has per-stage telemetry from
`stage-done`, (2) compares expected tools against actual harness tool calls.
Expected tools come from an `<!-- ICM-TOOLS expect="..." -->` line in the frozen
contract; each whitespace-separated token is an ERE matched unanchored against
actual tool names (same semantics as ICM-GATE `tools=`). Contracts without the
declaration fall back to scraping `tools/...` mentions from prose. Actual tool
names come from `gate-check --tool` entries in `.icm/telemetry/tool-calls.jsonl`,
so they exist only where an enforcement adapter is registered; with no records
in the run window, audit says so and does not count deviations. Produces a
deviation report on stdout including per-stage token usage summary. Exit 0 even
with deviations (report is informational). Exit 1 if workspace or run is not found.

### seal workspace-name [--cwd dir]
Appends a digest line for the latest run's evidence files (`.manifest`,
`telemetry/run.json`, `telemetry/stages.jsonl`, `telemetry/usage.jsonl`) to
`.icm-seals.log` at the project root. The log is committable while `.icm/`
stays gitignored; commit it after each sealed run. Tamper evidence, not
prevention: until the log is committed and pushed it is an editable file like
any other. Call at run end, after `stage-done` and `telemetry`.

### verify-seal workspace-name|--all [--cwd dir]
Recomputes digests against the last seal line. Per workspace: latest run only.
`--all`: every (workspace, run) ever sealed; runs pruned by `clean` print
`SEAL SKIP` and do not fail. Prints `SEAL OK` (exit 0) or `SEAL MISMATCH`
per altered/missing file (exit 1). Exit 1 too when no seal exists.

### gate-check --tool tool-name [--cwd dir]
Evaluates frozen ICM-GATE lines in the latest run of every workspace under cwd's `.icm/`.
Exit 0 (silent): no gate matches the tool, or all matching gates pass. Exit 1 with `DENY`
lines on stdout: a matching gate's checker failed, the run's `.manifest` does not verify
(tampered frozen contract or checker), or a gate line is malformed. Called by the
PreToolUse hook (`gate-hook.sh`) on every tool call, built-ins included; also callable
directly. Runs on every hooked call, so it is kept fork-lean (batched sha256, no
per-file subshells); keep it that way when editing.

### gate-status [--cwd dir]
Lists gates declared by installed skills and by active runs in cwd, evaluates the active
ones, and reports enforcement registration per scope: Claude Code settings
(`~/.claude/settings.json`, project `.claude/settings.json`, project
`.claude/settings.local.json`) and pi extension paths (`~/.pi/agent/extensions/icm-gate.ts`,
project `.pi/extensions/icm-gate.ts`). Exit 1 iff active runs declare gates and either no
scope registers enforcement, or the process runs inside Claude Code (`CLAUDECODE` set)
without a Claude-scope registration. Publish-stage contracts should run this before
sending anything.

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
- `tools` is matched unanchored against the harness tool name: MCP form
  (`mcp__<server>__<tool>`) or built-in names (`WebSearch`, `Bash`, ...).
  Anchor with `^...$` for exact matching.
- `run` executes with cwd = the run's stage dir. If its first token is a relative path to a
  file frozen at the run root (the skill's `checks/` dir is copied there by `init`), the
  token resolves against the run root. Exit 0 = pass.
- Checkers must be deterministic, read-only, and fast (well under the hook's 15s timeout).
  They run on every matching MCP tool call.
- `init` writes `.manifest` (sha256 of every frozen `CONTEXT.md` and `checks/` file).
  `gate-check` verifies all entries before honoring anything; mismatch denies, so a gate
  cannot be weakened mid-run by editing frozen files. Edit the live skill and re-init
  instead.
- Do not put a literal `<!-- ICM-GATE ` example inside a stage contract's prose; it will be
  parsed as a real gate (and a malformed one denies).

Enforcement requires a harness adapter (see README, `installer.sh --hooks` registers all
of them): `gate-hook.sh` for Claude Code (PreToolUse), `icm-gate.ts` for pi (`tool_call`
extension). Agents without an adapter see gates as advisory; contracts should still call
`gate-check`/`gate-status` explicitly before publish steps as defense in depth.

## Workspace naming

Workspace names support two forms:
- **Bare:** `ai-folder-research` — recursive search (backward compatible)
- **Namespaced:** `jake-van-clief/ai-folder-research` — deterministic path resolution under a namespace

Namespaced syntax is preferred for workspaces installed under a team/personal directory.

## How workspace skills use this

1. User invokes workspace (e.g. `/ai-folder-research`)
2. Workspace SKILL.md tells PI to call `icm.sh init`
3. PI reads the init output (stdout) to get the run directory path
4. PI checks init stderr for gitignore warnings — tells the user if `.icm/` isn't gitignored
5. For each stage: PI reads `CONTEXT.md`, executes Process, writes output
6. After each stage: PI calls `icm.sh next` to find what's left
7. When next returns "done", PI summarizes and stops
