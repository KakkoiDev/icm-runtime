---
name: pr-review
description: >
  Review a GitHub PR as a staged, auditable, sealed ICM run. Deterministically
  gather the PR summary + full action feed + the complete set of links (a tools/
  script: gh + regex), follow those links depth-2 (PR -> Notion ticket -> the
  external law/requirement site it cites; Slack threads; web), then run the
  ported code-review judgment (7-point validation, severity, adversarial,
  external-rule check grounded in the fetched requirements, dead-code, scope
  drift, a scars check, and execution-backed verification) into a REVIEW-<PR#>.md
  report. The deterministic gather + complete link graph replace the old review
  agent's silent best-effort context. This is the skill optimized by icm-improve.
  Triggers: "review PR <n>", "pr-review", "icm review this PR".
---

# pr-review

A code review that runs through the ICM runtime: every stage is gated,
telemetried, and the final report is sealed. It ports the `review` agent
(`~/.agents/.../agents/review.md`) and fixes its two weaknesses - context
gathering that was optional and silent, and links that were never followed.

## Determinism boundary (read this)

- **Deterministic** - a `tools/` bash script, no model judgment: the PR summary,
  the full action feed, the *set* of links, and the PR-template mandatory checklist
  with each box's tick state (`tools/gather-pr` = `gh` + regex -> `links.tsv`,
  `checklist.tsv`, `pr-template.md`). Same PR state -> identical output. The
  *audit* of each checklist item (04) is model-mediated, not the extraction.
- **Auditable but model-mediated** - not script-deterministic: *following*
  Notion/Slack links (MCP calls) and the review judgment. Verified via ICM-TOOLS
  and the eval-heldout link-coverage check, not guaranteed by a script.
- A web link is fetched deterministically via `tools/fetch-web` (curl); if curl
  can't reach it, WebFetch is tried; if it is still unreachable (auth wall) it is
  recorded as `WALLED-OFF` and **surfaced to the user** - never silently dropped.
- The inline PR review (06) splits the same way: the line **anchoring is
  deterministic** (`tools/build-review-comments` resolves a quoted snippet to its
  real RIGHT-side line, so a diff-offset vs source-line mixup cannot mis-post; an
  unresolved snippet lands in `unanchored.tsv`, never a guessed line). The **POST is a
  gated, pending-only write** (`tools/post-review`, create-or-append, passes no
  `event`) - it drafts a review a human submits; it never publishes on its own.

## Pipeline

| Stage | Does | Output |
|-------|------|--------|
| 01-context | `gh` PR summary + action feed + extract every link + the PR-template mandatory checklist (with tick state) + the repo template + seal the diff (deterministic) | `pr-context.md`, `links.tsv`, `checklist.tsv`, `pr-template.md`, `pr.diff` |
| 02-links | follow each link depth-2 (Notion/Slack/web), flag walled-off | `link-graph.md` |
| 03-runtime-evidence | how the mechanism executes: run history + a real actor/event instance + secret stores (deterministic); the changed-value impact sweep (tests that still assert a value the diff removes - the dual of dead-code, deterministic); per-AC execution-chain trace | `runtime-evidence.md`, `impact.md`, `ac-execution-trace.md` |
| 04-review | ported review dimensions + 7-point + scars check + PR-template checklist audit (uniform bar, verified/asserted, bias alarm), findings tagged CONFIRMED/PLAUSIBLE/REFUTED | `findings.md`, `checklist-audit.md` |
| 05-verify | suite + mutation-in-worktree + read-only MCP + mandatory adversarial per-finding verify (no-oracle PRs backed by runtime-evidence, never "static only") | `verification.md` |
| 06-report | assemble + seal the report, then post findings inline as a PENDING PR review (deterministic snippet->line anchoring; create-or-append; never submitted) | `REVIEW-<PR#>.md`, `review-comments.ndjson`, `review-comments.json`, `unanchored.tsv`, `report-receipt.md` |

## Invocation

```
icm.sh init kakkoidev/pr-review
```
Inputs (from the chat that starts the run): `<owner>/<repo>` and the PR number.
`<PR#>` becomes the report index: `REVIEW-<PR#>.md`.

## Runtime

This workspace uses the ICM runtime. Never scaffold dirs, copy files, or format
timestamps yourself - delegate to `icm.sh` via bash:
```
bash ~/.agents/skills/icm/runtime/icm.sh <command> kakkoidev/pr-review
```
After `init`, read the run path from stdout (report any gitignore warning on
stderr). Each stage's contract is `<run>/<stage>/CONTEXT.md`. After each stage,
`icm.sh next kakkoidev/pr-review` finds the next empty stage.

## Per-stage telemetry (MANDATORY)

After writing a stage's output, immediately:
```
bash ~/.agents/skills/icm/runtime/icm.sh stage-done kakkoidev/pr-review --stage <stage-name>
```

## Audit + seal

After the run:
```
bash ~/.agents/skills/icm/runtime/icm.sh audit kakkoidev/pr-review
bash ~/.agents/skills/icm/runtime/icm.sh seal kakkoidev/pr-review
```
Seal makes `REVIEW-<PR#>.md` tamper-evident; suggest committing `.icm-seals.log`.

## Reference
- `docs/GUIDE-improving-pr-review.md` - how to improve this skill without over-fitting or prose bloat (classify by layer, freeze every miss as a fixture/contract).
- `tools/gather-pr` - deterministic PR gather (gh + links + checklist + template). `tools/extract-checklist` - shared checkbox parser (frozen by `eval/checklist-extraction.test.sh`). `tools/fetch-web` - curl + auth-wall detect.
- `tools/gather-impact` - deterministic changed-value dual of dead-code: for each user-visible value the diff removes, the tests/snapshots that still assert it (`impact.md`). Catches the class the review agent caught by hand and the skill missed (#24198).
- `references/scars.md` - generalized review lenses, frozen into the run and used as a review lens in 03.
- `eval/structure.test.sh` - skill shape. `eval-heldout/` - output-contract floor (link coverage, report contract) for icm-improve.
