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

Enforcement is a Claude Code PreToolUse hook (`gate-hook.sh`): the harness consults it on
every `mcp__*` tool call, outside the model's control. Register it:

```bash
./installer.sh --hooks    # user scope: merges into ~/.claude/settings.json
```

or commit this to a workspace repo's `.claude/settings.json` so enforcement travels with
`git clone`:

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

Threat model: this defends against a negligent agent (skips a check, sends before
verifying), not a malicious one. The agent can still delete the run dir or fabricate
checker inputs; workspaces that commit `.icm/` make that loud in git history. Enforcement
exists only where the hook is registered, and only in Claude Code: other agents (pi, Codex)
do not read Claude Code hooks, so gates there are advisory. `icm.sh gate-status` makes
absence loud (exit 1 when active runs declare gates but no scope registers the hook);
publish-stage contracts should run it before sending.

Pre-release check (no CI yet): `sh tests/gate.test.sh` must pass.

## Building your own workspace

See `skills/jake-van-clief/ai-folder-research/` as a template. Copy the structure,
write your stage contracts, add a SKILL.md with frontmatter. Run the installer again.

## License

MIT — matching the original ICM project.
