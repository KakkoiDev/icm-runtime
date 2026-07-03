# Improvement Brief - Run Identity and Concurrency (2026-07-03)

> Audience: an agent that will implement improvements to the ICM runtime.
> Status: incident report + design. You decide implementation; respect the constraints in the last section.
> Runtime under discussion (canonical, editable source): `~/Code/icm-runtime/skills/icm/runtime/icm.sh` (POSIX sh, ~1,935 lines), `gate-hook.sh`, `icm-gate.ts`. Line numbers are from the 2026-07-03 reading and will drift; grep the symbol, do not trust the number.

## TL;DR

The runtime has **no run identity**. Every run-scoped command resolves "the run" as *the lexically newest timestamp directory in the workspace* (`latest_run`, icm.sh:121-130), and `cmd_init` (icm.sh:465) never checks whether a run is already open. Consequences:

1. A second `init` in the same workspace **silently orphans** the live run - no warning, no supersede event, no seal. Observed in production on 2026-07-02 (incident below).
2. Concurrent runs of the same workspace are structurally impossible: the older run vanishes from every command's view (stage-done, seal, audit, gates) the instant the newer directory exists.
3. Two concurrent Claude sessions in one repo additionally clobber the shared `.icm/telemetry/transcript-path` (gate-hook.sh writes one unsuffixed file) and cross-attribute tool telemetry (attribution is timestamp windowing against the newest run).

Recommendation: **Option C - a layered `resolve_run` ladder** (`--run` flag > `ICM_RUN_ID` env > per-session pointer file > `latest_run` fallback with a loud warning), plus an **init-time open-run guard** - the guard, not the pointer, is what would have prevented the observed incident.

## Incident: silent run orphaning (2026-07-02, kakkoidev/pr-review)

One Claude session ran the pr-review skill in a meetsone worktree and called `icm.sh init` twice, ~24 s apart. Evidence paths are from that worktree (ephemeral, may be gone when you read this): `.icm/kakkoidev/pr-review/2026-07-02_08-34-36/` (run 1) and `.../2026-07-02_08-35-03/` (run 2), plus `.icm-seals.log` at the worktree root.

| UTC | Event |
|---|---|
| 08:34:36 | `init` #1 -> run 1 created. Its `events.jsonl` gets `run_init` - the only event it will ever have. |
| 08:34:54 | Session runs stage-01 `gather-pr` into run 1; outputs born 08:34:59-08:35:00. |
| 08:35:00 | Same session runs `init` **again** (no error, no warning). |
| 08:35:03 | Run 2 created. From here `latest_run` returns run 2 for every command. |
| 08:35:17 | `gather-pr` re-runs into run 2 - deterministic tool, so outputs are **byte-identical** to run 1's. |
| 08:36-09:16 | Run 2 proceeds through all six stages. Run 1 is frozen forever: stage-01 output + one `run_init`, no `stage_done`, no seal, nothing marking it dead. |
| 08:53:13 | First seal of run 2 - premature: 05-verify/06-report stage_dones were `estimated` with empty model. A second, adjacent defect (see Open questions #7). |
| 09:16:22 | Run 2 re-completed for real and sealed again. Both `.icm-seals.log` lines carry `"run_id":"2026-07-02_08-35-03"`. |

Aggravator: because the stage-01 gather tool is deterministic, run 1's and run 2's outputs were identical - nothing looked wrong at the time. The operator discovered the orphan only by asking "I ran the skill twice, where are the two results?"

This incident was a *same-session* double-init. Two genuinely concurrent sessions would hit the identical collapse **plus** the telemetry clobbering described below.

## Root cause, mechanically

Three facts, each necessary:

1. **Run id is a wall-clock timestamp.** `ts=$(date -u +%Y-%m-%d_%H-%M-%S)` (icm.sh:477); run dir `.icm/<ws>/<ts>` (:484). The only collision handling is a same-second `.2` suffix (:485-490). Nothing else about run identity is ever persisted or consulted.

2. **"Current run" = newest directory.** The core resolver:

   ```sh
   latest_run() {                          # icm.sh:121-130
       ...
       newest=$(cd "$icm_dir" && ls -1 2>/dev/null | sort -r | head -1)
       echo "$newest"
   }
   ```

   It takes a workspace name only - never a run id - and is consumed by every run-scoped command path: `next` (:586), `telemetry` (:977), `stage-done` (:1014), `reify-telemetry` (:1121), `audit` (:1233), `seal` (:1595), `verify-seal` (:1692), `children` (:1868, default). Gate evaluation uses the sibling `latest_runs` (:293), which yields **one newest run per workspace** across all of `.icm/`. No command in the surface accepts an explicit run id except `children <ws> [<run_id>]` (:1861).

3. **`cmd_init` has no open-run check.** It unconditionally `mkdir -p`s a fresh timestamp dir (:465-581). No detection, no warning, no supersede semantics. The only stderr it can emit is the `.gitignore` advice.

Run identity is a side effect of directory listing. The moment a newer directory exists, the older run stops being addressable by anything.

## What breaks under concurrency

- **Same-workspace second init (observed).** Old run orphaned as above. Its gates also go dark instantly: `check_run` iterates `latest_runs`, so an orphaned run's `_active_stage` is never evaluated again - a stage gate that was mid-flight simply stops existing.
- **Two sessions, one repo.** `gate-hook.sh` overwrites the single shared `.icm/telemetry/transcript-path` on every tool call - already documented as "correct only without concurrent sessions" (docs/REFERENCE.md, telemetry honesty section) and partially mitigated for *transcript resolution* by the `CLAUDE_CODE_SESSION_ID` ladder in `find_transcript` (icm.sh:160, ladder documented at :148-159). Run resolution got no such fix. Additionally, `audit`'s tool attribution intersects the **global** `tool-calls.jsonl` timestamps with the **newest run's** stage windows (`_audit_tools_in_window` :1202, window logic near :1339-1369) - two interleaved sessions cross-attribute each other's tool calls.
- **Seal races.** `cmd_seal` seals `latest_run` (:1595). Whoever inits last steals the seal target. A premature seal of the *wrong* run is one `init` away.
- **Nesting assumes one open run per workspace.** `_suspended_runs` (:1713) suspends a parent's gates while a child (linked via `init --caller`, recorded in the child's `run.json`) is open - but it enumerates via `latest_runs`, one run per workspace. Caller links are the proof that run ids are already first-class, addressable values; the runtime just never uses them to resolve "current".
- **No locking, no PID, no session key for runs.** Grep for `flock|lockfile|\.lock|kill -0` over icm.sh + gate-hook.sh: zero matches. `CLAUDE_CODE_SESSION_ID` is used solely by `find_transcript`.

## Design options considered

**Option A - explicit `--run <id>` threaded through skill prose.** init prints the run id; every SKILL.md / stage file passes it to stage-done/seal/audit. Rejected as the *primary* mechanism: every existing skill's prose would need editing (pr-review alone has 6 stage files calling `stage-done kakkoidev/pr-review --stage ...` with no run id), prose-carried identity is exactly the kind of agent-obedience ICM exists to distrust (an agent that drops the flag silently reverts to `latest_run`), and it does nothing for the hook, which composes its own `gate-check` invocation.

**Option B - env var / pointer file.** `ICM_RUN_ID` exported by init dies at the process boundary: `gate-hook.sh` is a PreToolUse hook spawned by the harness, not by the agent's shell - env set in a Bash tool call never reaches it. A pointer file works across that boundary, but note honestly: a pointer alone would **not** have prevented this incident - the second init came from the *same session*, so it would simply have moved that session's own pointer to run 2. The incident fix is the init guard, orthogonal to all three options.

**Option C - layered resolution + init guard.** Both of the above as layers, plus a guard. Recommended.

## Recommendation: Option C

### 1. `resolve_run <ws>` ladder

New helper replacing direct `latest_run` call sites, most-authoritative first - mirroring the codebase's own precedent, `find_transcript`'s documented ladder (icm.sh:148-159: session-env > hook > fallback, degrade loudly):

1. `--run <id>` explicit flag, accepted by every run-scoped command.
2. `ICM_RUN_ID` env - agent-shell convenience; document explicitly that it never reaches hooks.
3. Session pointer file `.icm/<ws>/.current.<session_id>`, written by `init` when a session id is available. Dotfile placement is deliberately backward-safe: `latest_run`'s `ls -1` skips dotfiles and `latest_runs`' find glob matches only timestamp-shaped names (comment at :483 already relies on this shape). Session id sources: agent shell has `CLAUDE_CODE_SESSION_ID` (already production-relied-upon at :166-172); the hook has `session_id` in its stdin JSON (same payload that supplies `transcript_path`), with a code-grounded fallback of `basename "$transcript_path" .jsonl` - the naming contract icm.sh:149-151 already documents. Adding `.session_id // ""` to the hook's existing single jq fork costs nothing.
4. `latest_run` fallback - full backward compatibility - **plus a loud stderr warning whenever more than one open run exists** for the workspace.

### 2. Init guard (the actual incident fix)

`cmd_init` detects an existing **open** run (has an `_active_stage`, not sealed) for the workspace and refuses, printing the open run id and remediation, unless `--force` (or `--caller` - nested runs are cross-workspace anyway). `--force` appends a `run_superseded` tombstone event to the old run's `events.jsonl`, so the old run stops being "open": gates close, `audit` reports honestly, no silent freeze. With this guard, the 2026-07-02 double-init would have failed fast at 08:35:00 with the first run's id on stderr.

### 3. Supporting changes

- `init` records a `"session"` field in `run.json` - tamper-evident for free, since `run.json` is in `_seal_files` (:1567).
- Gate evaluation: replace the `latest_runs`-per-workspace assumption with an `open_runs` enumeration (all runs with an active stage); hook passes `--session <id>` to `gate-check`; gate-check evaluates runs owned by that session plus unowned runs. Two sessions' gates stop cross-firing. Manifest tamper-checks still run for all runs.
- Hook writes `transcript-path.<session_id>` (docs/REFERENCE.md already documents the bracketed suffix `transcript-path[.<session_id>]`; the code never implemented it - the doc is ahead of the code). `find_transcript` reads the suffixed file first.
- New visibility command `icm.sh runs <ws>`: run id, active stage, sealed status, owning session. (Extending `cmd_list` :608 is the alternative; prefer a compact dedicated `runs`.)

## Change inventory

All in `skills/icm/runtime/` unless noted. Line numbers verified 2026-07-03; grep the symbol.

| Site | Line | Change |
|---|---|---|
| `usage()` | icm.sh:56 | document `--run`, `--force`, `runs` |
| `latest_run()` | :121 | becomes final fallback inside new `resolve_run()`; multi-open-run warning |
| `find_transcript()` | :160 | read `transcript-path.<session_id>` before shared file |
| `latest_runs()` | :293 | new sibling `open_runs()` for gate paths |
| `cmd_init()` | :465 | open-run guard + `--force` tombstone; `"session"` in run.json; write `.current.<session_id>` pointer |
| `cmd_next()` | :584 | `--run` + resolver |
| `cmd_list()` | :608 | show open/sealed/session status (or new `cmd_runs`) |
| `cmd_clean()` | :707 | prune stale `.current.*` pointers |
| `cmd_telemetry()` | :961 | `--run` + resolver |
| `cmd_stage_done()` | :991 | `--run` + resolver |
| `cmd_reify_telemetry()` | :1107 | `--run` + resolver |
| `cmd_audit()` | :1218 | `--run` + resolver; per-session transcript for attribution windows |
| `cmd_seal()` | :1583 | `--run` + resolver; ledger line format unchanged (already carries `run_id`) |
| `cmd_verify_seal()` | :1649 | `--run` |
| `_suspended_runs()` | :1713 | iterate `open_runs`; handle >1 open run per workspace |
| `cmd_gate_check()` | :1722 | accept `--session`; evaluate session-owned + unowned open runs |
| `cmd_children()` | :1856 | reconcile existing positional run id with `--run` |
| dispatch table | icm.sh tail | add `runs` |
| gate-hook.sh | jq extraction / transcript-path write / gate-check call | extract `session_id` (fallback: transcript basename); write suffixed transcript-path; pass `--session` |
| icm-gate.ts | - | pi adapter parity note: pi has its own session model; may stay on shared-file + fallback with a documented caveat |

## Migration and compatibility

- **Zero-flag invocations behave identically when exactly one open run exists** - which is every existing single-session workflow. The ladder only changes behavior when it has better information.
- Skill prose stays unmodified. `stage-done <ws> --stage ...` keeps working; the session pointer resolves the run.
- `.icm-seals.log` line format unchanged (already keyed by `run_id`).
- POSIX sh, must parse under bash 3.2 (tests/gate.test.sh case 0 lints this automatically).
- Non-Claude harnesses (pi via icm-gate.ts; Codex advisory-only) have no session id: they live on the `latest_run` fallback. Acceptable; say so in REFERENCE.md.

## Test additions (tests/gate.test.sh - hermetic, tmp HOME, builds its own skill tree)

1. Double-init guard fires; `--force` writes `run_superseded` tombstone to run 1 and run 1 stops being open.
2. `--run` threading through stage-done / seal / audit / verify-seal.
3. Resolution precedence: `--run` beats env beats pointer beats latest.
4. `gate-check --session` with two open runs: own gates fire, other session's do not, manifest tamper-check still global.
5. Fallback warning when >1 open run and no disambiguator.
6. Stale pointer pruning via `clean`.

## Docs to update when implemented

- `docs/REFERENCE.md` - "What tracks the run", "Running a skill, step by step", "Telemetry honesty and concurrency" (the transcript-path suffix there becomes true).
- `usage()` in icm.sh; `CHANGELOG.md`; this file's status line; `docs/README.md` already indexes this brief.

## Risks / open questions

1. **Behavior flip on stale runs.** Today an orphaned run's gates silently vanish (masked by `latest_runs`); under `open_runs` enumeration a forgotten open run's activity gates persist until tombstoned. The guard + tombstone mitigate; call the flip out in the changelog.
2. **Same-session parallel runs of one workspace are scoped OUT.** The pointer maps session -> one run per workspace, and timestamp-window telemetry attribution fundamentally cannot separate two runs interleaved in a single transcript. The guard forbids it without `--force`, and `--force` supersedes rather than parallelizes. Cross-session and cross-workspace concurrency are the supported cases.
3. **Hook stdin `session_id` stability across harness versions.** Specify jq `.session_id // ""` with the transcript-basename fallback (naming contract at icm.sh:149-151).
4. **Pointer-write atomicity.** Single writer per session makes races theoretical; use `printf > tmp && mv` anyway; no flock on stock macOS sh.
5. **`children` positional run id vs `--run`** - alias or deprecate; implementer's choice, document it.
6. **`clean` semantics for open-but-abandoned runs** - should `clean` tombstone instead of delete? Decide during implementation.
7. **Adjacent defect, out of scope here:** `seal` accepted a run whose 05/06 stage_dones were `estimated` with empty model (the 08:53Z premature seal in the incident). `seal` should arguably refuse - or warn - when any stage_done is estimated/missing. File separately.

## Constraints (do not regress)

- `gate-check` runs on **every hooked tool call**; keep the fork budget flat (comments near icm.sh:276 and :326 exist for this reason). The resolver must not add per-call subprocess fan-out.
- gate-hook fail-open-on-broken-checker vs fail-closed-on-deny semantics stay exactly as they are.
- POSIX sh / bash 3.2 parse; hermetic HOME in tests; installed `~/.agents/skills/icm/runtime/` copies are symlinks to this repo - edit here only.
