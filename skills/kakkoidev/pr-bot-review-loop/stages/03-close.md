# Stage 03: Close (clean up, then hand to a human)

<!-- ICM-TOOLS expect="(Bash|Read)" -->
<!-- ICM-GATE tools="Write" run="checks/loop-exit.sh" -->

The gate is the exit condition itself: `checks/loop-exit.sh` runs
`ledger-audit --mode converged` and blocks this stage's Write until the loop has actually
converged. If it fails, the answer is another round, not an edit to the ledger.

This is the diagram's last edge - `E --否--> G` - and the human on the other side of it is
the point of the whole process. Everything here exists so they inherit a PR they can read,
not a transcript they have to reconstruct.

## Inputs
| Source | Location | Scope |
|--------|----------|-------|
| Ledgers | ../02-round/output/rounds.tsv, ledger.tsv | every round and every finding with its disposition |
| PR body | ../02-round/output/pr-body.md | the description as the loop left it |
| Exit head | ../02-round/output/exit-head.tsv | the head the last round reviewed (R9) |
| Bot reports | ../02-round/output/bot-comments-\<last\>.tsv | which reports are superseded and still expanded (R11) |
| Request comments | ../02-round/output/request-\<n\>.tsv (every round) | the `request_comment_id` and `request_author` the loop posted each round, collapsed in full including the last (R11) |
| CI reads | ../02-round/output/ci-\<n\>.tsv | for the honest CI line (R8) |

## Process

1. **Confirm convergence in writing.** The gate has already run; restate what it found in
   `close.md`: which round was the quiet one, the head it reviewed, and that nothing was
   pushed after it. If the gate failed, you are not in this stage - go back to 02.

2. **Collapse the superseded bot reports AND every request comment (R11) - this is the
   closing step, not a per-round one.** While rounds were still coming, that history was
   what the next round and the human read. Now it is noise. Two separate cleanups, both
   dry-run first:

   **a. Bot reports - every one except the newest, which stays visible:**
   ```bash
   bash ~/.agents/skills/kakkoidev/pr-bot-review-loop/tools/mark-superseded \
     <owner>/<repo> <pr#> ../02-round/output/bot-comments-<last>.tsv --bot <bot-login> \
     > output/superseded.tsv
   bash ~/.agents/skills/kakkoidev/pr-bot-review-loop/tools/mark-superseded \
     <owner>/<repo> <pr#> ../02-round/output/bot-comments-<last>.tsv --bot <bot-login> --apply \
     >> output/superseded.tsv
   ```

   **b. Our own review-request comments - every one, INCLUDING the last** (captain's
   ruling, 2026-09-09: a request comment is pure machinery - "@claude review, round N,
   head is X" - and carries nothing a human or a later bot needs; unlike a bot report there
   is no "current" one to protect):
   ```bash
   bash ~/.agents/skills/kakkoidev/pr-bot-review-loop/tools/gather-requests \
     <owner>/<repo> <pr#> ../02-round/output output/requests.tsv
   req_author=$(awk -F'\t' '$1=="request_author"{print $2; exit}' ../02-round/output/request-1.tsv)
   bash ~/.agents/skills/kakkoidev/pr-bot-review-loop/tools/mark-superseded \
     <owner>/<repo> <pr#> output/requests.tsv --bot "$req_author" \
     > output/superseded-requests.tsv
   bash ~/.agents/skills/kakkoidev/pr-bot-review-loop/tools/mark-superseded \
     <owner>/<repo> <pr#> output/requests.tsv --bot "$req_author" --apply \
     >> output/superseded-requests.tsv
   ```
   `gather-requests` marks every row `superseded=yes` (there is no exempt "latest" row for
   request comments), so `mark-superseded` - unmodified, same tool as (a) - collapses all
   of them, last one included.

   Both mutations go through the approved wrapper at its `/graphql` path
   (`gh-axi api POST /graphql`) - the plain GitHub CLI route for `minimizeComment` is
   refused as a write - and every target within each is batched into one aliased call, so
   each cleanup costs one approval. Proven and executed on PR 26204 (seven bot reports and
   all seven request comments collapsed).

   The tool refuses anything not authored by the given login, and cannot reach a review, a
   review thread, or a human's pending draft review. Any `REFUSE` row is a signal to stop
   and look, not to add a flag. Review threads are **not** minimized - they were answered
   and resolved in 02 (R10).

3. **Re-gather and run the closed audit.** The counts in the last round's TSV predate the
   cleanup, so refresh them before checking that the cleanup happened - bot reports via
   `gather-round`, request comments via `gather-requests` re-run against the now-collapsed
   live state:
   ```bash
   bash ~/.agents/skills/kakkoidev/pr-bot-review-loop/tools/gather-round \
     <owner>/<repo> <pr#> final output <bot-login>
   bash ~/.agents/skills/kakkoidev/pr-bot-review-loop/tools/gather-requests \
     <owner>/<repo> <pr#> ../02-round/output output/requests-final.tsv
   bash ~/.agents/skills/kakkoidev/pr-bot-review-loop/tools/ledger-audit \
     --rounds ../02-round/output/rounds.tsv --ledger ../02-round/output/ledger.tsv \
     --pr-body ../02-round/output/pr-body.md \
     --exit-head ../02-round/output/exit-head.tsv \
     --final-round output/round-final.tsv \
     --final-bot-comments output/bot-comments-final.tsv \
     --final-requests output/requests-final.tsv \
     --mode closed > output/ledger-audit.tsv
   ```
   Every row must be `PASS`. A `FAIL` here is unfinished work, never a note in the report.

4. **Finish the PR description.** It must carry, in the author's own words and not as a
   dump of this run's TSVs:
   - the refusal ledger - each refused finding, whether the *finding* or the *fix* was
     refused, and the reason (R3);
   - each out-of-scope item with its follow-up ticket ID (R6);
   - how many rounds ran and which commit the final round reviewed (R2, R9).

5. **State CI honestly in one line (R8).** Name each check's real state, with every
   SUSPECT resolved as *real failure* or *infrastructure* and what you read to decide.
   "CI is green" is a claim about a colour; say what passed.

6. **Human handoff.** End `close.md` with what the human is being asked to do: review the
   code, not the loop. Tell them explicitly what the loop did **not** cover - every
   `refused-finding-wrong` and `refused-fix-wrong` is a judgment they may reverse, and
   every `out-of-scope` item is a real problem this PR is deliberately leaving in place.
   The bot's review is the weak one; theirs is the one that decides.

## After Output (MANDATORY)
```bash
bash ~/.agents/skills/icm/runtime/icm.sh stage-done kakkoidev/pr-bot-review-loop --stage 03-close
```

## Outputs
| Artifact | Location | Format |
|----------|----------|--------|
| Close report | output/close.md | Convergence statement (which round was quiet, on which head, nothing pushed after it); the cleanup result; the refusal ledger and out-of-scope tickets as they now read in the PR description; the honest CI line with every SUSPECT resolved; and the human handoff naming what the loop did not settle. |
| Audit | output/ledger-audit.tsv | `ledger-audit --mode closed` output - every row `PASS`. Any `FAIL` is unfinished work. |
| Cleanup record | output/superseded.tsv | `mark-superseded` dry-run then apply output for bot reports: one row per report, `WOULD-MINIMIZE` / `MINIMIZED` / `SKIP` / `REFUSE` / `FAILED`, plus the `# mode=` accounting line. |
| Request-comment cleanup record | output/requests.tsv, output/superseded-requests.tsv | `gather-requests` output (every row `superseded=yes`) and `mark-superseded` dry-run then apply output for it - every request comment collapsed, including the last. |
| Final round metrics | output/round-final.tsv, output/bot-comments-final.tsv, output/requests-final.tsv | The post-cleanup re-gather the closed audit reads: `bot_comments_superseded_expanded` must be 0, the final bot report must still be visible, and every request comment in `requests-final.tsv` must be `minimized=yes`. |
