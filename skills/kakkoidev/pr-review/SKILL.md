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
  the full action feed, and the *set* of links (`tools/gather-pr` = `gh` + regex
  -> `links.tsv`). Same PR state -> identical output.
- **Auditable but model-mediated** - not script-deterministic: *following*
  Notion/Slack links (MCP calls) and the review judgment. Verified via ICM-TOOLS
  and the eval-heldout link-coverage check, not guaranteed by a script.
- A web link is fetched deterministically via `tools/fetch-web` (curl); if curl
  can't reach it, WebFetch is tried; if it is still unreachable (auth wall) it is
  recorded as `WALLED-OFF` and **surfaced to the user** - never silently dropped.

## Pipeline

| Stage | Does | Output |
|-------|------|--------|
| 01-context | `gh` PR summary + action feed + extract every link + seal the diff (deterministic) | `pr-context.md`, `links.tsv`, `pr.diff` |
| 02-links | follow each link depth-2 (Notion/Slack/web), flag walled-off | `link-graph.md` |
| 03-runtime-evidence | how the mechanism executes: run history + a real actor/event instance + secret stores (deterministic) + per-AC execution-chain trace | `runtime-evidence.md`, `ac-execution-trace.md` |
| 04-review | ported review dimensions + 7-point + scars check, findings tagged CONFIRMED/PLAUSIBLE/REFUTED | `findings.md` |
| 05-verify | suite + mutation-in-worktree + read-only MCP + mandatory adversarial per-finding verify (no-oracle PRs backed by runtime-evidence, never "static only") | `verification.md` |
| 06-report | assemble + seal the report | `REVIEW-<PR#>.md`, `report-receipt.md` |

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
- `tools/gather-pr` - deterministic PR gather (gh + links). `tools/fetch-web` - curl + auth-wall detect.
- `references/scars.md` - documented past failures, frozen into the run and used as a review lens in 03.
- `eval/structure.test.sh` - skill shape. `eval-heldout/` - output-contract floor (link coverage, report contract) for icm-improve.
