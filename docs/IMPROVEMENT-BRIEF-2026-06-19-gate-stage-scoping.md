# Improvement Brief - Gate Stage-Scoping Deadlock (2026-06-19)

> RESOLVED (2026-06-19, commit 4296258): fixed via option A (stage-scoping).
> `check_run` now evaluates a gate only while its owning stage is the run's ACTIVE
> stage, computed by the new `_active_stage` helper. A completed run has no active
> stage and denies nothing, which also closes the cross-workspace blast radius
> (amplifier 2). Manifest tamper-evidence is still checked first. Regression: test
> case 41 reproduces this brief's exact deadlock trace on the pre-fix code and
> passes after; 41b/c/d cover fires-when-active, passes-when-precondition-met, and
> silent-when-complete.
> NOTE: option B's "`.stage-telemetry` already marks closed" is now stale -- the
> per-run telemetry was unified into `events.jsonl`, so the "closed" signal is a
> `stage_done` event, which is what `_active_stage` reads.

> Audience: the implementing agent. Companion to `IMPROVEMENT-BRIEF-2026-06-19-telemetry-and-determinism.md`.
> Register: this is a precise engineering spec, deliberately NOT in the `draft-report` house style. A deadlock trace needs exactness and step ordering, not a 10-second gist.
> Line numbers are from this reading of `skills/icm/runtime/icm.sh` and `gate-hook.sh`; they will drift. Grep the symbol, not the number.

## TL;DR

ICM gates are evaluated GLOBALLY - across every stage of a run, and across every workspace's latest run - matched by tool-name regex ONLY, with no stage-scoping. So a gate that names a common tool (`Write`, `Read`, `Bash`, ...) denies that tool in any earlier stage too, which is a hard deadlock for pure-authoring pipelines. Gates are therefore unusable for any skill whose stages share a common tool, which is most non-MCP skills. This only manifests once `--hooks` is installed - i.e. turning ON enforcement is what triggers it.

## What actually happens (call path, precise)

1. `gate-hook.sh` is a PreToolUse hook with matcher `.*`, so it runs on EVERY tool call. It reads `tool_name` + `cwd`, `cd`s into `cwd`, and if `.icm` exists calls `icm.sh gate-check --tool "$tool_name"`. (`gate-hook.sh` ~40-66)
2. `cmd_gate_check` (icm.sh ~1341) iterates `latest_runs` - the latest run of EVERY workspace under `./.icm` - and calls `check_run "$run" "$tool"` for each. (icm.sh ~1357)
3. `check_run` (icm.sh ~294):
   - First verifies the frozen contract against `.manifest`; on mismatch it prints `DENY ... contract tampered` and returns BEFORE any tool matching - so a tampered run denies EVERY tool call regardless of tool. (~302-308)
   - Then greps `<!-- ICM-GATE ` across ALL stage contracts in the run: `"$cr_run"/[0-9]*/CONTEXT.md`. Every stage's gate, not just the active one. (~310)
   - For each gate: parses `tools=` and `run=` via `gate_attr`. (~316-317)
   - Matches the called tool against `tools` (unanchored ERE): `printf '%s' "$cr_tool" | grep -Eq -- "$cr_tools"`. (~323)
   - On match, runs the checker `run` with cwd = the gate's OWNING stage dir: `(cd "$cr_stage_dir" && sh -c "$cr_exec")`. (~347)
   - Non-zero checker exit -> prints `DENY ...`; `gate-hook` converts a `DENY`-prefixed line into a permission deny. (~348-354, `gate-hook.sh` ~70-72)
   - The owning stage IS computed (`cr_stage`, ~313-314) but used ONLY in the DENY text - never to decide whether the gate is in scope.

Net: a gate is live from the instant `init` freezes its `CONTEXT.md`, for the WHOLE run, matched purely by tool name, independent of run progress or which stage is executing.

## The deadlock (concrete trace)

Pure-authoring pipeline where every stage writes its output with `Write` (e.g. `kakkoidev/draft-report`: `01-frame`, `02-draft`, `03-tighten`). Suppose, intending a pre-condition, `02-draft` declared:

```
<!-- ICM-GATE tools="Write" run="test -s ../01-frame/output/frame.md" -->
```

With `--hooks` installed:

1. `init` freezes all three `CONTEXT.md` (including 02's gate) and writes `.manifest`.
2. Stage 01 attempts `Write` of `01-frame/output/frame.md`.
3. Hook -> `gate-check --tool Write` -> `check_run` greps all gates -> finds 02's gate.
4. `tools="Write"` matches the called tool `Write`.
5. Checker `test -s ../01-frame/output/frame.md` runs from `<run>/02-draft/`, testing `<run>/01-frame/output/frame.md` - which does not exist yet (it is the very file this `Write` would create) -> exit 1.
6. `check_run` prints `DENY ... 02-draft: checker failed` -> the `Write` is blocked.
7. `frame.md` can never be created: the gate that requires it denies the only `Write` that would create it. Hard deadlock, and while the run is open EVERY `Write` in the project is denied.

This is why `kakkoidev/draft-report` ships with NO gates: any `Write`-matched gate bricks it.

## When it bites, when it does not

- Only with `--hooks` registered. Without the hook, `gate-check` is never called, gates are inert (no enforcement AND no deadlock). So enabling enforcement - required for the whole "reliable/auditable" story - is exactly what triggers the deadlock for these skills.
- `kakkoidev/publish-to-notion` dodges it BY ACCIDENT: its gates name MCP-specific tools (`notion-create-pages`, `notion-fetch`) that are only ever called inside their own stage. No earlier stage calls those tools, so the global scope never fires. The safety is incidental (rare tool), not designed.
- Bites any skill whose gate references a tool an earlier stage also uses: `Write`, `Read`, `Edit`, `Bash`, `WebFetch`, etc. That is most non-MCP skills.

## Blast radius (two amplifiers)

1. Cross-stage: a later stage's gate denies an earlier stage (the trace above).
2. Cross-workspace: `cmd_gate_check` evaluates `latest_runs` = the latest run of EVERY workspace under `./.icm`. A live `Write`-matched gate in workspace A's latest run denies `Write` calls made while working in workspace B in the same `.icm` root. One unfinished gated run taxes unrelated work in the same project.

## Recovery (precise - matters because it can trap a session)

The deadlock is a CLEAN checker failure (`test` exits 1) = a genuine `DENY` = fail CLOSED. The hook's fail-OPEN path only covers a CRASHING `gate-check` (parse error / missing dep), not a checker that runs fine and reports "condition not met." So the deadlock genuinely blocks.

- `tools="Write"` does NOT match `Edit`/`Read`/`Bash` (different tool names), so those still work - you can recover with `Bash` (`rm -rf` the stuck run dir, so `latest_run` falls back to a clean run or none) or by removing the gate from the source and running a fresh `init` (latest_runs uses the newest run).
- Do NOT try to fix it by editing the FROZEN `CONTEXT.md` in the run: that trips the manifest tamper check (~302-308), whose `DENY` fires before tool matching and thus denies EVERY tool, bricking the session harder.
- Last resort: `installer.sh --remove` to unregister the hook.

## Root cause (one line)

`check_run` matches gates by tool name only and never scopes them to the owning stage or to run progress; the owning stage (`cr_stage`, ~313-314) is already known at evaluation time and simply unused as a guard.

## Fix options (implementer decides)

- A. Stage-scope (recommended, smallest correct change): evaluate a gate only when its owning stage is the ACTIVE stage. "Active" = next-empty stage (`cmd_next` already computes this) or the in-progress stage. `check_run` already has `cr_stage`; add `cr_stage == active_stage` as a guard. Cost: computing the active stage on the hot path (every tool call) must be cheap - cache it in the run dir at stage boundaries (`init` / `stage-done` already write there) and read one file.
- B. Progress-gated: a gate is live only between its stage being entered and closed. `.stage-telemetry` already marks "closed"; you would add an "entered" marker.
- C. Explicit scope in the directive: carry the owning stage on the gate (implicit from its `CONTEXT.md` path) and enforce only for that stage. Same effect as A, more explicit in the contract.
- D. Split gate kinds: a PRE-condition gate checked ONCE on stage entry (off the tool hot path) vs a TOOL gate checked on a specific tool within the active stage. The current model conflates "guard this stage's entry" with "gate every matching tool everywhere," which is the deeper design error.
- Pair any of the above with a cross-workspace fix: `gate-check` should evaluate only the run relevant to the current context, not every workspace's latest run.

## Constraints (do not regress)

- bash 3.2 (macOS `/bin/bash`). The gate path already caused a session-bricking parse bug once (`RUNTIME-IMPROVEMENTS-2026-06-15.md`).
- `gate-hook` -> `gate-check` -> `check_run` run on EVERY tool call. Active-stage logic must be near-O(1) and must not add a fork-heavy step to the hot path.
- Keep the hook contract: fail OPEN on a crashing checker, fail CLOSED on a genuine `DENY` (`gate-hook.sh` ~62-75).
- Do NOT break `publish-to-notion`'s MCP-tool gates - they must keep working under whatever scoping lands.
- Scoping must run AFTER manifest verification, not instead of it - tamper-evidence stays first.

## Repro

1. `cd` into a scratch dir (not a real project - a stuck `Write` gate can trap the session). `icm.sh init kakkoidev/draft-report`.
2. Add to `skills/kakkoidev/draft-report/stages/02-draft.md`: `<!-- ICM-GATE tools="Write" run="test -s ../01-frame/output/frame.md" -->`. Re-`init` (gates freeze at init).
3. `installer.sh --hooks`.
4. In a Claude Code session in that dir, run the skill. Stage 01's `Write` of `frame.md` is denied: `DENY ... 02-draft: checker failed: test -s ../01-frame/output/frame.md`.
5. Recover: `Bash rm -rf` the stuck run dir, remove the gate from the source, `installer.sh --remove` if needed.
