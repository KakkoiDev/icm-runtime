# ICM Runtime - 5-minute talk track

Audience: engineers. Target ~700 words / ~5 min at 150 wpm.
Centerpiece: live `sandbox-tour` (offline, ~2s). One message: we replaced the
multi-agent framework with folders, and got auditable, tamper-evident,
token-metered AI workflows as a side effect.

One slide per timestamp. Renders as a deck (slides split on `---`).

---

## [0:00-0:30] Hook

Every multi-agent framework you have seen - CrewAI, LangChain, AutoGen -
orchestrates agents in code. The control flow lives inside Python objects.
That makes it opaque: you cannot easily see what ran, what it cost, or whether
the agent did what the spec said.

ICM inverts that. The orchestration lives in the filesystem. Numbered folders
are the pipeline. Markdown files are the contracts. A single agent reads the
right file at the right moment.

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

Run: `bash ~/.agents/skills/kakkoidev/icm-demo/tools/sandbox-tour`

Narrate the eight steps as they print:

1. **Stage scoping** - stage-02 gate silent while 01 active. ALLOW.
2. **Gate DENY** - close 01; 02's precondition (`ready.md`) is missing. DENY.
3. **Normalization** - same call as `mcp__...__demo_publish`. Still DENY (wrapper stripped, matched).
4. **Non-gated** - `Read`, not named by the gate. ALLOW.
5. **Gate ALLOW** - create `ready.md`. Precondition met. ALLOW.
6. **Seal + verify** - anchor the digests. SEAL OK.
7. **Seal tamper** - inject a fake event into `events.jsonl`. SEAL MISMATCH, exit 1.
8. **Manifest tamper** - edit the frozen `CONTEXT.md`. DENY, "contract tampered".

That is the whole value proposition in your terminal: deny, allow, cost, tamper.

---

## [4:30-5:00] Close

Install once, skills are just markdown plus bash, every run is sealed and
token-tracked.

Where it stands: beta. 114 tests, CI on Linux and macOS, six skills, MIT. We
just added versioning, a release workflow, and eval coverage; the one honest gap
is the pi adapter's runtime, still unverified without a pi environment. Next step
is cutting the tagged release.

That is ICM: the framework is a folder, and the folder proves what it did.

---

## Backup if you cannot share a terminal

Fall back to the "demo output" slide in the deck - the same eight steps, pre-run.
Read the DENY/ALLOW/SEAL/MISMATCH lines off the slide in the same order.

---

## Pre-flight (do this before walking in)

- `bash ~/.agents/skills/kakkoidev/icm-demo/tools/sandbox-tour` once, cold.
  Confirms it prints all 8 steps and self-cleans. Took ~2.1s last run.
- Terminal font large enough to read from the back row.
