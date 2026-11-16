# Stage 07: pr-agent second opinion

<!-- ICM-TOOLS expect="(Bash|Read)" -->
<!-- ICM-GATE tools="Bash" run="test -s ../06-report/output/report-receipt.md" -->

Run pr-agent (The-PR-Agent/pr-agent, pinned 0.50.0) `review` on the same sealed diff,
with its LLM calls served by `claude -p` (Opus 5.5, the user's own Claude login - no API
key), save its findings beside this run's review, and publish them on the PR as ONE comment
that opens with `<!-- pr-agent-review -->` and names pr-agent, so the public record shows
which reviewer said what. This comment is the one exception to 06's no-plain-comment rule,
by the captain's decision of 2026-11-16 ("I want it to publish. that would make a public
record and we could inspect it later"); 06's rule still holds for this skill's own findings.
It runs AFTER 06 so its output cannot leak into this skill's
findings or its pending review.

## Inputs
| Source | Location | Scope |
|--------|----------|-------|
| Sealed diff | ../01-context/output/pr.diff | the exact diff 04-06 reviewed |
| PR context | ../01-context/output/pr-context.md | `<owner>/<repo>` and the PR number |

## Process
1. Run the tool (`<owner>/<repo>` and `<PR#>` from pr-context):
   ```bash
   bash ~/.agents/skills/kakkoidev/pr-review/tools/run-pr-agent ../01-context/output/pr.diff output <owner>/<repo> <PR#> --publish
   ```
   `--publish` is the only switch that posts. Drop it to keep the findings local (the
   `Published:` line then reads `no`). pr-agent itself never holds a GitHub token; the tool
   posts with `gh` only after a review that actually ran.
   - `STATUS: BLOCKED` (no `claude` CLI on PATH): the stage is complete; tell the user.
   - Non-zero exit (version drift, failed review, failed post): report the error and
     `pr-agent.log`; do not reinstall or change the pin inside a review run. A failed review
     is never posted.
2. Do NOT merge pr-agent's findings into `REVIEW-<PR#>.md` or the pending review. Tell the
   user the `Published:` URL and the path of `PR-AGENT-<PR#>.md`.

## After Output (MANDATORY)
```bash
bash ~/.agents/skills/icm/runtime/icm.sh stage-done kakkoidev/pr-review --stage 07-pr-agent
bash ~/.agents/skills/icm/runtime/icm.sh seal kakkoidev/pr-review
```

## Outputs
| Artifact | Location | Format |
|----------|----------|--------|
| pr-agent findings | output/PR-AGENT-<PR#>.md | `# pr-agent findings` title, `STATUS: RAN\|BLOCKED\|FAILED`, `Published: <comment url>\|no (<why>)\|failed (<why>)`, then pr-agent's review markdown verbatim |
| Posted body | output/pr-agent-comment.md | the exact PR comment body (`--publish` only) |
| Structured review | output/pr-agent-review.json | pr-agent `--json-output` (RAN only) |
| Run log | output/pr-agent.log | pr-agent stdout/stderr (RAN/FAILED only) |
