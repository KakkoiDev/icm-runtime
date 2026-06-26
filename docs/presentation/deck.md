<!--
ICM Runtime - technical deck. Plain markdown; slides split on `---`.
Diagrams are pre-rendered SVGs in diagrams/ (source: diagrams/*.mmd).
Rebuild everything (SVGs + this deck's HTML) in one step:  sh build.sh
Renders in any markdown viewer too: GitHub shows the committed SVGs inline.
-->

# ICM Runtime

## A beta experiment in auditable AI agents

Folders as orchestration - so the harness can check the agent, not just trust it.

`github.com/KakkoiDev/icm-runtime` - MIT - beta

---

# The problem

Every multi-agent framework orchestrates **in code**.

- CrewAI, LangChain, AutoGen: control flow lives inside Python objects.
- Opaque. Hard to **audit** what ran.
- Hard to **cost** - tokens hide inside the framework.
- Hard to **verify** the agent did what the spec said.

The orchestration is invisible because it is buried in code.

---

# Two things it gives you

**Author** - scaffold a multi-stage agent skill as markdown contracts + small shell scripts (`icm.sh new-skill`). No orchestration code.

**Enforce** - at runtime the engine freezes those contracts, gates tool calls, meters tokens, and seals the evidence.

Skill creator + run enforcer.

---

# The inversion

Put the orchestration in the **filesystem**, where you can see it.

![Five layers: a skill holds numbered stage contracts; a run holds state; tracking and enforcement wrap it](diagrams/inversion.svg)

The runtime owns state. The model is glue between deterministic checkpoints.

---

# Anatomy of a skill

```
kakkoidev/icm-demo/
  SKILL.md            # metadata + how to drive it
  stages/
    01-lifecycle.md   # frozen into the run as CONTEXT.md
    02-enforcement.md
    03-telemetry-seal.md
  checks/*.sh         # gate checkers (frozen, hashed)
  tools/*.sh          # deterministic stage scripts (frozen, hashed)
  eval/*.test.sh      # offline verification
```

Markdown + bash. No framework to learn.

---

# Lifecycle

![Lifecycle: init, then the stage loop (read contract, do work, stage-done), then audit and seal](diagrams/lifecycle.svg)

The model only lives inside the stage loop. Everything around it is deterministic.

---

# Gates: mechanical preconditions

Declared in the stage contract:

```
<!-- ICM-GATE tools="demo_publish" run="checks/ready.sh" -->
```

- `tools=` is a regex matched against the tool name.
- `run=` is a checker; exit 0 = pass. The hook denies on non-zero.
- **Scoped to the active stage only** - fires while its stage is open,
  not before, not after. (Fixed a cross-stage deadlock in v0.6.0.)

Preconditions are enforced, not suggested.

---

# Tamper-evidence: two layers

**Layer 1 - manifest.** sha256 of every frozen `CONTEXT.md`, `checks/`,
`tools/`. Edit a contract mid-run -> gate-check DENIES: "contract tampered".

**Layer 2 - seal.** sha256 of `run.json + events.jsonl + .manifest`, appended
to `.icm-seals.log` (committable, lives at project root).
Edit a sealed file after the fact -> `verify-seal` shows MISMATCH.

You cannot quietly rewrite history of a run.

---

# Token telemetry: four fields

Per stage, read from the session transcript at `stage-done`:

| field | meaning |
|---|---|
| `tokens_in` | new input tokens |
| `cache_creation` | cache write |
| `cache_read` | cache hit |
| `tokens_out` | output |

Read from the transcript, **never hand-passed by the model**.
Reified post-run with exact counts. The model cannot lie about cost.

---

# Cross-harness by normalization

The same gate matches every harness:

```
Claude Code:  mcp__claude_ai_Notion__notion-fetch
pi / Codex:   notion-fetch
```

Runtime strips the `mcp__<server>__` wrapper and folds built-in aliases
(`WebSearch` -> `web_search`). Write `tools="notion-fetch"` once; it matches
both. Enforcement adapters: `gate-hook.sh` (Claude Code), `icm-gate.ts` (pi).

---

# Live demo - a gate, in 4 commands

```
RUN=$(icm.sh init kakkoidev/gate-demo)
icm.sh gate-check --tool publish               # DENY: receipt missing
echo ok > $RUN/01-publish/output/receipt.md
icm.sh gate-check --tool publish               # ALLOW
```

The gate blocks `publish` until `output/receipt.md` exists. Create the file, the call is let through. Files persist - open them. Offline, ~20 seconds.

---

# Demo output (backup if no terminal)

```
$ icm.sh gate-check --tool publish
DENY ... 01-publish: checker failed: checks/receipt.sh   # blocked: no receipt
$ echo ok > $RUN/01-publish/output/receipt.md
$ icm.sh gate-check --tool publish
ALLOW (exit 0)                                           # receipt present: allowed
```

The DENY is the win - the gate refused the action until its precondition held.

---

# What's real, what's open

**Real:** gates fire live in Claude Code; tamper-evidence holds; 119 tests, CI on Linux + macOS; offline, bash-only.

**Open:** pi adapter runtime-untested; a gate firing on a real model tool call mid-workflow (today's is hand-driven) needs MCP; beta - a bet, not a product.

Testers welcome.

---

# Try it, then tell me

A bet: mechanical, tamper-evident checks on agents are worth having. Worth pursuing?

```
git clone github.com/KakkoiDev/icm-runtime && ./installer.sh
```

Full offline self-test - every mechanism, one command:

```
bash ~/.agents/skills/kakkoidev/icm-demo/tools/sandbox-tour
```

ICM method: Van Clief & McDermott, arXiv:2603.16021
