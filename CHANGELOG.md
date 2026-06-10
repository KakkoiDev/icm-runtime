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
- `installer.sh --hooks`: idempotent registration of the hook in `~/.claude/settings.json`
- Regression suite: `sh tests/gate.test.sh` (20 cases, the manual pre-release check)

## 0.1.0 — 2026-06-01

- Initial release extracted from personal dotfiles
- `icm.sh` runtime: init, next, list, diff, stages, clean commands
- `ai-folder-research` workspace: 3-stage research pipeline (research → draft → polish)
- POSIX-compatible bash runtime (macOS, Linux, WSL)
- Gitignore safety check on init
- Namespace-aware workspace resolution (`jake-van-clief/ai-folder-research`)
- Installer with `--remove` for skill symlink management
