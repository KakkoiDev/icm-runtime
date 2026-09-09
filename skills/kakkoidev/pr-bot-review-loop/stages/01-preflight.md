# Stage 01: Preflight (what must be true before the first round)

<!-- ICM-TOOLS expect="(Bash|Read)" -->

The loop is cheap to run and expensive to run wrong. This stage establishes the four
things every later stage assumes: the strong review already happened, the bot can
actually be summoned, the PR's own defect class is named, and the ledger exists.

## Inputs
| Source | Location | Scope |
|--------|----------|-------|
| PR reference | the chat that started the run | `<owner>/<repo>` and the PR number |
| Ticket | the chat that started the run | the ticket the PR is scoped to - the boundary R6 defends |
| Strong review | the sealed `REVIEW-<PR#>.md` from `kakkoidev/pr-review` | what has already been found, so the loop does not re-litigate it |

## Process
1. **Read `references/loop-rules.md` end to end** (all twelve, with their reasons) before
   doing anything else. The stages cite them as `R<n>` and assume you have read them; a
   rule you have not read is a rule you will break at 2am on round 7.
2. **Refuse to start without the strong review.** This skill runs *after*
   `kakkoidev/pr-review`, not instead of it - the diagram's 「強い」 review is the local
   one with the repo checked out, the suite runnable and the ticket fetched. If no sealed
   `REVIEW-<PR#>.md` exists for this PR, stop and run that skill first. Record the path of
   the review you found; "I read the diff carefully" is not the strong review.
3. **Establish the bot's identity and that it can be summoned (R1).** Record two separate
   facts, both from evidence, not memory:
   - `bot_login` - the login the bot posts under, read from an existing bot comment on
     this repo (`gh-axi api "/repos/<owner>/<repo>/issues/<pr#>/comments" --jq '[.[].user.login] | unique'`),
     or from another PR in the repo if this one has no bot activity yet.
   - `mention_handle` - the literal string that triggers it, normally `@claude`. If the
     repo has never been triggered by a mention, say so: the first round is then also a
     test of whether the trigger exists, and R1's `UNCONFIRMED` verdict is the expected
     first result, not a failure to hide.
4. **Name the PR's own defect class in one sentence (R5), and write it down.** What kind
   of mistake is *this* change prone to - a missing guard, an unhandled depth, a wrong
   rounding, a lost tenant filter, an off-by-one in a boundary? Every round re-runs this
   specific check over its own fixes, because the loop's fixes are new unreviewed code
   written under pressure from a review comment. On PR 26205 the HIGH caught at round 9
   was introduced by an earlier round's fix; naming the class up front is what makes that
   check possible instead of a hope.
5. **Record the base ref** the revert proofs will run against (usually the PR's merge
   base). `check-revert-proof --base <ref>` needs it and getting it wrong makes every
   proof meaningless.
6. **Initialise the ledger.** Write `output/rounds.tsv` and `output/ledger.tsv` containing
   only their `#` column-header comment lines (the formats are documented in
   `tools/ledger-audit`). Stage 02 appends to them; nothing else creates them.

## After Output (MANDATORY)
```bash
bash ~/.agents/skills/icm/runtime/icm.sh stage-done kakkoidev/pr-bot-review-loop --stage 01-preflight
```

## Outputs
| Artifact | Location | Format |
|----------|----------|--------|
| Preflight | output/preflight.md | The PR and its ticket; the path of the sealed strong review (or a stop); `bot_login` and `mention_handle` with the evidence each came from; the PR's defect class in one sentence (R5); the base ref for revert proofs; and a one-line statement that the twelve rules were read. |
| Rounds ledger | output/rounds.tsv | Created empty except for the `#` header comment. Columns per `tools/ledger-audit`: round, request_verdict, reviewed_sha, head_sha, stale, findings, actionable, threads_open, threads_unanswered, pushed_sha, defect_class_recheck. |
| Findings ledger | output/ledger.tsv | Created empty except for the `#` header comment. Columns: round, finding_id, severity, disposition, reason, evidence. |
