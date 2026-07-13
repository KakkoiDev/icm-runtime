# Stage 01: Gather PR context (deterministic)

<!-- ICM-TOOLS expect="(Bash)" -->

Pull the PR summary, the full chronological action feed, and the complete set of
links - deterministically, via the frozen `tools/gather-pr` script. No judgment
here: this stage is a single script call so the gathered context is reproducible.

## Inputs
| Source | Location | Scope |
|--------|----------|-------|
| PR reference | the chat that started the run | `<owner>/<repo>` and the PR number |

## Process
1. Run the deterministic gather tool from THIS stage's directory - the tool writes
   to a cwd-relative `output/`, so the cwd must be the stage dir:
   ```bash
   cd <abs-run-dir>/01-context && \
     bash ~/.agents/skills/kakkoidev/pr-review/tools/gather-pr <owner>/<repo> <pr#> output
   ```
   `<abs-run-dir>` is the absolute path `icm.sh init` printed on stdout.
   It writes `output/pr-context.md` (summary header, file buckets, action feed),
   `output/links.tsv` (every URL in the PR's free text, with source),
   `output/checklist.tsv` (the PR-template mandatory checklist as instantiated in
   the body, one row per box: `checked`/`unchecked` <TAB> item text),
   `output/pr-template.md` (the repo's PR template, ground truth for which items
   are mandatory), and `output/pr.diff` (the change under review, sealed so the
   review is reproducible).
2. Do NOT hand-edit any of these files. If the tool errors (auth, missing PR),
   report the exact error to the user and stop - do not fabricate context.
3. Read `output/pr-context.md` so you know the PR; note the bucket counts and any
   linked Notion/Slack/requirement URLs you will follow in stage 02.
4. Read `output/checklist.tsv` and `output/pr-template.md`. Note how many items the
   template mandates, which the body ticked vs left unchecked, and any template item
   MISSING from the body (a deleted checklist line is a dodge, not a pass). This is
   the input to stage 04's checklist audit - the author's tick state is a *claim*,
   not evidence. If `checklist.tsv` is empty (no template / no checklist in this
   repo), record that fact; there is then nothing to audit and 04 says so explicitly.
5. **Read the provenance `gather-pr` wrote** (deterministic - do NOT hand-run a glob;
   the earlier prose version had a cwd trap that silently produced an empty file and a
   false "fresh" on a real re-review):
   - `output/prior-runs.tsv` - sealed reviews of THIS SAME PR# from earlier runs. If
     non-empty, this is a **re-review**: 04 forms findings BLIND first, then reads a
     prior same-PR review only to reconcile, and 06 discloses it. Empty = fresh. (A
     prior review of a *different* PR is lineage, handled separately in 04.)
   - `output/seal.tsv` - `pr_head_sha`, `local_head_sha`, `dirty`, `diverged`. The
     sealed `pr.diff` IS the PR head; `diverged=yes` (a different local commit OR a
     dirty working tree) means on-disk reads may not be in the reviewed diff - the input
     to 04's out-of-seal rule.
   - **When `diverged=yes`, record the review-target decision in
     `output/seal-decision.tsv` before proceeding** (04's gate `checks/review-precondition.sh`
     blocks the review Write without it). Surface the divergence to the human
     (`pr_head_sha` vs `local_head_sha`, N commits, dirty?) and write three rows:
     `target` (`sealed` | `working-tree`), `human_approved` (`yes` | `no`), `note`.
     **Default `target=sealed`**: review the actual PR - reproducible, and the
     divergence is reported as one finding. `target=working-tree` (review the local code
     instead) is allowed ONLY with the human's explicit `human_approved=yes`, and makes
     the whole review non-reproducible/out-of-seal. Do not pick `working-tree` on your
     own. If `diverged=no`, no decision file is needed.

**Run discipline (cwd + one model per run).** Two working directories coexist and
mixing them is the most common operational failure: tools read/write a
cwd-relative `output/`, so run each tool from its stage dir (`cd <abs-run-dir>/<stage>`);
`icm.sh` resolves `.icm` from the repo root, so run every `icm.sh` command from
there (`cd <abs-repo-root>`) - if `icm.sh` reports "no active run" it is almost
always a wrong cwd (it now prints a hint naming the repo root). A pr-review run
should complete under ONE model/session: after any interruption or model switch,
run `icm.sh next kakkoidev/pr-review` and trust ITS answer for the next empty
stage - never re-run a stage that already has a stage-done (the runtime warns on
duplicate closures and audit flags them), and never emit an estimated stage-done
to "catch up" (seal refuses estimated counts).

## After Output (MANDATORY)
Run from the repo root - `icm.sh` resolves `.icm` cwd-relative:
```bash
cd <abs-repo-root> && \
  bash ~/.agents/skills/icm/runtime/icm.sh stage-done kakkoidev/pr-review --stage 01-context
```

## Outputs
| Artifact | Location | Format |
|----------|----------|--------|
| PR context | output/pr-context.md | Summary (title, repo, #, state, author, dates, size, labels, linked issues); file buckets (prod/test/config/generated/lockfile/docs with paths); chronological action feed (ts, who, event, note) |
| Link set | output/links.tsv | One row per discovered URL: `<url>\t<source>` (PR-body, comment:<author>, review:<author>, commit). Deterministic and complete - every link in the PR's free text. |
| Checklist | output/checklist.tsv | One row per PR-template checkbox in the body: `checked`/`unchecked` <TAB> item text. The tick state is the author's claim; stage 04 audits each item against the diff. Empty if the repo has no template checklist. |
| PR template | output/pr-template.md | The repo's PR template (fetched from the common `.github/PULL_REQUEST_TEMPLATE.md` paths), so 04 can tell a mandatory item the body DROPPED from one that was genuinely absent. A placeholder line if no template exists. |
| Prior runs | output/prior-runs.tsv | Written by `gather-pr` (deterministic, no cwd trap): paths to sealed `REVIEW-<PR#>.md` from earlier runs of THIS SAME PR (empty = fresh). Non-empty makes this a re-review: 04 forms findings blind before reading a predecessor, 06 discloses independence. |
| Seal | output/seal.tsv | `pr_head_sha`, `local_head_sha`, `dirty` (yes/no), `diverged` (yes/no). Reviewed-revision provenance: `pr.diff` is the PR head; `diverged=yes` (different local commit OR dirty tree) means on-disk reads may be out-of-seal (04). |
| Seal decision | output/seal-decision.tsv | Written ONLY when `diverged=yes`: `target` (`sealed`/`working-tree`), `human_approved` (`yes`/`no`), `note`. Records which revision the review targets; 04's gate blocks the review Write without it (working-tree needs human_approved=yes). |
| Diff | output/pr.diff | `gh pr diff` output - the exact change under review, sealed with the context so the review stage reads a reproducible artifact, not an ad-hoc re-fetch. |
