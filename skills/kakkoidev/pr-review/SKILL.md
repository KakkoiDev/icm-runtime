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
- **Deterministic, same split, for the house-standards pair:** *which* normative
  documents the repo writes for itself (`tools/gather-house-rules` -> `house-rules.tsv`)
  and *which* deprecated symbols the diff's added lines use (`tools/gather-deprecations`
  -> `deprecations.tsv`) are extracted by script, so a document that exists cannot be
  skipped by forgetting it and a deprecation marker one file away cannot go unread.
  Whether the code actually *violates* a quoted rule is the model's judgment (04).
- **Deterministic, same split again, for local context:** *which* added lines and added
  paths carry a home path, an identity-shaped literal, a scratch or draft location, a
  personal tool's ignore rule, a private-lexicon term or a review-process label (`tools/gather-local-leakage` ->
  `local-leakage.tsv`) is extraction by script, so a value that is only true on the
  author's machine cannot be passed over the way a past PR's were. Whether that value is
  *genuinely private* - a copyable real id versus a documented tenant uuid, a personal
  tool versus the actual requirement - is the model's judgment (04), and the class with
  no literal to extract at all (an environment assumption: a variable one install sets,
  a default right in one workspace) is the reviewer's own pass, which 04 makes explicit
  rather than leaving to the tool.
- **Auditable but model-mediated** - not script-deterministic: *following*
  Notion/Slack links (MCP calls) and the review judgment. Verified via ICM-TOOLS
  and the eval-heldout link-coverage check, not guaranteed by a script.
- A web link is fetched deterministically via `tools/fetch-web` (curl); if curl
  can't reach it, WebFetch is tried; if it is still unreachable (auth wall) it is
  recorded as `WALLED-OFF` and **surfaced to the user** - never silently dropped.
- The inline PR review (06) splits the same way: the line **anchoring is
  deterministic** (`tools/build-review-comments` resolves a quoted snippet to its
  real RIGHT-side line, so a diff-offset vs source-line mixup cannot mis-post; an
  unresolved snippet lands in `unanchored.tsv`, never a guessed line). The **write is
  ONE pending review** (`tools/post-review`, create-only, passes no `event`, stops if the
  user already has a pending review on the PR) - one terse English + one terse Japanese
  line per finding; the report carries the lengthy explanation and the pending review URL.
  It never submits, never posts a plain comment: the human reads, then publishes.

## Pipeline

| Stage | Does | Output |
|-------|------|--------|
| 01-context | `gh` PR summary + action feed + extract every link + the PR-template mandatory checklist (with tick state) + the repo template + the repo's own normative documents + the deprecated symbols the diff uses + the local context the diff would ship + seal the diff (deterministic) | `pr-context.md`, `links.tsv`, `checklist.tsv`, `pr-template.md`, `template-checklist.tsv`, `house-rules.tsv`, `deprecations.tsv`, `local-leakage.tsv`, `pr.diff` |
| 02-links | follow each link depth-2 (Notion/Slack/web), flag walled-off | `link-graph.md` |
| 03-runtime-evidence | how the mechanism executes: run history + a real actor/event instance + secret stores + deployed presence of new env vars and tests (deterministic); the changed-value impact sweep (tests that still assert a value the diff removes - the dual of dead-code, deterministic); per-AC execution-chain trace | `runtime-evidence.md`, `impact.md`, `ac-execution-trace.md` |
| 04-review | ported review dimensions + 7-point + scars check + PR-template checklist audit (uniform bar, verified/asserted, bias alarm), findings tagged CONFIRMED/PLAUSIBLE/REFUTED | `findings.md`, `checklist-audit.md` |
| 05-verify | suite + mutation-in-worktree + read-only MCP + mandatory adversarial per-finding verify (no-oracle PRs backed by runtime-evidence, never "static only") | `verification.md` |
| 06-report | assemble + seal the report, then add findings inline as ONE PENDING PR review, EN + JP line each (deterministic snippet->line anchoring; create-only, stops on an existing pending review; never submitted) | `REVIEW-<PR#>.md`, `review-comments.ndjson`, `review-comments.json`, `unanchored.tsv`, `report-receipt.md` |

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

## Feedback pass (after the author responds)

The run ends at a pending draft; precision is only measurable once the author/reviewer
replies. The pass is not left to memory - it runs on two triggers, whichever comes first:
- **At merge** of a reviewed PR (or when asked "how did the review land?").
- **At the start of the next run on the same repo**, before stage 01: list the sealed
  `REVIEW-<n>.md` under that repo's `.icm/kakkoidev/pr-review/` whose PR has no row in
  the calibration log, and run the pass for each before starting the new review.

For each, run:
```
bash tools/gather-review-feedback <owner>/<repo> <PR#>
```
It emits one TSV row per posted `**F<n>` comment and per reply. Classify each finding
(`accepted` / `accepted-fix-replaced` / `rejected(<reason>)` / `disputed` / `ignored`) and append the rows to
the local, untracked calibration log (`~/.config/icm/pr-review-calibration.md`,
format in `references/calibration.example.md`). A finding shape rejected twice becomes a floor demotion
reason or a scar, and a fix shape replaced twice becomes a stage-04 `Fix shape:` lens - this
is the loop that keeps the value gate calibrated by ground truth instead of one incident.

## Reference
- `tools/gather-pr` - deterministic PR gather (gh + links + checklist + template + body claims via `tools/extract-body-claims` + process gates `gates.tsv` + the PR text as `pr-text.diff`; the latter three frozen by `eval/body-claims.test.sh` and `eval/gather-pr-gates.test.sh`). `tools/extract-checklist` - shared checkbox parser (frozen by `eval/checklist-extraction.test.sh`). `tools/fetch-web` - curl + auth-wall detect.
- `tools/gather-house-rules` - deterministic discovery of the repo's OWN normative documents (guideline trees, architecture decision records, contributor and agent instructions, the PR template, incident catalogues), with a path-token relevance hint and an explicit `# NONE:`/`# TOTAL:` accounting line so a document that exists cannot be skipped by forgetting it (`house-rules.tsv`; 04 must account for every row and quote the rule it cites). `tools/gather-deprecations` - the deprecated-symbol map intersected with the diff's added lines, resolved to the definition site with the note that names the replacement, and an explicit `# CLEAR:` for searched-and-none-found (`deprecations.tsv`). Both frozen by `eval/house-rules-deprecations.test.sh`.
- `tools/gather-local-leakage` - deterministic extraction of the local context a diff would SHIP: home paths, identity-shaped literals (bounded 32-hex / uuid / Slack id), scratch and draft file locations, a personal tool's ignore rule in a shared ignore file, and terms from the private lexicon - a local untracked file (`$ICM_PRIVATE_VOCAB`, else `~/.config/icm/private-vocab.txt`; format in `references/private-vocab.example.txt`) that is never committed to a reviewed repo or to this one; a missing lexicon is reported as `# NO-LEXICON:`, never as a clear (a past PR's first guard hardcoded the banned words inside a file that shipped, publishing the list it existed to suppress; the tool excludes that file from its own scan). Added lines and added paths only: a value the diff deletes can never produce a hit. Emits signals, never verdicts; `# TOTAL:`/`# CLEAR:` accounting, with the clear explicitly bounded by the lexicon and by the tool's residual misses. Frozen by `eval/local-leakage.test.sh`, which asserts both halves against a frozen fixture - planted signals found at the right line across hunks, and CI paths, bot addresses, lockfile hashes and all-caps constants kept silent.
- `tools/detect-precedence-changes` - merges the diff reordered (object-literal spread order, single-line spread and `Object.assign` argument order), each pair with its old and new winner (`precedence.tsv`); `--check` enforces 04 step 17: every row has a `Precedence:` line with the winners the diff shows, and unstated or partial intent or a missing test names an existing finding. Born from https://github.com/meetsmore/use-ai/pull/96 (a moved `...config.attributes` reversed which source won). Frozen by `eval/precedence.test.sh`.
- `tools/gather-impact` - deterministic changed-value dual of dead-code: for each user-visible value the diff removes, the tests/snapshots that still assert it (`impact.md`). Catches the class a review agent once caught by hand and the skill missed. Pass the reviewed checkout as the 3rd arg (stage 03 does): the `git rev-parse` default resolves to whatever repo the cwd sits in, and the tool refuses a root that holds none of the diff's paths rather than sweeping it and printing a false `values=0` (frozen by `eval/impact-root-guard.test.sh`).
- `tools/check-value-claims` - deterministic cross-check of the self-graded value floor (an inline-bound `introduced-by-diff=yes` or `=sibling` must cite a diff-touched file; frozen by `eval/check-value-claims.test.sh`). `tools/gather-review-feedback` - post-submit thread harvest feeding the local calibration log.
- `references/scars.md` - generalized review lenses, frozen into the run and used as a review lens in 03. `references/calibration.example.md` - format of the local, untracked per-finding ground-truth log (accepted/rejected) driving gate calibration.
- `eval/structure.test.sh` - skill shape. `eval-heldout/` - output-contract floor (link coverage, report contract, inline-comment coverage + value gate) for icm-improve.
