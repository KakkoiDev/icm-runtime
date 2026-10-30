# Stage 02b: Comment pass (second look, comments now readable)

<!-- ICM-TOOLS expect="(Read|Bash|Write|mcp__claude_ai_Notion__notion-fetch|mcp__claude_ai_Notion__notion-get-comments)" -->
<!-- ICM-GATE tools="Write" run="checks/blind-done.sh" -->

The blind review is done and frozen. Now read every comment on the page and take a
second pass over the same findings, this time knowing what the team has already
said. Three jobs, in this order: confirm or kill each finding against the live
threads, record what was promised in a comment and never written into the document,
and decide which existing threads need a reply rather than a new one.

**Why the order is blind-first, comments-second.** The obvious design is to fold the
comments into the document before reviewing it, so nobody wastes effort on text that
has been superseded. That design is wrong, for a reason worth stating: if
supersessions are pre-applied, the gap between what the body says and what the
comments say is absorbed silently and becomes unmeasurable. That gap is the single
most valuable output of this stage. Reviewing the body cold and then diffing against
the threads makes drift a first-class finding instead of an invisible correction.
It also keeps stage 02's blindness structural, since the comments were never fetched
at all, rather than relying on a gate to prove a stage did not peek.

**Nothing new is discovered here.** If a lens fires on something you notice while
reading comments, it belongs in a later run. A finding that skipped the refutation
and grounding passes is not a finding.

## Inputs
| Source | Location | Scope |
|--------|----------|-------|
| Findings | ../02-blind-review/output/findings.md | every `## F<n>` and `## R<n>` block, frozen |
| Story body | ../01-gather/output/story-body.md | for the `discussion-urls` spans and to check what the body actually says today |
| Target id | ../01-gather/output/target-id.txt | the page to harvest |
| Impl facts | ../01-gather/output/impl-facts.md | for judging whether a comment's answer matches the code |

## Process

1. **Harvest every comment. Completely. This is gated, not trusted.**

   `notion-get-comments` truncates silently on pages with many discussions, and the
   truncation notice is a bare attribute inside an XML blob:
   `total-count="24" shown-count="8"`. On the run that produced this stage, that
   line was read as complete. Sixteen threads went unread; a finding was published
   as "still unanswered" when the owner had answered it four hours below the comment
   that was read, two other findings were already closed, and a live self-correction
   was missed. **A truncated read is not a reconciliation.** Assume truncation and
   prove otherwise:

   1a. Fetch the page with `mcp__claude_ai_Notion__notion-fetch` and
       `include_discussions: true`. Take the authoritative count from
       `<page-discussions discussion-count="N">` and write it as the FIRST line of
       `output/discussions.md`:
       ```
       Declared: N
       ```
       Take it from that attribute, never from a `shown-count`, and never lower it
       later to make a check pass.
   1b. Enumerate every discussion id from two sources and union them: the
       `discussion-urls="discussion://..."` attributes throughout the fetched body,
       and the `<page-discussions>` summary. Page-level discussions are anchored to
       no block and appear in no body span, which is why both sources are needed.
   1c. Call `mcp__claude_ai_Notion__notion-get-comments` once per discussion id with
       `discussion_id:`, appending each `<discussion ...>` block verbatim to
       `output/discussions.md`. Also make one bulk call with
       `include_all_blocks: true` and `include_resolved: true` first; it is cheaper
       when it happens to be complete, and its `total-count` cross-checks 1a.
       Resolved threads are in scope: a resolved thread can still hold the decision
       that kills a finding.
   1d. Gate it:
       ```bash
       ~/.agents/skills/kakkoidev/story-review/tools/discussion-coverage \
         output/discussions.md ../01-gather/output/story-body.md \
         > output/coverage.txt
       ```
       Non-zero exit means the harvest is partial. Fetch what is missing and re-run.
       Do not proceed, and do not write a disposition for any finding, until this
       exits 0.

2. **Mechanical thread state.** Read the page's owner from the fetched properties
   (the `PM Owner` / assignee user id) and run:
   ```bash
   ~/.agents/skills/kakkoidev/story-review/tools/thread-state \
     output/discussions.md <owner-user-id> > output/thread-state.tsv
   ```
   The tool decides only what a script can decide: who spoke last, how long ago,
   and whether the owner ever spoke in the thread. `NO_OWNER_REPLY` is strictly
   worse than `AWAITING_OWNER`: nobody with authority has looked at all.

   **Derive the staleness threshold from this page, do not invent one.** Compute the
   owner's observed reply lag across threads where they did reply, and call an
   `AWAITING_OWNER` thread stale when it exceeds that. A hardcoded "3 days" is a
   number nobody can defend; "twice this owner's own median turnaround" is.

3. **Promise ledger (deterministic enumeration).**
   ```bash
   ~/.agents/skills/kakkoidev/story-review/tools/commitment-scan \
     output/discussions.md > output/commitments.tsv
   ```
   This is the highest-yield check in the stage and it finds a failure no
   spec-quality lens can see. The pattern, measured across two stories: the owner
   answers in a comment, says "I'll put it in the AC", and the document is never
   edited. Three separate reviewers on one page each independently wrote a variant
   of "Where can I find this? I cannot find the new wording", and on that page the
   owner had stated outright that they did not want to edit the body because a
   rewrite would disconnect the existing comments. Everyone downstream then reviews
   text the owner has already replaced, and cannot tell.

   **Every row in `commitments.tsv` gets a disposition in
   `output/drift-ledger.md`**, no silent omission (same contract as stage 01's
   sibling manifest):
   - `LANDED: <thread> - <promise> - body text that satisfies it`
   - `NOT LANDED: <thread> - <promise> - what the body says instead`
   - `NOT A PROMISE: <thread> - <matched sentence> - why the pattern misfired`
     (the marker list is deliberately generous; a false positive costs one line)

   Then do the same for `## Self-corrections`. A reversal is the higher-severity
   half: the thread's middle is now wrong, and anyone who read it before the
   reversal, or who reads it top-down, carries the withdrawn answer forward. Record
   each as `REVERSED: <thread> - <what was withdrawn> - <what replaced it>`, and
   check whether the withdrawal itself ever reached the body.

4. **Disposition every finding.** Every `## F<n>` gets exactly one verdict. Read the
   thread's LAST comment, never its first.

   | Verdict | Meaning |
   |---------|---------|
   | `UNRAISED` | no thread touches it. Eligible to send as a new comment. |
   | `ANSWERED` | asked, answered, and the body reflects the answer. Closed. |
   | `ANSWERED IN COMMENT ONLY` | the answer exists but the body does not carry it. The finding is resolved; the document is not. Cross-reference the drift ledger. |
   | `PARTLY ANSWERED` | the general question was answered, a specific sub-case was not. Narrow to the unanswered part. |
   | `NON-ANSWER` | the owner replied but did not address what was asked. Re-ask, narrowed to the unaddressed part, as a reply in the existing thread. |
   | `STALE ANSWER` | a later owner comment supersedes the answer this thread ends on, and the thread was never corrected. |
   | `DECIDED AGAINST` | the owner considered this and chose the other way. Not sent, flagged loudly: re-asking reads as not having read the thread. |
   | `VOID (SUPERSEDED TEXT)` | the finding quotes body text that a comment has since replaced. The finding is about text nobody will implement. State the replacement text. |

   `VOID (SUPERSEDED TEXT)` exists because it happened: a set of findings was
   generated against a page body whose acceptance criteria the owner had already
   rewritten in a comment three days earlier, and the review was published without
   anyone noticing the reviewed text was dead. Check every finding's `> ` quote
   against the comment threads for a replacement before trusting it.

   Two shapes that read as `UNRAISED` to a keyword search and are the worst things
   to re-send: a proposal that was raised and overruled (`DECIDED AGAINST`), and a
   question answered in a thread anchored to a *different* block than the one the
   finding quotes. Search by topic, not by block.

5. **Plan the reply, not just the comment.** For each finding and each stale thread,
   name the action. A new top-level comment is only one of the options and often the
   wrong one:
   - `NEW COMMENT` - `UNRAISED`. A fresh thread on the quoted block.
   - `REPLY: NUDGE` - `AWAITING_OWNER` past this page's own threshold. The question
     is already well posed; it just needs an answer. Do not restate it.
   - `REPLY: RE-ASK` - `NON-ANSWER`. Quote what was asked, quote what came back,
     name the gap between them in one sentence.
   - `REPLY: FLAG STALE` - `STALE ANSWER`. Point at the newer decision and ask
     which one holds.
   - `REPLY: LAND IN BODY` - `ANSWERED IN COMMENT ONLY`. Ask for the agreed text to
     be written into the document, and say which reviewers were blocked by its
     absence. Where many promises are outstanding, this is ONE comment naming the
     pattern, not one per promise: seven separate nudges to write things down is the
     volume problem this skill exists to avoid.
   - `NO ACTION` - `ANSWERED`, `DECIDED AGAINST`, `VOID`.

   A reply goes in the existing thread. Never open a second thread on a question
   that already has one; that splits the answer across two places and is how a
   thread ends up with three reviewers asking where the spec went.

## After Output (MANDATORY)
```bash
bash ~/.agents/skills/icm/runtime/icm.sh stage-done kakkoidev/story-review --stage 02b-comment-pass
```

## Outputs
| Artifact | Location | Format |
|----------|----------|--------|
| Discussions | output/discussions.md | `Declared: N` as the first line, then every `<discussion ...>` block verbatim. Complete by construction: `tools/discussion-coverage` must exit 0 against it. |
| Coverage proof | output/coverage.txt | `tools/discussion-coverage` output, ending in its `ok:` line. A file whose last line is a `FAIL:` is a stage failure, not a limitation to note. |
| Thread state | output/thread-state.tsv | `tools/thread-state` output plus its `## Summary` and `## Oldest unanswered` sections. |
| Commitments | output/commitments.tsv | `tools/commitment-scan` output: `## Commitments`, `## Self-corrections`, `## Summary`. |
| Drift ledger | output/drift-ledger.md | `## Promises` with one `LANDED:` / `NOT LANDED:` / `NOT A PROMISE:` line per row of `commitments.tsv`'s `## Commitments`, then `## Reversals` with one `REVERSED:` line per `## Self-corrections` row, then `## Threshold` stating this page's observed owner reply lag and the staleness cutoff derived from it. Every row accounted for; a row present in `commitments.tsv` and absent here is a stage defect. |
| Dispositions | output/dispositions.md | One row per `## F<n>` and `## R<n>` from findings.md: `<id> \| <verdict from step 4> \| <action from step 5> \| <thread id or "none"> \| <one-line evidence: the quoted comment text and its date>`. Every id appears exactly once. A `## Summary` section counts each verdict. |
