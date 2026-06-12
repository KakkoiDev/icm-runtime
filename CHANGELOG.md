# Changelog

## 0.3.0 - 2026-06-12

- Tool call logging: every `icm.sh` invocation in a project with `.icm/` writes a
  structured line to `.icm/telemetry/tool-calls.jsonl` (timestamp, command, args,
  cwd, exit code)
- Run telemetry: `cmd_init` writes `telemetry/run.json` per run with stage names;
  new `telemetry` command writes completed-run summaries to
  `~/.icm/telemetry/skill-runs.jsonl`
- **Per-stage token tracking (MANDATORY, two-tier):** new `stage-done` command records
  stage boundaries to `telemetry/stages.jsonl` + `.stage-telemetry` marker. Token counts
  are OPTIONAL (the model has no programmatic access mid-session). New `reify-telemetry`
  command fills in exact counts post-hoc from the conversation transcript. Audit flags
  any completed stage without a `stage-done` marker.
- Deterministic tools convention: skills get an optional `tools/` directory; `init`
  freezes it into the run and adds to `.manifest` for tamper evidence
- Audit command: `icm.sh audit <workspace>` now does two checks — (1) stage
  telemetry completeness, (2) expected vs actual tool calls. Reports per-stage
  token usage summary from `stages.jsonl`.
- Manifest expansion: `tools/` files are now hashed in `.manifest` alongside
  `CONTEXT.md` and `checks/` files
- Reference implementation: `ai-folder-research` skill gets `tools/` with example
  search and synthesize scripts; stage contracts updated to reference tools
  and include mandatory per-stage telemetry

## 0.2.1 - 2026-06-10

- Fix: workspace resolution was broken for every externally-installed skill.
  `SCRIPT_DIR` resolved physically (`pwd -P`), so invocation via the installed
  `~/.agents/skills/icm/runtime/icm.sh` symlink pointed `SKILLS_DIR` at this repo's
  `skills/` instead of `~/.agents/skills`; and the bare-name lookup used `find` without
  `-L`, which skips symlinked workspaces entirely. `init`/`stages` failed for any skill
  living in another repo (e.g. the performance-review workspaces) since their migration.
  Now: logical `SCRIPT_DIR` + `find -L`. Verified: symlinked and direct invocation both
  resolve; full gate deny/allow chain re-proven; `sh tests/gate.test.sh` 26/26.

## 0.2.0 - 2026-06-10

- Harness-enforced stage gates: `<!-- ICM-GATE tools="..." run="..." -->` lines in stage
  contracts, frozen per run by `init` together with the skill's `checks/` dir
- Tamper evidence: `init` writes a sha256 `.manifest`; `gate-check` verifies every entry
  before honoring gates and fails closed on mismatch
- New commands: `icm.sh gate-check --tool <name> [--cwd <dir>]`,
  `icm.sh gate-status [--cwd <dir>]`
- `gate-hook.sh`: Claude Code PreToolUse hook that denies gated `mcp__*` tool calls while
  a matching gate fails (fails closed on missing jq or protocol mismatch)
- `icm-gate.ts`: pi `tool_call` extension blocking gated tool calls via the same
  `gate-check` core (fails closed when icm.sh is missing)
- `installer.sh --hooks`: idempotent registration of both adapters
  (`~/.claude/settings.json` hook entry, `~/.pi/agent/extensions/icm-gate.ts` symlink)
- `gate-status` is harness-aware: pi-only registration fails the check when running
  inside Claude Code (`CLAUDECODE` set)
- Regression suite: `sh tests/gate.test.sh` (26 cases, the manual pre-release check)

## 0.1.0 — 2026-06-01

- Initial release extracted from personal dotfiles
- `icm.sh` runtime: init, next, list, diff, stages, clean commands
- `ai-folder-research` workspace: 3-stage research pipeline (research → draft → polish)
- POSIX-compatible bash runtime (macOS, Linux, WSL)
- Gitignore safety check on init
- Namespace-aware workspace resolution (`jake-van-clief/ai-folder-research`)
- Installer with `--remove` for skill symlink management
