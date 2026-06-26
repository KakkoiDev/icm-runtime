# ICM Runtime - 5-minute talk track

Audience: engineers. Target ~700 words / ~5 min at 150 wpm.
Centerpiece: live `sandbox-tour` (offline, ~2s). One message: we replaced the
multi-agent framework with folders, and got auditable, tamper-evident,
token-metered AI workflows as a side effect.

One slide per timestamp. Renders as a deck (slides split on `---`).

---

## [0:00-0:30] Hook

Agents skip verification steps, and you only find out later. The usual answer is
"tell the model to check" - and hope it listens.

I wanted the check to be mechanical: the harness blocks the action until the
check passes, and leaves a record you can't quietly edit. I built that as the ICM
runtime. It's beta - this is an honest look, not a sales pitch.

---

## [0:30-1:30] The model

Four nouns. A **skill** is a workflow, namespaced like `kakkoidev/icm-demo`.
Inside it, **stages** are numbered markdown files - `01-`, `02-`, `03-`. When a
run starts, each stage file is frozen into the run as its `CONTEXT.md`: a
contract the agent cannot silently rewrite. A **run** is a timestamped
directory under `.icm/`. And **enforcement** is a harness hook that fires on
every tool call.

The key idea: the runtime owns all the state. The model is just the
non-deterministic glue between deterministic checkpoints.

---

## [1:30-2:15] The payoff

Because the runtime owns state, you get three properties for free, on every run.

- **Gates.** A stage declares a precondition as a comment:
  `ICM-GATE tools="..." run="checker"`. The hook runs the checker before letting
  the tool through. Mechanical, not vibes.
- **Token telemetry.** Four fields per stage - new input, cache creation, cache
  read, output - read from the transcript at stage close. The model cannot lie
  about cost.
- **Seals.** A sha256 digest of the run's evidence. Edit a sealed file and the
  digest no longer matches.

Let me show you all of it. Offline. No network, no credentials, two seconds.

---

## [2:15-4:30] LIVE DEMO

Run it live in a scratch dir - 4 commands, files persist, ~20 seconds:

```
ICM=~/.agents/skills/icm/runtime/icm.sh
RUN=$(bash $ICM init kakkoidev/gate-demo)
bash $ICM gate-check --tool publish               # DENY: receipt missing
echo ok > $RUN/01-publish/output/receipt.md
bash $ICM gate-check --tool publish               # ALLOW
```

Narrate: "The gate blocks `publish` until the stage produces `receipt.md`. First
call, no receipt - DENY, and it names the failed checker. I create the receipt.
Same call - ALLOW. The harness refused the action until the precondition held; the
model cannot route around it."

`publish` stands in for a real action (deploy, send). For the exhaustive offline
self-test of every mechanism (scoping, normalization, seal, tamper), run
`icm-demo`'s `sandbox-tour` - but keep that off stage; this one gate is the idea.

---

## [4:30-5:00] Close

What's real: gates fire live in Claude Code, tamper-evidence holds, 119 tests on
Linux and macOS. What's open: the pi adapter is runtime-untested, and a gate firing
on a real model tool call mid-workflow (today's gate was hand-driven) needs MCP, so
you didn't see that part today.

The bet: mechanical, tamper-evident checks on agents are worth having. Is that
worth pursuing? One command to try it - and tell me.

---

## Backup if you cannot share a terminal

Fall back to the "demo output" slide in the deck - the same eight steps, pre-run.
Read the DENY/ALLOW/SEAL/MISMATCH lines off the slide in the same order.

---

## Pre-flight (do this before walking in)

- `bash ~/.agents/skills/kakkoidev/icm-demo/tools/sandbox-tour` once, cold.
  Confirms it prints all 8 steps and self-cleans. Took ~2.1s last run.
- Terminal font large enough to read from the back row.
