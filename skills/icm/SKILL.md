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
**Never removes incomplete runs** — work in progress is always preserved.

### gate-check --tool tool-name [--cwd dir]
Evaluates frozen ICM-GATE lines in the latest run of every workspace under cwd's `.icm/`.
Exit 0 (silent): no gate matches the tool, or all matching gates pass. Exit 1 with `DENY`
lines on stdout: a matching gate's checker failed, the run's `.manifest` does not verify
(tampered frozen contract or checker), or a gate line is malformed. Called by the
PreToolUse hook (`gate-hook.sh`) on every `mcp__*` tool call; also callable directly.

### gate-status [--cwd dir]
Lists gates declared by installed skills and by active runs in cwd, evaluates the active
ones, and reports hook registration per settings scope (`~/.claude/settings.json`, project
`.claude/settings.json`, project `.claude/settings.local.json`). Exit 1 iff active runs
declare gates but no scope registers the hook. Publish-stage contracts should run this
before sending anything.

## Stage gates

A stage contract may declare a gate on a single line (attribute values double-quoted,
single line, no embedded double quotes):

```
<!-- ICM-GATE tools="<ERE over tool names>" run="<checker command>" -->
```

Semantics:
- `tools` is matched unanchored against the harness tool name (`mcp__<server>__<tool>`).
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

Enforcement requires the Claude Code PreToolUse hook (see README, `installer.sh --hooks`).
Other agents do not read Claude Code hooks; there, gates are advisory and contracts should
call `gate-check`/`gate-status` explicitly before publish steps.

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
