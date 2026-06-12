# Changelog

## 0.5.0 - 2026-06-12

- **Per-stage transcript snapshots:** `stage-done` now snapshots the session
  transcript window (previous boundary to now) while the file still exists.
  Default appends usage events only (ts, model, token counts -- no conversation
  content) to `telemetry/usage.jsonl` and computes the stage's token counts on
  the spot (`"counts": "transcript"`). `--full` additionally freezes the raw
  window into `<stage>/transcript.jsonl` (full conversation content -- keep
  gitignored unless deliberate). `reify-telemetry` demoted to post-hoc fallback.
- `gate-hook.sh` records the harness-provided `transcript_path` into
  `.icm/telemetry/transcript-path` on every hook invocation; `stage-done` and
  `reify-telemetry` prefer it over newest-session guessing (shared
  `find_transcript` helper).
- **Seal:** `icm.sh seal <workspace>` appends sha256 digests of the latest run's
  evidence files (`.manifest`, `run.json`, `stages.jsonl`, `usage.jsonl`) to a
  committable `.icm-seals.log` at the project root; `verify-seal` recomputes and
  exits 1 on mismatch. Tamper evidence once committed, not prevention.
- Tests: cases 24-26 (snapshot, --full, hook transcript-path recording,
  seal/verify/tamper). 49 total.

## 0.4.0 - 2026-06-12

- **ICM-TOOLS declarations:** stage contracts declare expected harness tools with
  `<!-- ICM-TOOLS expect="..." -->` (whitespace-separated EREs, unanchored, same
  semantics as ICM-GATE `tools=`). Frozen with the contract and manifest-covered.
  `audit` matches each declared tool against actual `gate-check --tool` records in
  the run window: ✓ seen, ✗ deviation. When no records exist (no enforcement
  adapter), audit says so instead of counting false deviations. Prose scraping of
  `tools/...` mentions remains as fallback for undeclared contracts.
- Fix: `tool-calls.jsonl` was not valid JSONL when jq was installed -- the args
  array was pretty-printed across multiple physical lines, breaking every line-based
  consumer including audit's own window filter. Now compact (`jq -c`).
- Fix: `reify-telemetry` transcript auto-detection took the first find hit; now
  prefers the Claude Code project dir matching cwd, picks the newest candidate by
  mtime, and warns when several sessions qualify. Empty stage windows now produce
  `null` instead of malformed JSON (awk sum replaces paste|bc; bc no longer needed).
- **Removed: ccusage fallback in `reify-telemetry`.** Session-level totals were
  imprecise (whole session, not the run) and needed bun. Transcript parsing is the
  only token source now; counts stay `estimated`/`null` when no transcript is found.
- `ai-folder-research`: stage 01 declares `ICM-TOOLS expect="(search_web|web_search|WebSearch)
  (fetch_url|web_fetch|WebFetch)"`; placeholder `tools/search.sh` and
  `tools/synthesize.sh` deleted (they existed only to be audit-visible and made
  every run deviate from its own contract).
- Tests are hermetic: the suite sandboxes `$HOME` under tmp (previously
  `icm.sh telemetry` wrote to the developer's real `~/.icm`). New cases: JSONL
  validity, ICM-TOOLS matching, reify from transcript, newest-transcript selection.
  45 cases total.
- CI: GitHub Actions workflow runs the suite on ubuntu + macos.

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
