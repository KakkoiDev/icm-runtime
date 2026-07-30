# Stage 04: Handoff (the deliverable)

<!-- ICM-TOOLS expect="(Read|Bash|mcp__claude_ai_Notion__notion-fetch|mcp__claude_ai_Notion__notion-get-comments)" -->
<!-- ICM-GATE tools="Write" run="checks/reviewed.sh" -->

Turn the audited findings into the thing a human actually uses: a tiered list of
decision-owner questions, each with a pre-written comment and a link to the exact
block it goes on. Nothing new is discovered here. If you notice a fresh issue while
writing this stage, it belongs in a later run, not smuggled in past the refutation
and grounding passes every other finding went through.

**Why this stage exists.** For three validated runs the final artifacts were
`findings.md` (raw, engineer-facing, flat severity) and a coverage report (a
self-test of the skill, useless to anyone reviewing the story). A human then
hand-built the real deliverable twice: tiering, the question to ask, and the block
to ask it on. On one of those runs the per-story deliverables for three of five
stories were written to a scratchpad OUTSIDE the sealed run and were gone by the
time anyone looked.

**Reconciliation already happened, in stage 02b.** Do not re-derive it. Stage 02b
harvested every comment under a completeness gate and gave each finding a verdict;
this stage consumes `dispositions.md` and tiers what survived. Why it matters that
somebody did it: on the run that produced this design, **12 of 30 findings were
already answered before the review ran**, three of them decided the opposite way,
and one repeated a conflation the PM had corrected that same day. Sending those
would have cost the reviewer's credibility on the 16 that were real.

You may still read the threads here, to quote a comment exactly in a draft. You may
not overturn a 02b verdict on a re-skim; if a verdict looks wrong, the harvest or
the disposition is wrong and 02b is the stage to fix.

## Inputs
| Source | Location | Scope |
|--------|----------|-------|
| Findings | ../02-blind-review/output/findings.md | surviving `## F<n>` blocks and refuted `## R<n>` blocks |
| Dispositions | ../02b-comment-pass/output/dispositions.md | the verdict and planned action per finding - authoritative, do not re-derive |
| Drift ledger | ../02b-comment-pass/output/drift-ledger.md | promises made in comments and never written into the body; owner self-corrections |
| Thread state | ../02b-comment-pass/output/thread-state.tsv | which threads are awaiting the owner, and for how long |
| Discussions | ../02b-comment-pass/output/discussions.md | the complete harvest, for exact comment quotes and block ids |
| Grounding audit | ../03-score/output/grounding-audit.md | which findings are grounded; the confidence distribution |
| Coverage report | ../03-score/output/coverage-report.md | `## New candidates` (only meaningful when scoring applied) |
| Self-audit | ../03-score/output/self-audit.md | which matched rows were coincidental |
| Story body | ../01-gather/output/story-body.md | for AC numbering and exact quotes |
| Target id | ../01-gather/output/target-id.txt | the page to fetch block ids for |

## Process

1. **Get the block ids (deterministic first).** A finding without a link to its
   block makes a human hunt for the acceptance criterion before they can comment.
   Preferred path, complete:
   ```bash
   NOTION_TOKEN=<integration secret from the environment, never from a .env file> \
   ~/.agents/skills/kakkoidev/story-review/tools/fetch-block-ids \
     "$(cat ../01-gather/output/target-id.txt)" \
     > output/block-ids.tsv
   ```
   This returns EVERY block, including ones with no discussion yet. Those are
   exactly the blocks where a new thread must be started, so they are the ones you
   most need.

   **Fallback, partial:** if no token is available or the tool reports
   `object_not_found` (the page tree is not shared with that integration, a one-time
   human step in Notion's UI that no bot can perform for itself), fetch the page with
   `mcp__claude_ai_Notion__notion-fetch` and `include_discussions: true` and take
   block ids from the `discussion-urls="discussion://<page>/<block>/<disc>"`
   attributes. Know the limit before relying on it: this exposes a block id **only
   as a side effect of that block already carrying a discussion.** A block with no
   comments yet stays invisible, and those are frequently the highest-value targets.
   Write the fallback and its consequence into `## Limits`.

   **Never invent, guess, or approximate an anchor, and never substitute a
   neighbouring block's id.** A link that scrolls to the wrong line is worse than no
   link: the human trusts it. Where no id is obtainable, write
   `no link available` plus the exact manual route (hover the line, open the drag
   handle, Copy link to block) and quote enough of the block's text to find it.

2. **Read stage 02b's verdicts as given.** Every `## F<n>` already carries one of
   eight verdicts and a planned action. What each verdict means for this stage:

   | 02b verdict | Tierable? | Form it takes here |
   |-------------|-----------|--------------------|
   | `UNRAISED` | yes | a new comment on the quoted block |
   | `PARTLY ANSWERED` | yes, narrowed to the unanswered part | a reply in the existing thread |
   | `NON-ANSWER` | yes | a reply quoting what was asked and what came back |
   | `STALE ANSWER` | yes | a reply pointing at the newer decision |
   | `ANSWERED IN COMMENT ONLY` | not as a spec question | folds into the single `## Land in the body` ask |
   | `ANSWERED` | no | `## Already answered`, with the answer |
   | `DECIDED AGAINST` | no | `## Already answered`, flagged loudly |
   | `VOID (SUPERSEDED TEXT)` | no | `## Already answered`, with the replacement text |

   A finding whose 02b verdict is `ANSWERED`, `DECIDED AGAINST`, or `VOID` never
   appears in a tier, no matter how severe the blind review rated it. Re-asking a
   settled question reads as not having read the thread and costs the credibility of
   everything sent alongside it.

3. **Tier by consequence. Three tiers, and the test is the damage, not the
   interest.**

   **Tier 1 - disaster if it ships unresolved.** The damage must be one of:
   money that is silently wrong at scale; duplicated or corrupted financial
   records; a foundational trigger or ownership ambiguity that forces data-model
   rework or rework of another story; a state a user cannot recover from. To place
   something here you must be able to write, in one sentence, **the concrete bad
   outcome AND why nothing downstream catches it.** If an implementer or QA would
   trip over it during the build, it is not tier 1. "Both readings compile and look
   correct" is the strongest tier-1 signal there is.

   **Tier 1 is capped at 5 items.** If more than five qualify, rank them and push
   the remainder to the top of tier 2 with a one-line note saying they were cut for
   volume. The cap exists because the failure mode this stage was built to fix is a
   30-item list that buried four real problems. A tier 1 of twelve is the same
   failure wearing a new label.

   **Tier 2 - must share.** A real decision worth making, but an implementer or QA
   would surface it, or the fix stays local. Not noise, not project-ending.

   **Tier 3 - everything else, in priority order.** Rank by cost of delay: things
   that get expensive once code exists (a structural choice that would leave two
   incompatible shapes in one table) go above wording fixes.

   Severity from `findings.md` does NOT map to tier. A low-severity undefined
   permission that two other stories already depend on outranks a high-severity
   edge case nobody will hit. State the tier reason in the finding's own terms.

4. **Write the question, not the complaint.** "The rounding basis is undefined" is a
   finding. "Should the order amount use the tenant's rounding settings, the source
   estimate's, or the form's own?" is a question. Enumerate the options when there
   are few: a question with the options listed gets answered in one pass; an open
   one comes back as a meeting.

5. **Write each tier-1 item ready to paste, and say WHERE it goes.** Two to four
   sentences. Lead with the fact that makes it real (the schema or code evidence,
   concretely), then the question. Each item carries a `Block:` line and a `Thread:`
   line, because "post this" and "reply to this" are different actions:
   - `Thread: new thread` - a fresh top-level comment on the block.
   - `Thread: <discussion://...>` - a reply inside that existing thread. **Never
     open a second thread on a question that already has one.** That splits the
     answer across two places, and it is how a page ends up with three reviewers
     each asking where the spec went.

   Match the draft to 02b's planned action, because the four reply kinds read very
   differently and the wrong one is worse than silence:
   - `REPLY: NUDGE` - the question is already well posed. Do not restate it. One
     line asking for an answer, with the age. Restating a question the owner has
     already read is what makes a nudge feel like an accusation.
   - `REPLY: RE-ASK` - quote what was asked, quote what came back, name the gap in
     one sentence. Without both quotes it reads as not having read the reply.
   - `REPLY: FLAG STALE` - name the newer decision, cite its date, ask which holds.
   - `NEW COMMENT` - evidence, then the question.

   **No @mention of anyone** - the agreed protocol is to post untagged, re-read the
   page with the comments in place to confirm each landed on the block it was meant
   for, and only then tag a person per item. A drafted comment that tags someone
   removes that check. Do not draft comments for tiers 2 and 3; they are not being
   sent this round and pre-writing them is the volume problem again.

6. **One `## Land in the body` ask, not one per promise.** Read
   `../02b-comment-pass/output/drift-ledger.md`. Every `NOT LANDED:` row is spec the
   team agreed on that the document does not contain. This is not a spec-quality
   finding and must not compete with the tiers for attention, but it is frequently
   the highest-leverage thing on the page: when it is unfixed, every later reviewer
   works from text the owner already replaced, and cannot tell.

   Write ONE comment draft that names the pattern, lists the outstanding items
   compactly, and cites the reviewers who were blocked by the absence (their own
   words are the argument; nothing you write is as persuasive as three people
   independently asking where the spec went). Seven separate nudges to write things
   down is the volume problem again. Include every `REVERSED:` row here too, with
   what was withdrawn and whether the withdrawal ever reached the body: a reversed
   answer still sitting mid-thread is read as current by anyone scrolling.

   If the ledger has no `NOT LANDED:` and no `REVERSED:` rows, say so in one line.
   An absent section is indistinguishable from an unchecked one.

7. **Group by tier, tier 1 first, and make tier 1 complete enough to act on without
   scrolling.** A reader who stops after tier 1 must have the link, the thread, the
   question, and the paste-ready text for everything that would be a disaster.

8. **Carry the honesty forward.** These must survive rather than be smoothed away:
   each row's `Confidence` label verbatim from `findings.md`; any finding the
   self-audit marked `COINCIDENTAL` (keep the finding, drop the claim that it
   matched a known issue); a `## Refuted` section listing every `## R<n>` with its
   `Killed:` reason; and a `## Already answered` section for 02b's `ANSWERED`,
   `DECIDED AGAINST`, and `VOID (SUPERSEDED TEXT)` verdicts, each with the answer or
   the replacement text and its date. That section is not filler - it is what stops
   the next run from regenerating settled questions.

9. **State the limits.** One `## Limits` section naming at minimum: the grounding
   audit's `Grounded: N/M` and every ungrounded finding; whether coverage scoring
   applied or was `n/a`; which anchor path was used and, if the fallback, that
   thread-less blocks have no link; every lens with no material; any sibling that
   could not be fetched; and any `Plausible` row still waiting on code nobody read.

   Comment coverage is NOT a limit to confess here - it is a precondition proven in
   02b. Copy `coverage.txt`'s `ok: harvest complete (N/M ...)` line in verbatim as
   evidence. If you find yourself wanting to write "read N of M discussions", stop:
   the gate should have blocked this stage, and the fix is in 02b, not a caveat here.

10. **Do not act.** No Notion comments, no page edits, no ticket updates, no
    mentions. This file is the input to a human's decision about which questions to
    actually ask. The operator posts; this stage prepares.

## After Output (MANDATORY)
```bash
bash ~/.agents/skills/icm/runtime/icm.sh stage-done kakkoidev/story-review --stage 04-handoff
```

## Outputs
| Artifact | Location | Format |
|----------|----------|--------|
| Block ids | output/block-ids.tsv | `tools/fetch-block-ids` output (`block_id<TAB>type<TAB>anchor_url<TAB>text`), or the fallback's partial set with a header line naming it as partial. Absent only if neither path was available, which `## Limits` must then state. |
| Handoff | output/handoff.md | `# Story review handoff: <story id>`, then a `Grounded:` / `Survival rate:` line from the grounding audit. Then `## Tier 1 - disaster if it ships unresolved` (at most 5 rows) with columns `Order \| Finding \| Location \| Question \| Why this is disaster-class`, immediately followed by `### Tier 1 comments, ready to post`: per item a `Block:` line carrying a markdown link to the exact block (or `no link available` plus the manual route and enough quoted text to find it), a `Thread:` line reading either `new thread` or the `discussion://` id to reply inside, and the paste-ready text as a `>` quote, containing no @mention. Then `## Tier 2 - must share` and `## Tier 3 - everything else, in priority order`, questions only, no drafted comments. Then `## Land in the body` per step 6 (one comment draft covering every `NOT LANDED:` and `REVERSED:` row of the drift ledger, or one line stating the ledger was clean). Then `## Already answered` (02b's `ANSWERED` / `DECIDED AGAINST` / `VOID (SUPERSEDED TEXT)` verdicts with the answer or replacement text and its date), `## Refuted` (one row per `## R<n>` with its `Killed:` reason, stated explicitly as empty if nothing was refuted), and `## Limits` per step 9 including `coverage.txt`'s `ok: harvest complete` line verbatim. Every `## F<n>` from findings.md appears in exactly one of Tier 1/2/3 or `## Already answered`. |

## Anchor-format note

A block anchor is `https://app.notion.com/p/<page-id-no-dashes>#<block-id-no-dashes>`,
written as a **markdown link** `[text](url)`. Do not paste a bare URL: Notion
silently converts a bare block URL into a page mention and **strips the `#block`
fragment**, leaving a link that opens the page and scrolls nowhere. Observed live on
2026-07-30 - all four anchors in a handoff were quietly degraded this way and only a
fetch-back caught it. After writing any anchor into Notion, fetch the page back and
confirm the `#<32 hex chars>` fragment survived.
