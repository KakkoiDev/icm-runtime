# Improvement Brief - Telemetry Unification + Determinism (2026-06-19)

> Audience: an agent that will implement improvements to the ICM runtime.
> Status: observations + direction. You decide implementation; respect the constraints in the last section.

## How these observations were produced

A new skill, `publish-to-notion`, was authored and run end to end as a real test:
- Skill source: `~/Code/icm-runtime/skills/cyril-antoni/publish-to-notion/` (`SKILL.md` + `stages/01-render.md`, `stages/02-publish.md`, `stages/03-verify-share.md`).
- Test run (ephemeral, may be gone when you read this): `<scratchpad>/.icm/<namespace>/<skill>/<timestamp>/`. It created a real private Notion page and reached `VERIFIED: PASS`.
- Runtime under test (canonical, editable source): `~/Code/icm-runtime/skills/icm/runtime/icm.sh`, `gate-hook.sh`, `icm-gate.ts`. The installed copies at `~/.agents/skills/icm/runtime/` are symlinks to these. Line numbers below are from this reading and will drift; grep the symbol, do not trust the number.

The install was done WITHOUT `--hooks`, which is itself a finding (see Defect 2/3).

---

## Observation 1: telemetry is scattered across 5 location scopes / 9 artifacts

This is the "many separate telemetry files in different locations" problem. Full inventory:

| # | Artifact | Path (scope) | Written by | When | Contents |
|---|----------|--------------|------------|------|----------|
| 1 | `run.json` | `<run>/telemetry/run.json` (per-run) | `cmd_init` (icm.sh ~412) | on `init` | workspace, run_id, created, stages[], cwd, [caller] |
| 2 | `stages.jsonl` | `<run>/telemetry/stages.jsonl` (per-run) | `cmd_stage_done` (icm.sh ~758) | per stage close | ts, stage, model, tokens_in, tokens_out, counts |
| 3 | `usage.jsonl` | `<run>/telemetry/usage.jsonl` (per-run) | `cmd_stage_done` (icm.sh ~728) | per stage close | per-API-call: ts, model, tokens_in, cache_creation, cache_read, tokens_out, stage |
| 4 | `.stage-telemetry` | `<run>/<stage>/.stage-telemetry` (per-stage) | `cmd_stage_done` (icm.sh ~764) | per stage close | stage, reported_at |
| 5 | `tool-calls.jsonl` | `<project>/.icm/telemetry/tool-calls.jsonl` (per-project) | `_log_start`/`_log_end` (icm.sh ~45) | every `icm.sh` invocation | ts, tool=`icm.sh`, cmd, args[], cwd, ec |
| 6 | `transcript-path` | `<project>/.icm/telemetry/transcript-path` (per-project) | `gate-hook.sh` ~55 | every tool call, only with `--hooks` | harness transcript path |
| 7 | `hook-errors.jsonl` | `<project>/.icm/telemetry/hook-errors.jsonl` (per-project) | `gate-hook.sh` ~84 | on hook breakage | error breadcrumb |
| 8 | `skill-runs.jsonl` | `~/.icm/telemetry/skill-runs.jsonl` (global) | `cmd_reify_telemetry` / close (icm.sh ~656) | on reify / final close | ts, skill, run_id, model, tokens_in, tokens_out, cost_est, cwd, log_dir |
| 9 | `.icm-seals.log` | `<project>/.icm-seals.log` (project root, committable) | `cmd_seal` (icm.sh ~1161) | on `seal` | sha256 digests of run evidence files |

Five different scopes: per-stage dir, per-run `telemetry/`, per-project `.icm/telemetry/`, project root, and `~/.icm/`. To answer "what did this run cost and do," a reader currently joins 1+2+3+5. To answer "did the steps happen," they join 4+5+8. That join is implicit and undocumented.

Constant `ICM_TELEMETRY_DIR=".icm/telemetry"` is defined at icm.sh ~23.

---

## Observation 2 (defect): `stages.jsonl` `tokens_in` conflates cache reads

In the test run, `stages.jsonl` reported `tokens_in: 1029217` for `01-render` - implausible for a 3823-token-out stage. It is the sum of `cache_read` across that stage's `usage.jsonl` calls (337462 + 340006 + 343553 ~= 1.02M). So `tokens_in` is "total context processed including cache," not "new input tokens." `usage.jsonl` (artifact 3) DOES carry the real breakdown (`tokens_in`, `cache_creation`, `cache_read`, `tokens_out` per call); the rollup in `cmd_stage_done` collapses them lossily.

Fix direction: carry all four token fields through the per-stage rollup (and into the global index), so cost is computable and `tokens_in` means new input. `tokens_out` is already reliable.

---

## Observation 3 (defect): model/MCP tool calls are not logged; capture depends on `--hooks`

`tool-calls.jsonl` (artifact 5) logs ONLY `icm.sh` invocations (via the `_log_start` wrapper). It does NOT log model tool calls such as `notion-create-pages` or `notion-fetch`. Those are captured only indirectly: when `gate-hook.sh` is registered (`installer.sh --hooks`), every harness tool call triggers `icm.sh gate-check --tool <name>`, and THAT `icm.sh` call is what lands in `tool-calls.jsonl` with the tool name in `args`. `cmd_audit` (icm.sh ~870, helpers `_audit_tools_in_window` ~854) reconstructs "actual tools" from those records.

Consequence observed: with no `--hooks`, `cmd_audit` printed for every stage `no gate-check records in run (enforcement adapter not registered?)` and `Actual tools in stage window: (none)`. So gates were declared but never enforced, and the tool-call audit had nothing to compare against. The skill's "gated / auditable" promise is inert until `--hooks` is installed.

Fix direction: make this loud. `cmd_audit` and `cmd_gate_status` (icm.sh ~1282) already hint at it; consider failing `audit` with a clear "hooks not installed, gates were advisory only" banner rather than `Deviations: 0`, which reads as "all good."

---

## Observation 4 (defect): transcript selection guesses without the hook

`find_transcript` (icm.sh ~139) uses `.icm/telemetry/transcript-path` (artifact 6, written by the hook) when present, else falls back to newest-session detection. In the test (no hook), `stage-done` printed `2 candidate transcripts; picked newest: .../Code-performance-review/...jsonl` - a transcript from an unrelated project. The resulting `usage.jsonl` happened to look internally consistent with this run, but the selection is a guess and can attribute another session's tokens to this run. The fallback should at least filter candidates by `cwd` match against `run.json.cwd`, and `audit` should flag when the fallback (not the hook) chose the transcript.

---

## Observation 5 (defect): global rollup + `cost_est` only on reify/close

`~/.icm/telemetry/skill-runs.jsonl` (artifact 8) is the only place with `cost_est` and the only cross-project index. The test run never appeared there because `reify-telemetry` / final close was not run (the run was abandoned after `audit`). So the single most useful "what did every run cost" file silently misses any run that is not explicitly closed. Consider writing a provisional global entry at first `stage-done` and upgrading it on reify, so an abandoned run is still visible.

---

## Request A: unify the telemetry

Direction (decide the exact shape):
- Make ONE per-run append-only log the single source of truth: `<run>/telemetry/events.jsonl`, with typed events: `run_init`, `stage_done` (carrying all four token fields), `tool_call`, `gate`, `seal`. This collapses artifacts 2, 3, 4 and the per-run meaning of 5 into one ordered stream. `run.json` (1) can stay as the static header or become the first `run_init` event.
- Derive everything else from that stream: `cmd_stages`, `cmd_audit`, `cmd_telemetry`, `cmd_diff` read the one log instead of joining several.
- Keep exactly two things outside the per-run log, for good reasons: `.icm-seals.log` (project root, committable, must survive `.icm/` being gitignored) and `~/.icm/telemetry/skill-runs.jsonl` (global index, derived rollup - one line per run).
- Document the layering in the README: per-run `events.jsonl` = source of truth; global `skill-runs.jsonl` = derived index; `.icm-seals.log` = tamper anchor. Right now no doc states which file answers which question.

---

## Request B: determinism - "smart model builds, small model executes"

Goal (user's words): the runtime should generate very-easy-to-use skills where the model is only non-deterministic glue between tool calls (and summarization). A small model should be able to execute a skill without inventing steps.

Current reality:
- Stage contracts (`stages/NN-*.md`) describe Process steps in prose. The agent reads them and DECIDES which tool to call and with what args. A small model can skip or mis-call a step. This is the gap the user is pointing at.
- ICM already supports deterministic shell in a skill's `tools/` dir (frozen per run, manifest-covered) for gate checkers and stage processing. Anything callable from bash (gh, curl, jq, git, file ops) can already be a script, not a thought.
- Nuance (this corrects an earlier overstatement that MCP "cannot be scripted"): an MCP server is just a JSON-RPC server over stdio or HTTP, so it IS callable from a script in principle - the model is not technically required. The real constraint is AUTH + TRANSPORT, decided per server:
  - A self-hosted / local stdio MCP server, or any MCP server you hold the endpoint + token for, can be driven directly from a `tools/` script. Pattern: the script spawns its OWN instance of the server (same command + env the harness uses, auth read from a local config it can see) and calls the tool over JSON-RPC. Do not hand-roll the handshake - generic MCP CLI clients (`@modelcontextprotocol/inspector --cli`, `mcptools`/`mcpt`) do `spawn server -> call tool X with args -> print JSON` in one command, so the `tools/` step becomes e.g. `mcpt call <tool> --args ...`. Fully scriptable, fully deterministic.
  - You cannot reuse the harness's already-running instance. A stdio server's transport is the child process's stdin/stdout pipes, owned by the harness process; another process cannot attach to them and there is no shared port. "Already up in the session" does NOT mean "reachable by a script." The script always stands up its own instance (or hits an HTTP endpoint it has the URL + token for).
  - The `mcp__claude_ai_*` connectors used in this session (including the Notion one) are claude.ai-hosted: the OAuth token and endpoint live in the harness, not in a local config a `tools/` script can read. Those stay model-mediated unless you replicate that auth out-of-band. Replicating it = running your own instance of that server (for Notion, `@notionhq/notion-mcp-server`) with your own integration token - the same token cost as calling the REST API directly. Caveat: the claude.ai Notion connector's Notion-flavored-markdown dialect (the `<table>` blocks, the spec we read) may be claude.ai-specific and absent from the OSS server, which likely speaks raw Notion block JSON. Verify that server's tool schema before assuming you get the conversion for free.
  - Often there is a first-class API/CLI that sidesteps MCP entirely. Notion has a REST API (`api.notion.com`) with an integration token (this monorepo already uses one - `NOTION_API_KEY` drives the `pnpm notion:fetch-*` scripts). A `tools/` script can publish a page directly (`notion-publish file.md`), removing the model from the call. Cost: the claude.ai Notion MCP converts Notion-flavored markdown to blocks server-side; the raw REST API takes its own block JSON, so a direct script must own the markdown-to-blocks conversion (md-to-notion-blocks libraries exist). You trade the MCP's free conversion for determinism.
  - Genuinely model-only: harness built-ins like `WebFetch`/`WebSearch` have no shell entrypoint and stay model-issued.

Direction:
- For bash-reachable work: push it into `tools/` scripts so the model does not reason about it. The `publish-to-notion` test had the model hand-build the `<table>`/mermaid conversion in stage 01 - that is exactly the kind of step a deterministic renderer script should own.
- Preferred determinism path: when a step's tool has a bash-reachable API/CLI or a self-hostable MCP, wrap it in a `tools/` script so the step is a script call, not a thought. Apply this aggressively - it is the core of "small model executes."
- For steps that genuinely must go through a harness-held connector (auth not scriptable) or a built-in: make the stage contract carry a machine-checkable tool-call spec, not prose - exact tool name + an argument template that maps named prior-stage outputs to argument fields. The small executor's only freedom becomes filling values and gluing stage N output into stage N+1 input. Today `ICM-TOOLS` (e.g. `<!-- ICM-TOOLS expect="(notion-create-pages|notion-update-page)" -->`) only DECLARES expected tool names for audit; extend it (or add a sibling directive) into an execution spec the executor must satisfy and the gate can check.
- Split the lifecycle explicitly: a "build" pass (smart model, run once) generates the `tools/` scripts and the per-stage tool-call specs; an "execute" pass (small model) just follows them. This is the durable form of "smart builds, small executes," and it maps onto the create/maintain workflows already drawn in the skill-discoverability proposal.

Concrete first target: pick `publish-to-notion` as the pilot, and make it the proof that a skill can be (almost) fully scripted:
- Stage 01: move the markdown-to-Notion-blocks conversion into a pure, testable `tools/render.*` script.
- Stage 02: replace the `notion-create-pages` MCP call with a `tools/notion-publish` script that hits `api.notion.com` directly with an integration token (the user's `notion-publish file.md` idea). This removes the model from the publish call entirely.
- Stage 03: same - a `tools/notion-fetch` script reads the page back for the verify check.
- Net result: the only model role left is gluing inputs and judging the verify receipt. Measure whether a small model can execute it without deviation. Document the token-handling (where the Notion integration token comes from) since it is now a script dependency, not a harness connector.

---

## Further improvements (ranked)

Beyond Requests A and B. Tagged by type and grounded in authoring/running `publish-to-notion`. The reliability lens: correctness items (#2, #3) and the fail-open hook discipline matter more than feature count - a tool that reports wrong token attribution or clobbers state under concurrency is not "reliable" no matter how many features it has.

1. [real-friction, small] **Remove per-`SKILL.md` boilerplate (DRY).** The Runtime / Per-Stage Telemetry / Audit / Seal sections are copied near-verbatim across `skills/cyril-antoni/signoff-proposal/SKILL.md` and `skills/cyril-antoni/publish-to-notion/SKILL.md` (this brief's author pasted them). Change the `icm.sh` command surface and every SKILL.md silently goes stale. Direction: the runtime owns those sections (generate them into the skill at build time, or have the skill reference a single shared include) so a SKILL.md carries only skill-specific content. Needs a mechanism decision: template-at-scaffold vs runtime-injected - Claude Code loads a static SKILL.md, so injection must happen when the skill is written, not at trigger time.

2. [real-friction, small, reliability] **Drop the `--tokens-in/--tokens-out <approx>` ask; auto-detect `--model`.** Stage "After Output" blocks tell the model to pass approximate token counts to `stage-done`. Models cannot reliably self-estimate token usage, and `cmd_reify_telemetry` (icm.sh ~774) recomputes the real counts from the transcript. So the ask is busywork that yields garbage until reify. The model name (`--model`) is likewise hand-passed and a wrong value poisons cost. Direction: contracts call `stage-done --stage X` only; the runtime/hook fills model + tokens from the transcript. Removes a whole class of human/model error.

3. [bug, reliability] **`transcript-path` clobbers under concurrency.** `gate-hook.sh` (~55) does `... > .icm/telemetry/transcript-path` - a single file per project, overwritten on every tool call. Two concurrent sessions in the same project overwrite each other, so `find_transcript` (icm.sh ~139) and `stage-done` attribute the wrong session's tokens. Direction: key the path by run_id (or PID), e.g. `transcript-path-<run_id>`, written into the active run's telemetry dir.

4. [heavy] **`skill new` scaffolder.** Today a skill is made by copying an existing one. `icm.sh new-skill <ns>/<name> --stages a,b,c` should emit a skill-specific-only SKILL.md (per #1), stage stubs with structured headers (per #6), a `tools/` dir, and a starter eval (per #5). This is the core enabler of "generate very easy to use skills," and the natural home for the dedup-on-create check from the skill-discoverability proposal.

5. [heavy] **Per-skill eval/test harness.** The repo tests the runtime (`tests/gate.test.sh`, `tests/pi-driver.ts`) but not individual skills. The build/execute split is unverifiable without it: run a skill against a fixture, assert its receipts and gate outcomes, with a cheap/mock model or a replay. This is the same "manual test / eval" gate drawn in the proposal, mechanized.

6. [heavy, do before #4/#5] **Structured stage front-matter, replacing the HTML-comment directives.** `ICM-GATE` / `ICM-TOOLS` are HTML comments parsed by regex; that parser family already caused the bash-3.2 outage (`RUNTIME-IMPROVEMENTS-2026-06-15.md`). A YAML stage header is more robust and is the natural carrier for the machine-readable tool-call execution spec from Request B. Land this before the scaffolder and eval harness, since both build on the stage format.

7. [meta] **Eat your own dogfood.** `skills/<author>/` has no index, no owners, no catalog - exactly the discoverability problem just speced for the team. Apply the frontmatter contract + a generated catalog to icm's own skill library.

8. [portability] **Cross-harness tool-name normalization.** A `tools` regex written for Claude Code names (`mcp__claude_ai_*`) will not match Codex/pi names (README already flags this). Add an alias/normalization layer so gate matching and the execution spec hold across all target harnesses - otherwise icm's multi-agent promise is Claude-Code-only in practice.

Sequencing: #1 and #2 are tiny, do them now. #3 is a contained bugfix. #6 lands before #4 and #5. Resist turning icm into a framework with more surface area than the skills it runs - every feature here is also a thing that can break on `bash 3.2` behind a `.*` hook.

## Constraints to respect (do not regress these)

- macOS ships `bash 3.2`. The runtime already ate one production outage from a `case` inside `$( )` that bash 3.2 mis-parses (see `RUNTIME-IMPROVEMENTS-2026-06-15.md`). Test under `/bin/bash`, not just a modern bash.
- `gate-hook.sh` runs on EVERY tool call (matcher `.*`). It must stay fast outside `.icm` projects and FAIL OPEN on a broken checker, never fail closed and brick the session. Do not move logic into the hot path.
- Tamper-evidence must survive: `.manifest` (sha of frozen contracts), `.icm-seals.log`. Any telemetry refactor must keep what `cmd_seal` (icm.sh ~1129) digests coherent.
- Do not break existing skills: `cyril-antoni/signoff-proposal`, `jake-van-clief/ai-folder-research`. They read the current telemetry shape; migrate or shim.
- Closing stages in real time matters: batching `stage-done` yields zero-width windows and null per-stage counts (documented in skill conventions). Keep that property.

## Open questions for the implementer

- Unified per-run log: one `events.jsonl`, or keep `run.json` as a static header + one event stream? (Recommend header + stream.)
- Should the global `skill-runs.jsonl` get a provisional entry at first `stage-done` (so abandoned runs are visible), upgraded on reify?
- Execution spec format: extend `ICM-TOOLS` semantics, or add a new `ICM-CALL` directive with arg templates? The former keeps one concept; the latter separates "audit expectation" from "execution instruction."
- How far to push determinism before it fights the "non-deterministic glue" goal - i.e., which steps are deliberately left to the model (summarization, judgement) vs scripted.
