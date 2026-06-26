# ICM Runtime - 5-minute talk track

Audience: engineers. Target ~700 words / ~5 min at 150 wpm.
Centerpiece: live `sandbox-tour` (offline, ~2s). One message: we replaced the
multi-agent framework with folders, and got auditable, tamper-evident,
token-metered AI workflows as a side effect.

---

## [0:00-0:30] Hook

Every multi-agent framework you have seen - CrewAI, LangChain, AutoGen -
orchestrates agents in code. The control flow lives inside Python objects.
That makes it opaque: you cannot easily see what ran, what it cost, or whether
the agent did what the spec said. ICM inverts that. The orchestration lives in
the filesystem. Numbered folders are the pipeline. Markdown files are the
contracts. A single agent reads the right file at the right moment.

## [0:30-1:30] The model

Four nouns. A **skill** is a workflow, namespaced like `kakkoidev/icm-demo`.
Inside it, **stages** are numbered markdown files - `01-`, `02-`, `03-`. When a
run starts, each stage file is frozen into the run as its `CONTEXT.md`: a
contract the agent cannot silently rewrite. A **run** is a timestamped
directory under `.icm/`. And **enforcement** is a harness hook that fires on
every tool call.

The key idea: the runtime owns all the state. The model is just the
non-deterministic glue between deterministic checkpoints. Each stage reads its
frozen contract, does work, writes to its `output/`, and closes. The next stage
picks up from there.

## [1:30-2:15] The payoff

Because the runtime owns state, you get three properties for free, on every
run.

One - **gates**. A stage declares a precondition as a comment:
`ICM-GATE tools="..." run="checker"`. The hook runs the checker before letting
the tool through. Preconditions are mechanical, not vibes.

Two - **token telemetry**. Four fields per stage - new input, cache creation,
cache read, output - read straight from the session transcript at stage close.
Never hand-passed by the model, so it cannot lie about cost.

Three - **seals**. A sha256 digest of the run's evidence, appended to a
committable log. Edit a sealed file after the fact and the digest no longer
matches. Tamper-evident.

Let me show you all of it. Offline. No network, no credentials, two seconds.

## [2:15-4:30] LIVE DEMO

Run: `bash ~/.agents/skills/kakkoidev/icm-demo/tools/sandbox-tour`

Narrate as the eight steps print:

1. **Stage scoping.** The stage-02 gate is silent while stage 01 is active.
   ALLOW. Gates only fire for the stage you are actually in - no cross-stage
   deadlocks.
2. **Gate DENY.** I close stage 01. Now stage 02 is active and its precondition
   - a `ready.md` file - is missing. `demo_publish` is DENIED. The checker
   failed, by name: `checks/ready.sh`.
3. **Cross-harness normalization.** Same call, but wrapped as
   `mcp__claude_ai_Notion__demo_publish` - the Claude Code MCP form. Still
   DENIED. The runtime stripped the wrapper and matched the same gate. Write the
   gate once, it works on Claude Code, pi, and Codex.
4. **Non-gated tool.** `Read` - the gate does not name it. ALLOW. No tax on
   tools you did not gate.
5. **Gate ALLOW.** I create `ready.md`. Precondition met. `demo_publish` now
   passes.
6. **Seal + verify.** Anchor the evidence digests. SEAL OK.
7. **Seal tamper.** I inject a fake usage event into `events.jsonl` - faking
   token cost. `verify-seal` catches it: SEAL MISMATCH. Exit 1.
8. **Manifest tamper.** I append one comment to the frozen `CONTEXT.md`. Next
   gate check: DENY, "contract tampered" - sha256 mismatch with the manifest.
   You cannot quietly edit a contract mid-run.

That is the whole value proposition running in your terminal. Deny, allow,
cost, tamper - all visible, all offline.

## [4:30-5:00] Close

Install once, skills are just markdown plus bash, you run them with one command,
and every run is sealed and token-tracked. Where it stands: beta. 64 test cases,
CI on Linux and macOS, six skills shipped, MIT licensed. The honest gaps: no
release/versioning yet, the pi adapter is shipped-but-untested, and a couple of
skills still lack eval suites. Next step is cutting a real tagged release.

That is ICM: the framework is a folder, and the folder proves what it did.

---

## Backup if you cannot share a terminal

Fall back to the captured output on the "demo output" slide - the same eight
steps, pre-run. Read the DENY/ALLOW/SEAL/MISMATCH lines off the slide in the
same order.

## Pre-flight (do this before walking in)

- `bash ~/.agents/skills/kakkoidev/icm-demo/tools/sandbox-tour` once, cold.
  Confirms it prints all 8 steps and self-cleans. Took ~2.1s last run.
- Terminal font large enough to read from the back row.
