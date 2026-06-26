# ICM Runtime - Hardening Report and Improvement Backlog (2026-06-15)

## Context

While driving a workspace skill (`signoff-proposal`) inside a project that has a
`.icm/` dir, **every tool call in the session started failing** with:

```
icm.sh: line 1289: syntax error near unexpected token `;;'
```

Root cause: `gate-hook.sh` is a Claude Code `PreToolUse` hook registered with matcher
`.*`, so it runs `icm.sh gate-check` on every tool call inside an ICM project. `icm.sh`
had a `case` pattern ending in `)` inside a `$( )` command substitution in
`cmd_children()`. **bash 3.2** (macOS `/bin/bash`) mis-parses that construct - it reads
the pattern's `)` as closing the `$(`, loses the `case`, and chokes on the `;;`. Authored
and tested on newer bash, where it parses fine, so it shipped.

Because the hook treated *any* non-zero exit from `gate-check` as a denial, one
unparseable line denied **every** tool call and trapped the session: the agent could not
even use `Edit`/`Read` to repair `icm.sh`, since those are tools gated by the same broken
hook. It had to be patched from outside the agent.

The findings below were produced by fixing the immediate bug, then re-running the skill
and adversarially reviewing both the fixes and the surrounding runtime with a 3-agent
review workflow (red-team the hook fix, test-adequacy of the parse lint, completeness
critic on the backlog).

---

## Part A - Shipped this session (fixed + verified)

| Area | Change | Commit |
|------|--------|--------|
| Parse bug | Balance the `case` pattern paren (`("$cc_parent"/*)`) so bash 3.2 parses `cmd_children` | `605dc1f` |
| Hook resilience | `gate-hook` denies only on an explicit `^DENY ` marker; any other `gate-check` failure (parse error, crash, missing dep) **fails open** with a stderr warning + a `jq`-built breadcrumb in `.icm/telemetry/hook-errors.jsonl`. Tamper paths still emit `DENY`, so tamper-evidence stays closed. | `5d53fbd` |
| CI guard | New test case 0 parse-lints **every** repo `*.sh` (incl. `installer.sh`) under `/bin/bash` (macOS 3.2 - the version that rejects the construct), records the bash version, word-split-safe | `5d53fbd` |
| Regression tests | `8e` broken `icm.sh` fails open; `8f` genuine `DENY` still fails closed; `8g` fail-open breadcrumb is valid JSONL even with control chars in checker output | `5d53fbd` |
| Skill hygiene | `signoff-proposal`: trim gather payloads (summaries / `only_service_entry_spans`, not full trace dumps); forbid batched `stage-done` (zero-width windows -> null token counts) | `ada18e9` |

Verification: `sh tests/gate.test.sh` -> **72 passed, 0 failed**, including the new cases
under bash 3.2.57. `8g` confirmed to fail on the pre-fix `tr`-strip encoding and pass on
the `jq` encoding (genuine regression test).

The hook fix was reviewed and **approved**: fail-open does not weaken the threat model
because every tamper / malformed-manifest / missing-manifest path in `check_run()` emits a
`DENY ` line (fails closed); fail-open is reachable only on a genuine crash that produces
no `DENY` line - the same scenario that previously bricked the session, now non-bricking.

---

## Part B - Recommended improvements (not yet done)

Prioritized. Each is grounded in observed behavior this session and confirmed against the
source by the review pass. `file:line` references are approximate to this commit range.

### P1 (high)

**B1. Fail-open gate events are recorded but read by nothing.**
`gate-hook` now writes a `gate-check-error` breadcrumb to `.icm/telemetry/hook-errors.jsonl`
when gates fail open - but no command reads it (`audit`, `gate-status`, `verify-seal` all
ignore it). A run can execute an entire stage with gates disabled and leave only an unread
JSONL line. The safety valve is correct; its invisibility is the defect.
*Fix:* (a) `audit` reads `hook-errors.jsonl`, counts events in the run window, reports them
as deviations; (b) `gate-status` reports "N gate-check errors since <ts> - gates were NOT
enforced on those calls"; (c) add `hook-errors.jsonl` to `_seal_files` so a fail-open
episode is tamper-evident.

**B2. Audit tool attribution is run-wide, and `audit` never fails -> `ICM-TOOLS` is near-cosmetic.**
`cmd_audit` computes `actual_tools` once for the whole run window, then matches every
stage's `expect=` against that union. A tool used only in `03-publish` satisfies an
`expect` on `01-gather`. And `audit` prints `Deviations: N` but exits 0 unconditionally, so
nothing in CI or a publish precondition can block on it. Observed: this session, every
stage's audit listed the union of all run tools.
*Fix:* (1) stamp each `tool-calls.jsonl` line with the active stage (gate-check or the hook
can derive it), then intersect per stage; (2) add `audit --strict` that exits non-zero on
deviations (missing `stage-done`, missing `ICM-TOOLS` tool, fail-open events) so CI /
publish contracts can gate. Bare `audit` stays informational.

**B3. `reify-telemetry` is destructive and non-idempotent.**
`cmd_reify_telemetry` rebuilds `stages.jsonl` from scratch and `mv`s over the original,
overwriting good `counts:"transcript"` rows that `stage-done` already computed, and
hardcodes `model:"(from transcript)"`, clobbering the real model. Observed run-to-run: a
good `01-gather in=292k` was overwritten with `in=18,579,565` and the model field
destroyed. Its stated purpose is a *fallback* for rows that could not snapshot.
*Fix:* make it a fill, not a clobber: only rewrite `estimated`/null rows, preserve the
`model` field, back up or diff before replace, and refuse an implausible (>5x) increase
without `--force`. Running it twice must be a no-op.

### P2 (medium)

**B4. No install-time `jq` guard for the telemetry path.** Base `./installer.sh` checks
`jq` only for `--hooks`, but `stage-done`'s snapshot/token math and `reify` all need `jq`.
Without it, `stage-done` still prints "OK ... boundary recorded" while writing
`tokens_in:null` - silent loss of the mandatory per-stage telemetry.
*Fix:* warn at base install when `jq` is absent; have `stage-done` emit a one-line stderr
warning when recording nulls because `jq` is missing.

**B5. Per-stage INPUT tokens are cumulative-context-inflated; stop presenting them as comparable.**
`usage_sums` sums `tokens_in + cache_creation + cache_read` per call - the full context
re-fed each call, which grows monotonically with session length. So `03-publish in=2.64M`
vs `01-gather in=866k` is mostly accumulated context, not stage-03 work. The audit table
prints them side by side with no caveat, inviting a false "03 is 3x costlier" read. (Not a
bug - cache reads are a real cost - but a reporting honesty problem.)
*Fix:* in the audit table, label input as cumulative/context-inflated and lead with
**output** tokens as the per-stage work signal; optionally surface `cache_read` separately.
One line in README Observability.

**B6. `clean` orphans denied/incomplete runs forever.** `cmd_clean` prunes only complete
runs and explicitly preserves incomplete ones. A run denied at a gate (or abandoned
mid-pipeline) is incomplete forever and accumulates. Observed: a gate-denied `signoff`
run lingered on disk.
*Fix:* opt-in reap, e.g. `clean --incomplete --older-than <days>`, default off; report
incomplete-run count + size in `clean`'s summary so buildup is visible.

### P3 (low / docs)

**B7. `gate-check` rejects a workspace positional.** `gate-check --tool X my-workspace`
errors with "Unknown gate-check option", colliding with the mental model that every
subcommand takes a workspace. *Fix:* accept an optional workspace positional and scope to
its latest run (the `latest_runs` filter is trivial), or make the error explicit.

**B8. Document that an `ICM-GATE` cannot verify a POST-action result.** A `PreToolUse`
gate fires before the tool runs, so `run=` can only assert preconditions. A gate checking
for a post-write receipt is unpassable (the receipt cannot exist until after the gated
call) - this exact mistake was made and corrected in the `signoff-proposal` publish stage.
The README gate section never states the PRE-only constraint. *Fix:* one paragraph in
README: verify post-action results in the NEXT stage's gate or in `stage-done`/`audit`,
never in the gate on the action itself.

**B9. Zero-width stage windows should warn at write time.** When two `stage-done` calls
land in the same second (batched stages), the telemetry window is `[t, t]` and captures
near-zero events -> null counts (observed: `02-compose` null in an earlier run). The only
guard is a prose "no batching" rule in the skill - exactly the kind of unenforced prose
gates exist to replace. *Fix:* in `stage-done`, if `_prev_ts == _now`, emit a stderr
warning ("zero-width window; token counts may be null - do not batch stage-done").

**B10. Lint coverage / tooling (from the test review).** The parse lint now covers all
`*.sh`; remaining: shell scripts without a `.sh` extension are not scanned, and
`shellcheck` (while it would not catch *this* bash-3.2 parse class) would catch a broader
set of quoting/portability bugs. *Fix:* optionally add a `shellcheck` step to CI and widen
the scan to shebang-detected scripts.

---

## Cross-cutting theme

Several items (B1, B2, B9) share one root: **the runtime produces a signal but does not
surface or enforce it.** Fail-open events, per-stage tool deviations, and degenerate
telemetry windows are all detectable at the moment they happen, but stay silent or
non-blocking. The gate system exists precisely because "prose does not bind"; the same
principle argues for making these three mechanical and loud rather than advisory.
