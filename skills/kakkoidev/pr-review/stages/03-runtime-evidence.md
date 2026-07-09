# Stage 03: Runtime evidence (grounding, before review)

<!-- ICM-TOOLS expect="(Bash|Read)" -->
<!-- ICM-GATE tools="Bash|Write" run="test -s ../02-links/output/link-graph.md" -->

Ground the review in how the changed mechanism ACTUALLY executes - before judging it.
This stage exists because the review's worst miss is reasoning from the diff plus an
unexamined assumption ("the run fires", "the trigger matches the actor") instead of
looking at a real instance. The gate blocks this stage until the link graph exists, so
runtime facts are gathered alongside the resolved requirements, not in a vacuum.

This stage gathers FACTS (deterministic tool) and lays out the EXECUTION CHAIN (model).
It does not judge - that is stage 04. Do not flag findings here.

## Inputs
| Source | Location | Scope |
|--------|----------|-------|
| PR context | ../01-context/output/pr-context.md | buckets, action feed, linked issues |
| Diff | ../01-context/output/pr.diff | the change under review (sealed in 01) |
| Link graph | ../02-links/output/link-graph.md | resolved tickets + the ACs they state |

## Process
1. **Gather runtime facts (deterministic).** Run the frozen tool from THIS stage's
   dir (it writes a cwd-relative `output/`), pinning detection to the sealed diff:
   ```bash
   cd <abs-run-dir>/03-runtime-evidence && \
     bash ~/.agents/skills/kakkoidev/pr-review/tools/gather-runtime-evidence <owner>/<repo> <pr#> output ../01-context/output/pr.diff
   ```
   The 4th arg pins detection to the diff sealed in stage 01, so this stage reads the
   exact state under review, not live HEAD (a determinism leak the tool already solves;
   the sibling gather-impact call below already pins the same diff).
   It records, for the changed mechanisms: workflow run history; a real recent instance
   of every conditional actor/event the diff depends on (e.g. a Dependabot PR timeline
   showing the bot applies labels as discrete ops); and the Actions-vs-Dependabot secret
   stores any referenced `secrets.*` resolves in. Absence is a recorded fact, never a
   silent skip. The tool is a live snapshot (run history / secrets drift) - that is
   expected; the load-bearing fact (e.g. "the bot applies the label") is stable.
1b. **Gather changed-value impact (deterministic) - the dual of the dead-code check.** Run:
   ```bash
   bash ~/.agents/skills/kakkoidev/pr-review/tools/gather-impact ../01-context/output/pr.diff output
   ```
   Dead-code asks "an ADDED symbol - does anything consume it?"; this asks the reverse:
   "a user-visible value this PR REMOVES - does an existing test/snapshot still assert it?"
   For every i18n key/value the diff removes, it resolves the value and greps the TEST TREE
   (scoped: `*.spec.*`, `*.test.*`, `__snapshots__`, e2e/cypress/playwright) for it, listing
   each consumer as a BREAKAGE CANDIDATE. This is the deterministic surfacing of exactly the
   miss the A/B on #24198 exposed (an e2e assertion on a label the PR stopped rendering). It
   emits facts only - "candidate to verify", never "confirmed break"; visual/screenshot
   snapshots are explicitly marked NOT searched (never a false clear). Stage 04 judges which
   candidates are real; the tool never judges here.
2. **Per-AC execution-chain trace (model).** For every acceptance criterion that asserts
   an *effect or mechanism* (not just a value), lay out the chain
   `trigger -> condition -> step -> external effect` and mark each link
   `executes for the real actor` / `unverified` / `broken`, citing `runtime-evidence.md`.
   This is the lens stage 04's constant/set traceability does not cover: a value-AC is a
   constant to check; a mechanism-AC ("notification sent on PR open", "job runs nightly",
   "flag gates the path") is an execution chain to walk against a real instance.
   - Generalize beyond CI: cron jobs (does the schedule fire? last run?), webhooks (does
     the event reach the handler?), feature-flag/env-conditional code (which branch runs
     for the real flag/env value?) - any behavior conditional on a runtime actor/event/env.
3. Do NOT judge. If the trace shows a link is `unverified` or `broken`, record it as a
   chain fact for stage 04 to weigh - do not write it as a finding here.

## After Output (MANDATORY)
Run from the repo root (`icm.sh` resolves `.icm` cwd-relative):
```bash
cd <abs-repo-root> && \
  bash ~/.agents/skills/icm/runtime/icm.sh stage-done kakkoidev/pr-review --stage 03-runtime-evidence
```

## Outputs
| Artifact | Location | Format |
|----------|----------|--------|
| Runtime evidence | output/runtime-evidence.md | Tool output (verbatim): changed-workflow run history; per conditional actor/event a real instance (timeline ops with actor + timestamp); secret-store membership (names only). Facts, no judgment. |
| Changed-value impact | output/impact.md | Tool output (verbatim): per user-visible value the diff REMOVES (i18n key/value), the test/snapshot files that still assert it (breakage candidates), each with `file:line`; an explicit `0 consumers` clear line where none; visual snapshots marked NOT searched. Facts, no judgment. |
| AC execution trace | output/ac-execution-trace.md | One block per mechanism-AC: the `trigger -> condition -> step -> external effect` chain, each link tagged `executes for the real actor` / `unverified` / `broken` with a citation into runtime-evidence.md. Value-only ACs are noted as "constant - checked in 04", not traced. |
