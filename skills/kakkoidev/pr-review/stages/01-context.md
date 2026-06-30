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
1. Run the deterministic gather tool, writing into this stage's `output/`:
   ```bash
   bash ~/.agents/skills/kakkoidev/pr-review/tools/gather-pr <owner>/<repo> <pr#> output
   ```
   It writes `output/pr-context.md` (summary header, file buckets, action feed),
   `output/links.tsv` (every URL in the PR's free text, with source), and
   `output/pr.diff` (the change under review, sealed so the review is reproducible).
2. Do NOT hand-edit either file. If the tool errors (auth, missing PR), report
   the exact error to the user and stop - do not fabricate context.
3. Read `output/pr-context.md` so you know the PR; note the bucket counts and any
   linked Notion/Slack/requirement URLs you will follow in stage 02.

## After Output (MANDATORY)
```bash
bash ~/.agents/skills/icm/runtime/icm.sh stage-done kakkoidev/pr-review --stage 01-context
```

## Outputs
| Artifact | Location | Format |
|----------|----------|--------|
| PR context | output/pr-context.md | Summary (title, repo, #, state, author, dates, size, labels, linked issues); file buckets (prod/test/config/generated/lockfile/docs with paths); chronological action feed (ts, who, event, note) |
| Link set | output/links.tsv | One row per discovered URL: `<url>\t<source>` (PR-body, comment:<author>, review:<author>, commit). Deterministic and complete - every link in the PR's free text. |
| Diff | output/pr.diff | `gh pr diff` output - the exact change under review, sealed with the context so stage 03 reviews a reproducible artifact, not an ad-hoc re-fetch. |
