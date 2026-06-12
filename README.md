# ICM Runtime — Folder Structure as Agent Architecture

**Interpretable Context Methodology (ICM)** implemented as reusable coding agent skills.

> ICM was created by **Jake Van Clief** ([@RinDig](https://github.com/RinDig))
> and **David McDermott** in their paper
> *"Interpretable Context Methodology: Folder Structure as Agentic Architecture"*
> ([arXiv:2603.16021](https://arxiv.org/abs/2603.16021), March 2026).
>
> This runtime is a coding-agent-native implementation of their methodology.
> The ideas — the five-layer context hierarchy, stage contracts, folder-based
> orchestration — are theirs.
>
> **Original repository:** [RinDig/Interpreted-Context-Methdology](https://github.com/RinDig/Interpreted-Context-Methdology)
>
> This project packages ICM as installable skills for coding agents that support
> the [Agent Skills](https://agentskills.io/) standard (PI, Claude Code, Codex, and others).

## What it does

ICM replaces multi-agent framework orchestration (CrewAI, LangChain, AutoGen) with
filesystem structure. Numbered folders = pipeline stages. Markdown files = prompts
and context. A single agent, reading the right files at the right moment, does the
work that would otherwise require a multi-agent framework.

## Install

```bash
git clone <repo-url> ~/Code/icm-runtime
cd ~/Code/icm-runtime
./installer.sh
```

The installer symlinks skill directories into `~/.agents/skills/` (PI, Codex - namespaced,
discovered recursively) and into `~/.claude/skills/` (Claude Code - flattened, since Claude Code
discovers skills only one level deep). If your coding agent doesn't follow symlinks during skill
discovery, use `--copy` instead:

```bash
./installer.sh --copy
```

Restart your coding agent and the skills are available.

Symlink mode: edits in `~/Code/icm-runtime/` propagate immediately.
Copy mode: re-run `./installer.sh --copy` to pick up changes.

Uninstall: `./installer.sh --remove`

## Included Skills

| Skill | What it does |
|-------|-------------|
| `icm` | Runtime mechanics (init, run stages, list, diff, clean). Used internally by workspace skills. |
| `ai-folder-research` | 3-stage pipeline: research a topic → draft analysis → polish into final output. |

## Commands

```
/ai-folder-research                    # Start new research pipeline
/ai-folder-research run                # Continue latest run
/ai-folder-research run stage 02       # Re-run a specific stage
/ai-folder-research list               # Show run history
/ai-folder-research diff               # Diff last two completed runs
/ai-folder-research clean --keep 3     # Prune old runs
```

## How it works

1. User says `/ai-folder-research`
2. Agent calls `icm.sh init` → creates `.icm/` in working directory with timestamped run
3. Stage contracts are frozen per run for auditability
4. Agent executes each stage's Process steps, writes output to `.icm/<workspace>/<timestamp>/<stage>/output/`
5. Output of one stage becomes input to the next
6. Human can edit any intermediate output — the next stage picks up changes

## Observability

### Tool logging
Every `icm.sh` invocation in a project with `.icm/` writes to
`.icm/telemetry/tool-calls.jsonl`. Each line records: timestamp, command, args,
working directory, exit code.

### Run telemetry
Each run gets `telemetry/run.json` (workspace, run_id, created timestamp, stage
count, cwd). Workspace skills write a summary to `~/.icm/telemetry/skill-runs.jsonl`
after completion. The global file is the single place to find every skill run across
all projects.

**Per-stage token tracking is MANDATORY.** After every stage, workspace skills call
`icm.sh stage-done` which writes to `telemetry/stages.jsonl`, drops a
`.stage-telemetry` marker, and snapshots the stage's usage events from the live
session transcript into `telemetry/usage.jsonl` (timestamps and token counts per
API call, no conversation content). Counts are computed on the spot and survive
harness transcript cleanup. `stage-done --full` additionally freezes the raw
transcript window into the stage dir for forensics; that IS conversation content,
so leave it gitignored unless you decide otherwise. The transcript path comes from
the gate hook when registered, else newest-session detection. `icm.sh
reify-telemetry` remains as a post-hoc fallback. The audit command flags any
completed stage that lacks stage-done telemetry.

### Seal
`icm.sh seal <workspace>` appends a sha256 digest line for the latest run's
evidence files to `.icm-seals.log` at the project root; commit that file (it
lives outside the gitignored `.icm/`). `icm.sh verify-seal <workspace>` recomputes
and exits 1 on mismatch; `verify-seal --all` checks every sealed run still on
disk (pruned runs are skipped, not failed). This is tamper evidence, not prevention: it converts a
silent telemetry edit into a visible digest mismatch and git diff, within the
same negligent-not-malicious threat model as gates.

### Audit
`icm.sh audit <workspace>` does two checks: (1) verifies every completed stage has
per-stage telemetry (`stage-done` was called), and (2) compares expected tools,
declared per stage via `<!-- ICM-TOOLS expect="..." -->`, against actual harness
tool calls recorded in the telemetry log by the gate enforcement adapter. Produces
a deviation report including per-stage token usage summary. Actual records exist
only where an adapter is registered; audit says so instead of guessing.

### Deterministic tools
Skills can include a `tools/` directory with shell scripts for gate checkers and
stage processing. Tools are frozen into each run and added to the tamper-evidence
`.manifest`. Expected harness tools are declared with an ICM-TOOLS line in the
stage contract (EREs, unanchored, one line per contract), frozen and manifest-covered
like gates.

## Stage gates (harness-enforced)

Stage contracts are prose, and prose does not bind: an agent can skip a verification step
it knows about. Gates make a stage's verification mechanical. A stage declares one line:

```
<!-- ICM-GATE tools="mcp__claude_ai_Slack__slack_send_message(_draft)?" run="checks/preservation.sh" -->
```

- `tools` is an ERE matched (unanchored) against the tool name the harness reports.
- `run` is a checker command executed with cwd = the run's stage dir. Exit 0 = gate passes.
  If its first token is a file frozen at the run root (e.g. `checks/preservation.sh`), it is
  resolved there. The degenerate form needs no script:
  `run="grep -Eq '^RESULT: PASS$' output/preservation.md"`.

`icm.sh init` freezes the gate with the contract (plus the skill's `checks/` dir) into the
run and writes a sha256 `.manifest`. `icm.sh gate-check --tool <name>` evaluates the latest
run per workspace and exits 1 with `DENY` lines when a matching gate fails. Every manifest
entry is verified first, so editing the frozen contract, deleting the gate line, or touching
a frozen checker all deny as tampered.

Enforcement runs in the harness, outside the model's control, with one adapter per agent:

- **Claude Code:** `gate-hook.sh`, a PreToolUse hook consulted on every tool call
  (matcher `.*`), so built-in tools (WebSearch, WebFetch, Bash, ...) are gated and
  logged, not just MCP tools. Outside `.icm` projects it exits in ~25ms; inside,
  a full gate evaluation is ~60-80ms per call. Re-run `installer.sh --hooks` to
  migrate a pre-0.6 `mcp__.*` registration.
- **pi:** `icm-gate.ts`, a `tool_call` extension that blocks while `gate-check` denies.

Register both at once (each is skipped if its harness is absent):

```bash
./installer.sh --hooks    # Claude Code: ~/.claude/settings.json; pi: ~/.pi/agent/extensions/
```

or commit this to a workspace repo's `.claude/settings.json` so enforcement travels with
`git clone`:

```json
{
  "hooks": {
    "PreToolUse": [
      {
        "matcher": ".*",
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

Threat model: this defends against a negligent agent (skips a check, sends before
verifying), not a malicious one. The agent can still delete the run dir or fabricate
checker inputs; workspaces that commit `.icm/` make that loud in git history. Enforcement
exists only where an adapter is registered; agents without one (Codex) see gates as
advisory only. `icm.sh gate-status` makes absence loud: exit 1 when active runs declare
gates but no scope registers enforcement, and (harness-aware) when running inside Claude
Code without a Claude-scope registration, since a pi-only registration is not enforcement
there. Publish-stage contracts should run it before sending.

Tool naming caveat for cross-harness gates: a `tools` regex written against Claude Code's
MCP naming (`mcp__claude_ai_Slack__slack_send_message`) will not match a differently named
pi tool. Matching is unanchored, so write the tool's core name
(`slack_send_message(_draft)?`) when a gate must bind in both harnesses. The same applies
to built-in tools: Claude Code says `WebSearch`/`WebFetch`, pi says `search_web`/`fetch_url`;
use alternation (`(search_web|WebSearch)`) in gates and ICM-TOOLS lines.

CI runs `sh tests/gate.test.sh` on ubuntu and macos (`.github/workflows/test.yml`);
run it locally before release too. The suite is hermetic: it sandboxes `$HOME`
under a tmp dir.

## Building your own workspace

See `skills/jake-van-clief/ai-folder-research/` as a template. Copy the structure,
write your stage contracts, add a SKILL.md with frontmatter. Run the installer again.

## License

MIT — matching the original ICM project.
