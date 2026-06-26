# Plan: harness-enforced ICM stage gates (agents cannot bypass)

Status: IMPLEMENTED 2026-06-10 (commits d11c685..4698b65, plus a pi tool_call adapter
beyond this plan's scope). Kept as the design record; line references describe the
pre-implementation tree (`icm.sh` @ 308 lines, `installer.sh` @ 186 lines, commit
`46f330e` era) and no longer match current files.

## 1. Problem

ICM stage contracts are prose. An agent executing a stage can skip a rule it knows about -
this happened 2026-06-10: a "preservation gate" written into the `sprint-focus` skill
(performance-review repo) was a convention, and conventions do not bind. The skill now has a
mechanical in-contract gate (line accounting + URL checks written to
`04-send/output/preservation.md` before sending to Slack), but the gate is still EXECUTED BY
THE AGENT. An agent that skips the gate can still call `slack_send_message`.

The only layer in Claude Code that an agent cannot skip is a **hook**: hooks run in the
harness, outside the model's control. This plan adds first-class gates to the ICM runtime,
enforced by a PreToolUse hook that denies gated tool calls until the gate's checker passes.

## 2. Threat model (read this before arguing with the design)

Defends against: a **negligent or lazy agent** that skips a verification step, sends before
checking, or hallucinates "checks passed".

Does NOT defend against a malicious agent. Residual bypasses, accepted and documented:
- The agent edits/deletes the run dir or the frozen contract. Mitigated by a sha256 manifest
  (gate-check fails closed on tamper) and by the fact that workspaces like performance-review
  COMMIT `.icm/`, so tampering is loud in `git status`/history.
- The agent fabricates checker inputs (e.g. writes a fake `raw.md`). The checker can only
  verify internal consistency of artifacts, not the truth of their capture.
- The agent uses a send path outside the gated tool list (a different MCP server, Bash+curl
  with a token). Out of scope for v1; the realistic send paths in this environment are the
  `mcp__claude_ai_Slack__*` tools (no Slack token is available to Bash locally).
- Enforcement only exists where the hook is REGISTERED. An unregistered machine silently
  loses it. Mitigated by: project-level `.claude/settings.json` registration committed in
  workspace repos (travels with `git clone`) + a `gate-status` command that makes absence
  loud + the skill contracts instructing agents to run `gate-status` before publish stages.

## 3. Verified facts the design relies on

Hook protocol (verified 2026-06-10 against https://code.claude.com/docs/en/hooks.md and
settings.md - re-verify, this API has changed before):
- PreToolUse hooks live under `hooks.PreToolUse` in settings files; `matcher` is a REGEX
  over tool names (MCP tools appear as `mcp__<server>__<tool>`, e.g.
  `mcp__claude_ai_Slack__slack_send_message`). Use `.*` not `*`.
- The hook command receives JSON on stdin: `{session_id, transcript_path, cwd,
  permission_mode, hook_event_name, tool_name, tool_input}`. `cwd` is the session's working
  directory. `tool_input` is the MCP tool's native arguments.
- Clean blocking: exit 0 and print on stdout
  `{"hookSpecificOutput": {"hookEventName": "PreToolUse", "permissionDecision": "deny",
  "permissionDecisionReason": "<why>"}}`. (Exit 2 + stderr also blocks but is the error
  path; prefer the JSON decision.)
- Hooks merge across scopes (user `~/.claude/settings.json`, project `.claude/settings.json`,
  project `settings.local.json`); project-level hooks are git-shared.
- Hooks do not inherit session env; everything needed must come from stdin JSON or disk.

icm.sh integration points (current file):
- `find_workspace()` line 23: resolves a workspace dir under `SKILLS_DIR` (= `icm.sh/../..`),
  namespaced or recursive find.
- `cmd_init()` line 73: creates `.icm/<ws>/<UTC-ts>/<stage>/output/` and freezes each
  `stages/*.md` to `<stage>/CONTEXT.md` via `cp`. THIS IS THE HOOK-IN POINT for freezing
  gates and checker scripts per run.
- `latest_run()` line 56: newest timestamp dir under `.icm/<ws>/`.
- Stage completion semantics everywhere: `output/` non-empty (see `cmd_next` line 102).
- Main dispatch lines 290-308 requires exactly `cmd + ws` positionals; `gate-check` takes no
  workspace (it scans all), so the arity check needs relaxing for that subcommand.
- POSIX sh, zero dependencies. Keep icm.sh jq-free; the HOOK script may require jq (it must
  parse stdin JSON) - see 4.4.

installer.sh integration points: bash, `install_symlink`/`install_claude_symlink` etc.,
arg dispatch at lines 172-182. New `--hooks` flag slots into that case statement.

## 4. Design

### 4.1 Gate declaration: one line inside the stage contract

A stage that gates tool calls carries a single self-contained line in its `stages/NN-*.md`:

```
<!-- ICM-GATE tools="mcp__claude_ai_Slack__slack_send_message(_draft)?" run="checks/preservation.sh" -->
```

- `tools`: ERE regex matched against the harness `tool_name`.
- `run`: checker command, executed by `gate-check` with cwd = the run's stage dir
  (`.icm/<ws>/<ts>/<NN-stage>/`). Exit 0 = gate passes. The degenerate "evidence file" form
  needs no script: `run="grep -Eq '^RESULT: PASS$' output/preservation.md"`.
- Attribute values: double-quoted, no embedded double quotes, single line. Parse with
  grep + sed in POSIX sh; do not build a general attribute parser.
- Why in the contract md: `cmd_init` already freezes contracts into the run. A gate frozen
  at init cannot be weakened mid-run by editing the skill. The frozen `CONTEXT.md` is the
  authority consulted at enforcement time, never the live skill file.

### 4.2 Freezing + tamper evidence (extend `cmd_init`)

1. If the skill has a `checks/` dir, copy it into the run root: `.icm/<ws>/<ts>/checks/`
   (checker scripts freeze with the contracts; `run=` paths resolve against the run root
   first, then the stage dir).
2. Write `.icm/<ws>/<ts>/.manifest`: one `sha256  <relpath>` line per frozen `CONTEXT.md`
   and per `checks/*` file. Portable hashing: `command -v sha256sum || shasum -a 256`.
3. `gate-check` re-hashes the gated stage's `CONTEXT.md` (and any `checks/*` it runs) against
   `.manifest` BEFORE honoring or executing anything. Mismatch = DENY with reason
   "contract tampered" (fail closed). Note: `cmd_clean` must ignore `.manifest` and `checks/`
   when classifying runs complete/incomplete (it globs `[0-9]*/` for stages, so a dotfile and
   a non-numeric dir are already ignored - verify, do not assume).

### 4.3 New icm.sh commands

`icm.sh gate-check --tool <tool_name> [--cwd <dir>]`
- Scan every workspace under `<cwd>/.icm/*/`; for each, take ONLY the latest run.
- Skip runs that are COMPLETE (every stage `output/` non-empty AND every gate passes).
- For each gate line in the latest run's frozen `CONTEXT.md`s whose `tools` regex matches
  `<tool_name>`:
  - Verify manifest hashes (4.2.3); tampered = deny.
  - Execute `run`; non-zero = deny.
- Output on deny (stdout, machine-readable, first line wins):
  `DENY <ws> <run-ts> <stage>: <reason>` and exit 1.
- Exit 0 (silent) when nothing matches or all matching gates pass.
- Strictness is deliberate: while a gated run is incomplete, matching tool calls in that cwd
  are blocked until the checker passes, even if the agent claims to be doing unrelated work.
  Escape hatches are human-visible only: finish the run, delete the stale run dir (loud in
  git), or disable the hook in `settings.local.json`. NO env-var bypass - an env var is
  agent-writable and defeats the point.

`icm.sh gate-status [--cwd <dir>]`
- Lists every gate declared by installed skills and by active runs in cwd.
- Reports whether the hook is registered: scan `~/.claude/settings.json`,
  `<cwd>/.claude/settings.json`, `<cwd>/.claude/settings.local.json` for the hook script
  path. Print REGISTERED / NOT REGISTERED per scope. Exit 1 if gates exist but no
  registration found (so contracts can assert on it).

Main dispatch: relax the 2-positional check for `gate-check`/`gate-status`; update the
usage() text and the header comment block (lines 3-9).

### 4.4 Hook script: `skills/icm/runtime/gate-hook.sh`

- Reads stdin JSON. Requires `jq`; if jq is missing, emit a DENY decision with reason
  "jq missing - gate cannot be evaluated, install jq" (fail closed; a silent fail-open turns
  missing deps into missing enforcement).
- Extract `tool_name` and `cwd`; `cd "$cwd"`; fast path: no `.icm/` dir = exit 0 silently.
- Run `<SCRIPT_DIR>/icm.sh gate-check --tool "$tool_name"`. On exit 1, print the deny JSON
  (4.3's DENY line as `permissionDecisionReason`) and exit 0. Otherwise exit 0 silently.
- Keep it under ~40 lines. It must never write to the run dir (read-only enforcement).

### 4.5 Registration

Recommended hook entry (project-level `.claude/settings.json` in each ICM workspace repo,
committed, so enforcement travels with the repo; same JSON works in `~/.claude/settings.json`
for global coverage via `installer.sh --hooks`):

```json
{
  "hooks": {
    "PreToolUse": [
      {
        "matcher": "mcp__.*",
        "hooks": [
          {
            "type": "command",
            "command": "$HOME/.agents/skills/icm/runtime/gate-hook.sh",
            "timeout": 15
          }
        ]
      }
    ]
  }
}
```

- Broad `mcp__.*` matcher + fast no-`.icm` exit in the script beats maintaining a tool list
  in settings; the gate's own `tools` regex is the real filter. Verify `$HOME` expands in
  hook commands; if not, write the absolute path at install time.
- `installer.sh --hooks`: idempotent merge of the entry into `~/.claude/settings.json` using
  jq (check for the command path first; back up the file; create it if absent). Add to the
  case dispatch at lines 172-182 and to the usage text. Print what was changed.

## 5. Implementation order

1. `icm.sh`: gate parsing helper (grep+sed of `ICM-GATE` lines), manifest write in
   `cmd_init`, portable sha helper, `cmd_gate_check`, `cmd_gate_status`, dispatch + usage.
2. `skills/icm/runtime/gate-hook.sh` (chmod +x).
3. `installer.sh --hooks`.
4. Tests (section 7) - write them WITH 1-3, not after.
5. Docs (section 9).
6. First consumer wiring lives in the performance-review repo, not here (section 6) - leave
   it to that repo's owner; this repo only ships the mechanism plus a fixture-based test.

## 6. First consumer (for context, implemented in performance-review)

`skills/sprint-focus/stages/04-send.md` gains:
`<!-- ICM-GATE tools="mcp__claude_ai_Slack__slack_send_message(_draft)?" run="checks/preservation.sh" -->`
plus a `skills/sprint-focus/checks/preservation.sh` that re-runs the line-accounting /
URL-set / pointer-ban reconciliation deterministically against `../01-ingest/output/raw.md`
and the `message-*.md` files, exiting non-zero with the unaccounted lines on stdout. The
skill's prose gate stays (defense in depth); the hook makes it binding. Future consumers:
`todo-triage` 04-publish and `refine-tickets` 04-publish gating
`mcp__claude_ai_Notion__notion-update-page|notion-create-pages`.

## 7. Tests (regression suite; each case fails if the feature is reverted)

`tests/gate.test.sh`, self-contained, tmp-dir based, no network, runnable via
`sh tests/gate.test.sh`. Build a fixture skill (one gated stage whose `run` is a trivial
`grep` on an evidence file) under a tmp SKILLS_DIR; point icm.sh at it (SKILLS_DIR is derived
from the script path, so copy icm.sh into the fixture tree or make SKILLS_DIR overridable
via an env var read ONLY when a test flag file exists - implementer's choice, document it).

Cases:
1. No `.icm/` in cwd: `gate-check --tool x` exits 0.
2. Active run, gated stage, checker fails (no evidence): exit 1, DENY line names ws/run/stage.
3. Evidence present, checker passes: exit 0.
4. Tool name not matching `tools` regex: exit 0 even with failing checker.
5. Tampered frozen contract (append a byte after init): DENY with tamper reason.
6. Completed run with passing gate: exit 0 (no stale blocking).
7. Hook end-to-end: pipe crafted stdin JSON through `gate-hook.sh` for cases 2 and 3; assert
   deny-JSON emitted (2) and silent exit 0 (3).
8. Init freezes gates: edit the SKILL's stage md after init to REMOVE the gate; `gate-check`
   still enforces (reads the frozen CONTEXT.md, not the skill).
9. `installer.sh --hooks` twice: settings.json contains exactly one hook entry (idempotent).

## 8. Acceptance criteria

- With the hook registered, an agent in a workspace cwd with an incomplete gated run CANNOT
  execute a matching MCP tool call: the call is denied with a reason naming the run, stage,
  and checker output.
- The same call succeeds immediately after the checker passes.
- Editing the live skill or the frozen contract mid-run cannot weaken an active gate
  (frozen-contract test 8 + tamper test 5 green).
- All 9 tests pass; `sh tests/gate.test.sh` is wired into whatever CI exists (none today -
  note it in README as the manual pre-release step).
- `icm.sh gate-status` correctly reports NOT REGISTERED on a machine without the hook entry.

## 9. Docs to update in this repo

- `README.md`: gates section (what, threat model summary, registration snippet).
- `skills/icm/SKILL.md`: document `gate-check`, `gate-status`, the ICM-GATE line format, and
  the `checks/` freezing behavior.
- `CHANGELOG.md`: entry for the feature.
- `installer.sh` usage text.

## 10. Out of scope (do not creep)

- Gating Bash or non-MCP tools (no realistic bypass path today; revisit if one appears).
- PostToolUse audit hooks, notification hooks.
- Any env-var or flag that lets an agent bypass a gate programmatically.
- Windows support beyond what POSIX sh already gives (matches the runtime's current stance).
