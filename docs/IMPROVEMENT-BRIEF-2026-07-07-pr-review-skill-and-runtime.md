# Improvement Brief - pr-review Skill + Runtime Hardening (2026-07-07)

> Audience: an agent (or human) that will improve the pr-review skill and the ICM runtime.
> Status: evidence + prioritized proposals from two full production runs. You decide implementation; respect the lane rules (below) and the constraints at the end. Line numbers drift; grep the symbol.
> Evidence base: two sealed pr-review runs in worktree `~/.tmux-worktree/meetsone/stephen/NONE-32140`:
> - `2026-07-02_08-35-03` - PR meetsmore/meetsone#24229 (verdict SHIP WITH FIXES, 7 findings, 2 mutation runs)
> - `2026-07-06_08-33-45` - PR #24374 (verdict BLOCK, CRITICAL data-loss executed both directions via purpose-built probe specs, full-revert mutation survived)
> Both runs produced correct, execution-backed verdicts. Everything below is about cost, fragility, and the misses the process itself surfaced.

## TL;DR

The skill's judgment layers (ensemble review, adversarial verify, execution-backed verdicts) performed; the **operational shell around them is the weak part**. Ranked: (1) the runtime still has no run identity - the 2026-07-03 brief is 0% implemented and both of its predicted incident classes fired in these runs (orphaned double-init; premature seal with fabricated stage_dones); (2) stage 05 has no environment story for real repos - a pnpm monorepo + Docker + session restart turned a 90-minute review into a 16-hour wall-clock run; (3) stage 02 misses load-bearing context by default (Notion discussions, attachments, Google Sheets); (4) two review lenses that would have caught the #24229->QAFB miss are not yet in the prose (guard-falsification enumeration, PR-lineage retro). Most fixes are stage-prose edits implementable via icm-improve; four are runtime changes; three are tool changes.

## What the two runs measured

From `telemetry/events.jsonl` (per-stage sums; full tables in the workflow evidence):

| | Run 24229 | Run 24374 |
|---|---|---|
| init -> final seal | 41m18s | 16h04m (active ~90min; 14h33m idle gap in 05-verify = Docker daemon death + operator absence + session restart) |
| stage_done events | 12 for 6 stages (every stage closed TWICE; 3 of them `estimated` with model="", null tokens) | 6/6 clean, 0 estimated |
| seals | 2 (premature at 08:53:13Z sealing fabricated 05/06 stage_dones; real at 09:16:22Z) | 1 |
| models | fable-5 + opus-4-8 interleaved (mid-run model switch; out-of-order stage re-entry: 02-links re-closed AFTER 03 closed) | fable-5 only |
| gate-check calls in window | 148, 0 nonzero exits | 255, 0 nonzero exits |
| heaviest stage | 05-verify (655s, 7.8M cache_read) | 05-verify (16M cache_read, 41k tokens_out) |
| orphaned sibling run | `2026-07-02_08-34-36` (single run_init, stage-01 output, never sealed) | none |

Gate enforcement overhead is a non-issue (403 calls, zero failures, zero friction). The cost center is stage 05 environment bootstrap and the judgment stages' cache churn.

## Lanes

- **Lane A - stage prose** (icm-improve may edit: non-protected body of `stages/*.md` only).
- **Lane B - contract** (human-gated: SKILL.md, ICM-GATE/ICM-TOOLS lines, `## Outputs`, eval/, eval-heldout/).
- **Lane C - tools/** (frozen for the improver; normal dev change + eval fixture).
- **Lane D - runtime** (`skills/icm/runtime/icm.sh` + gate-hook.sh + tests/gate.test.sh; never touched by icm-improve).

---

## Skill improvements

### S1 | P0 | cwd discipline for every icm.sh / tools call | Lane A
- Observed: run 24374 - `stage-done` failed with "no active run for kakkoidev/pr-review" because the shell cwd had persisted inside the stage dir from a prior `cd .../01-context && gather-pr ...` call; `.icm` resolves cwd-relative only.
- Today: no stage ever says where to run icm.sh from; the cwd=stage-dir assumption for `output/` and the cwd=repo-root assumption for icm.sh coexist silently (01-context.md:15-17 vs After Output blocks).
- Edit: every After Output block and every tool invocation gets an explicit absolute-path discipline line: run tools with `cd <abs-run-dir>/<stage> && tool ... output`; run every `icm.sh` command from the repo root (`cd <abs-repo-root> && bash ~/.agents/.../icm.sh ...`). One sentence each; removes the whole failure class until D2 lands.

### S2 | P0 | init discipline - never double-init | Lane B (SKILL.md is frozen for the improver)
- Observed: run 24229's sibling `2026-07-02_08-34-36` - same session ran `init` twice 24s apart; first run silently orphaned with stage-01 output already inside it (full forensics: IMPROVEMENT-BRIEF-2026-07-03). SKILL.md and stages contain zero resume/already-initialized prose.
- Edit (SKILL.md Invocation section): before `init`, list `.icm/kakkoidev/pr-review/` and check the newest run for an active stage; if an open run exists for the SAME PR, resume it (`icm.sh next`); if for a different PR, proceed; never re-init to "get a clean run" - the runtime cannot see the old one afterwards. Interim measure until D1 (runtime init guard) makes it mechanical.

### S3 | P1 | Notion: discussions + staleness are mandatory | Lane A
- Observed: run 24374 - the QAFB comment (the entire reason the PR exists) was invisible to a plain `notion-fetch`; it surfaced only via `include_discussions: true`. Page content itself came back cached "as of 2026-07-02" - four days stale - and the skill had no instruction to notice.
- Today: 02-links.md:20-22 says just "notion-fetch (URL or id)". No `include_discussions`, no freshness language anywhere.
- Edit (02 Process): fetch ticket pages with `include_discussions: true` always; read the "as of <ts>" header the MCP returns and, when it predates the PR's updatedAt, disclose the staleness in link-graph.md and treat mirrored tables (QA tables) as possibly missing post-cache rows.

### S4 | P1 | Attachment escalation | Lane A
- Observed: both runs - the decisive QA repro lived in video attachments; the skill recorded them walled-off and moved on. The word "attachment" appears nowhere in the skill (02-links.md handles only badge/image assets).
- Edit (02 Process): for load-bearing attachments on a resolved ticket (videos/images attached to the repro or a QAFB comment), attempt `notion-download-attachment` when the tool is available; if unavailable or non-textual, record "repro carried by attachment only - textual summary is N words" so stage 04 weighs the evidence thinness explicitly.

### S5 | P1 | Google links: try Workspace MCP before WALLED-OFF | Lane A
- Observed: both runs - the QA test-case Google Sheet was declared walled-off (curl auth-wall); this environment has Google Workspace MCP (`gws_api`, `gws_export`) that can read it. Same for docs.google.com generally.
- Edit (02 Process): for `docs.google.com` / `drive.google.com` links, attempt the Google Workspace MCP (ToolSearch for `gws`) before recording WALLED-OFF; fall back with the current disclosure.

### S6 | P0 | Stage 05 environment recipe for real repos | Lane A
- Observed: run 24374 - the prescribed `git worktree add <tmp> HEAD` is the easy 5%. The expensive 95%: PR head based on a moved master needed its own `pnpm install --prefer-offline` + `prisma generate` (stale client from the tracked tree references models that don't exist / miss new ones); `.env` had to be symlinked (a hook rightly blocks reading it - symlink, never copy/cat); jest-setup restored + migrated the SHARED local test DB forward (disclosure required); workspace packages resolve through relative symlinks into the original tree (verify the `@proone`-style workspace diff is irrelevant before trusting them). Run 24229 skipped all this by mutating the tracked tree (disclosed deviation).
- Also observed: the throwaway worktree was placed in the session scratchpad and a session restart DELETED it mid-run (rebuild cost: full install + DB setup again).
- Today: 05-verify.md:23-31 mentions runner detection and `git worktree add` only. Zero words on install/prisma/env/DB/monorepo.
- Edit (05 Process): add a "worktree bootstrap" checklist: (1) place the worktree in a location that survives the session (see D4; until then, a stable tmp dir outside the harness scratchpad); (2) `pnpm install --prefer-offline` (or the repo's manager) - never assume node_modules symlinks suffice across a base-branch gap; (3) run codegen the repo needs (prisma generate, openapi) when the schema/codegen inputs differ from the tracked tree; (4) secrets: symlink env files, never read or copy contents; (5) disclose shared-DB mutations (migrations run forward); (6) budget note: this is the expensive stage - do the bootstrap ONCE and run suite + probes + mutations in the same worktree.

### S7 | P1 | Probe-test pattern, institutionalized | Lane A
- Observed: run 24374's decisive evidence was two purpose-built integration probe specs executed on PR head (FAIL = data loss demonstrated) AND on reverted code (PASS = pre-PR safe). This upgraded a CRITICAL from source-confirmed to executed-proven and flipped the verdict to BLOCK. It was improvised; the prose doesn't know the pattern.
- Edit (05 Process, after the mutation step): for each CRITICAL/HIGH whose failure scenario is constructible with the repo's test harness, write a disposable probe spec IN the throwaway worktree and run it against BOTH the PR head and the reverted code - the two-direction result distinguishes "new regression" (fails head, passes revert) from "pre-existing" (fails both). Probes never ship to the PR branch; their fixtures/assertions are recorded in the report as ready-made regression specs.

### S8 | P2 | Ensemble mortality fallback | Lane A
- Observed: run 24229 - all 3 ensemble subagents died (`FailedToOpenSocket`); the operator improvised sequential inline passes and disclosed weaker independence. Run 24374's K=3 worked. 04-review.md:48 defines the ensemble; no words on subagent failure.
- Edit (04 Process): if an ensemble pass dies, retry it once; if parallel Task remains unavailable, run the K passes sequentially inline with fresh-eyes discipline and DISCLOSE the reduced independence in findings.md and the report header (the 24229 report already models the disclosure sentence).

### S9 | P1 | Guard-falsification enumeration | Lane A
- Observed: the #24229 review validated the fix against the ticket's flat repro; QA then found the hierarchy case - inputs where the fix's own guard (`childless-only`) is false. The next PR (#24374) removed that guard and introduced CRITICAL data loss. Both misses share one shape: nobody enumerated the guard's falsifying inputs.
- Edit (04 Process, near the trace-the-defect paragraph): when a fix adds or relies on a guard predicate (a filter condition, an early return, a childless/empty/null check), enumerate the input shapes that make the guard FALSE and state for each whether the fix still holds; a guard the ticket's repro never falsifies is exactly where the next QAFB lives. Also its dual, already half-present in 04: when a diff REMOVES a guard, ask what the guard was incidentally protecting (in #24374 the childless filter doubled as the label-collision safety net).

### S10 | P1 | PR-lineage retro | Lane A
- Observed: #24374 is a QAFB follow-up to #24229, which this workspace had already sealed a review for. The comparison ("what did the previous review miss and why") happened only because the user asked. It produced the S9 lesson - the retro is where process lessons come from.
- Edit (04 Process + 06 report prose): when the PR body/ticket references a previously REVIEWED PR (check `.icm/kakkoidev/pr-review/` + `.icm-seals.log` for a sealed REVIEW-<n>.md of the referenced PR), stage 04 must read the prior report and stage 06 adds a "Lineage" section: which of today's findings the prior review predicted (cite its finding id), which it missed, and the one-line lesson. Feeds references/scars.md via the operator.

### S11 | P2 | QA-table coverage map as standard output | Lane A
- Observed: both tickets carried 20-row QA tables; the useful artifact "which TC rows are automated vs manual, per variant" was produced ad hoc by the test-strength pass in run 24374.
- Edit (04 or 06 prose): when the ticket carries a QA/test-case table, the report includes a compact TC -> {automated / manual-only / unknown} map; rows the diff makes newly-manual are called out.

### S12 | P2 | Verdict -> GitHub review-event mapping | Lane A
- Observed: report says BLOCK; the human then translates to GitHub vocabulary ad hoc (the 24229 conversation had a REQUEST CHANGES vs Comment debate).
- Edit (06 Process step 1, verdict line): add one sentence - SHIP -> Approve; SHIP WITH FIXES -> Request changes with the fix list (Approve after applied); BLOCK -> Request changes + explicit do-not-merge sentence. Purely advisory text in the report; heldout contract unchanged (verdict regex untouched).

### S13 | P2 | Report delivery | Lane A (+ Lane B note)
- Observed: both runs end with the report buried at `.icm/<ws>/<run>/06-report/output/REVIEW-<n>.md`; the operator relays content manually.
- Edit (06 After Output prose): after seal, present the user the verdict + the report path, and offer (never auto-execute) posting the review to GitHub (`gh pr review --request-changes/--approve --body-file`). Posting is an outward-facing action - human-gated always.

### S14 | P2 | One model per run; re-verify state after model/session switches | Lane A
- Observed: run 24229's duplicate stage closures (12 stage_done for 6 stages), out-of-order 02-links re-entry after 03 closed, and the premature seal all correlate with a mid-run fable-5 <-> opus-4-8 switch; the second operator context re-ran stages it couldn't see were closed. D3 (seal integrity) is the mechanical backstop; prose can prevent the mess.
- Edit (SKILL.md is frozen; put it in 01-context prose): a pr-review run should complete under one model/session; after any interruption or model switch, run `icm.sh next kakkoidev/pr-review` and trust ITS answer about the next empty stage - never re-run a stage that has a stage_done, and never emit estimated stage_dones to "catch up" (that is what poisoned the 24229 seal).

### S15 | P2 | Pass the pinned diff to gather-runtime-evidence | Lane A
- Observed: `tools/gather-runtime-evidence` accepts an optional 4th arg pinning detection to the sealed diff (gather-runtime-evidence:6-8); stage prose (03-runtime-evidence.md:26) doesn't pass it, so detection re-fetches live PR state - a determinism leak the tool already solved.
- Edit: `... gather-runtime-evidence <owner>/<repo> <pr#> output ../01-context/output/pr.diff`.

## Tool improvements (Lane C - each needs an eval fixture proving fails-on-revert)

### T1 | P1 | gather-impact tier 2: removed-guard surfacing
- gather-impact is i18n-only by design (gather-impact:8-9); its documented residual misses plus S9's lesson motivate a second deterministic tier: from removed (`^-`) prod-file lines, surface removed guard shapes (`.filter(`, `if (`, `&& `-conjuncts, early `return` under condition) as "REMOVED GUARD candidates" with file:line - facts only, stage 04 judges (exactly the dead-code dual pattern that worked for i18n). In #24374's diff the removed childless filter would have been surfaced as a candidate. Keep the cap + NOT-searched honesty lines the i18n tier already has. Fixture: a diff removing a `.filter(` guard; assert the candidate line appears; assert a removed comment line does NOT.

### T2 | P2 | gather-pr: deterministic process signals
- Two signals that mattered in #24374 and are regex-cheap from data gather-pr already fetches: (a) PR-template checklist state - the "simple PR / quality checklist waived" checkbox and the unchecked test-coverage row; (b) approval latency + emptiness - review events with state APPROVED, empty body, submitted < N minutes after PR open. Emit as facts in pr-context.md; stage 04 already knows what to do with them (both fed the 24374 synthesis).

### T3 | P3 | fetch-web: Google-export fallback
- Optional: for docs.google.com spreadsheets, attempt the unauthenticated CSV export URL before WALLED-OFF. Low value if S5 (Workspace MCP) lands; keep as note.

## Runtime improvements (Lane D)

### D1 | P0 | Implement the 2026-07-03 run-identity brief - at minimum the init guard
- Status verified 2026-07-07: HEAD `125db54` IS the brief; zero items implemented (no resolve_run, no --run, no ICM_RUN_ID, no init guard, no tombstone, no session pointer, no open_runs, no transcript-path suffix, no run.json session field). `latest_run` still `ls -1 | sort -r | head -1` (icm.sh:121-130).
- Both incident classes it predicted occurred in these two runs (orphan 08-34-36; the seal-target ambiguity behind the premature seal). Minimum viable slice: **init guard + `--force` tombstone** (brief section "Init guard") - it alone prevents the orphan class. tests/gate.test.sh currently CODIFIES no-guard behavior (case 9-pre asserts a second init creates a distinct dir, :303-308) - that case must flip to assert refusal-without-force.

### D2 | P1 | `.icm` upward resolution (or a loud cwd error)
- `.icm` is cwd-relative everywhere (icm.sh:25, :123; seal appends `./.icm-seals.log` :1615). The S1 failure ("no active run" from a stage-dir cwd) is a runtime paper cut every skill pays. Options: (a) walk up from cwd to the git toplevel looking for `.icm` (bounded, e.g. stop at $HOME); (b) cheaper: when `.icm/$ws` is absent from cwd but present at `git rev-parse --show-toplevel`, print a pointed error naming the toplevel instead of the misleading "no active run". Tests: gate.test.sh cases 1/8c/13c/24e codify cwd-dependence for the HOOK (correct - the hook must stay silent outside ICM projects); the change targets the CLI commands only.

### D3 | P0 | Seal integrity: refuse estimated/duplicate stage_dones
- Verified: `cmd_seal` (icm.sh:1583-1616) inspects nothing in events.jsonl - the only refusal is "no evidence files". Run 24229's first seal notarized three fabricated stage_dones (`counts:"estimated"`, model="", null tokens, zero usage events) written 6 seconds earlier. A tamper-evidence system that seals fabricated progress markers undercuts its own story.
- Change: before sealing, scan events.jsonl for the run: any stage with NO stage_done -> refuse (run incomplete); any stage_done with `counts:"estimated"` or empty model -> refuse with the list, `--force` overrides and the seal line records `"forced":true`. gate.test.sh: new case (seal refuses on estimated; `--force` seals with marker); existing fixtures already produce estimated events for audit cases (:648 etc.) - reuse.

### D4 | P1 | Runtime-blessed `work/` dir under the run
- Session-scratchpad placement cost run 24374 a full environment rebuild when the session restarted. `_seal_files` (icm.sh:1567-1581) digests only `.manifest`, `telemetry/*`, and stage `output/` - a `work/` sibling is seal-invisible by construction, and `.icm/` is already gitignored.
- Change: document (and optionally `icm.sh init` mkdir) `<run>/work/` as the sanctioned scratch area for heavy verification state (throwaway worktrees, probe specs, extracted files); `icm.sh clean` prunes it. Stage-05 prose (S6) then points there. One caveat to state: `git worktree add` inside the repo's own gitignored dir is legal but the worktree must be `git worktree remove`d before `clean` deletes the dir, or git leaves a stale registration (prune handles it).

### D5 | P2 | Duplicate-stage_done visibility
- Run 24229: 12 stage_done events for 6 stages, silently accepted; audit does not flag re-closure. Cheap change: `cmd_stage_done` warns (stderr) when a stage_done for that stage already exists; `cmd_audit` lists duplicate closures in the deviations section. No behavior change, pure visibility.

### D6 | P3 | Cost summary helper
- The telemetry to answer "what did this review cost" exists per-stage in events.jsonl (both runs' tables in this brief were derived by hand). A tiny `icm.sh cost <ws>` (sum usage events per stage: tokens in/out, cache creation/read, wall-clock between boundaries) would let stage 06 prose put one cost line in the report receipt - useful for calibrating ensemble K and stage budgets.

## What NOT to change

- Gate/hook architecture: 403 gate-checks across both runs, zero failures, zero friction - leave it alone.
- The 6-stage pipeline shape and gate chain: both runs' quality traces directly to it (deterministic gather -> grounded links -> runtime facts -> gated findings -> execution -> sealed report).
- eval-heldout floor: all three checks held on both runs; extend only alongside new contract (candidates: ensemble-disclosure line when prod bucket nonempty; Lineage section when a sealed prior review exists - both regex-checkable, both Lane B).
- The ensemble + adversarial-verify prose (04:48, 05:33): the 24374 CRITICAL was found by all three perspective-diverse passes independently and survived execution-refutation - the design is earning its cost.

## Suggested sequencing

1. **D1 (init guard) + D3 (seal integrity)** - runtime, small, kill both observed incident classes; flip gate.test.sh case 9-pre.
2. **S1 + S6 + S7** via one icm-improve cycle - the operational prose with the highest per-run payoff.
3. **S3/S4/S5 + S9/S10** via a second icm-improve cycle - context completeness + the two miss-prevention lenses (S9 is the direct lesson of the #24229->QAFB miss).
4. **T1/T2** with eval fixtures; then D2/D4/D5; the P2 tail (S8, S11-S15, D6, T3) opportunistically.
5. Re-baseline: run the improved skill on the next real PR and A/B per docs/skill-improvement/README.md; the #24374 run (BLOCK with executed probes) is the new quality bar for "execution-backed".

## Constraints (do not regress)

- icm-improve lane rules: stage prose only; ICM-GATE/ICM-TOOLS/`## Outputs`/tools/eval/eval-heldout/SKILL.md frozen; guard must print GUARD OK (icm-improve.sh:82-97).
- POSIX sh / bash 3.2 for icm.sh and all tools; hermetic HOME in tests/gate.test.sh.
- gate-check runs on every hooked tool call - keep its fork budget flat (D2's upward walk must not run in the hook path).
- Never weaken the honesty lines: WALLED-OFF surfacing, NOT-searched disclosures, `UNVERIFIED:` tagging, estimated-counts labeling. Several proposals (S3, S4, D3) exist precisely to extend them.
