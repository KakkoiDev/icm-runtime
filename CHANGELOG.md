# Changelog

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
