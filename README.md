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

The installer symlinks skill directories into `~/.agents/skills/`. If your coding
agent doesn't follow symlinks during skill discovery, use `--copy` instead:

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

## Building your own workspace

See `skills/jake-van-clief/ai-folder-research/` as a template. Copy the structure,
write your stage contracts, add a SKILL.md with frontmatter. Run the installer again.

## License

MIT — matching the original ICM project.
