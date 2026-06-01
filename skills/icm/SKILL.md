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
