# Loop rules

Twelve rules. Every one of them is a real failure on a real PR, not a preference.
The reason is attached to each so a future reader can tell whether the rule still
applies, instead of deleting it as ceremony. Stages cite these as `R<n>`.

Source incidents: meetsone PRs **26203**, **26204**, **26205**, **26269**
(2026-08-25 .. 2026-09-08).

---

## R1 - A request comment without an `@claude` mention never fires

Post the next round's request with a literal `@claude` mention in the comment body,
then **verify a run actually started**. A posted comment is not a triggered review.

Verify, do not assume - `tools/verify-request-fired` records two independent signals:
1. the request comment body contains `@claude` (`mention=yes`), and
2. bot activity exists *after* the request timestamp - a new bot review/comment, or a
   started workflow run (`run_started=yes`).

`mention=no` or `run_started=no` means **the round did not happen**. Re-post with the
mention; never advance the round counter on an unfired request.

**Why:** on PR **26205** round 9 the request comment was posted without a mention and
sat unanswered - the loop looked like it was waiting on the bot when nothing had been
asked. PR **26204** had the same shape. The cost is silent: an unfired round is
indistinguishable from a slow one until you check.

---

## R2 - No round cap. Loop until a round comes back with nothing actionable

There is no "we have done enough rounds". The exit condition is a **quiet round**: a
round that produced zero actionable findings, on the current head (R9), with zero open
threads (R10). A round that produced a finding is not a quiet round, however small the
finding or however late the round.

**Why:** PR **26205** ran ten rounds. Round 9 - which a round cap of 3, 5 or 8 would
have skipped - caught a HIGH regression that the PR itself had introduced. Rounds are
cheap; a shipped regression is not.

---

## R3 - Findings are hypotheses, not orders

Read the source before agreeing with a finding. Two independent refusals exist and both
are legitimate:

- **the finding is wrong** - the behaviour it describes is not what the code does;
- **the finding is right and the proposed fix is wrong** - accepting the diagnosis does
  not oblige you to accept the prescription.

Every refusal is recorded in the ledger with its reason and repeated in the PR body, so
a human reviewer sees what was declined and why (see also R6 and R10).

**Why:** on PR **26205** the bot raised a real problem and proposed a fix that reused a
message whose instruction is wrong at depth 1. The refusal was settled with the bot's
*own stated criterion* - not with taste. Applying the proposed fix would have shipped a
new defect under the authority of a review.

---

## R4 - Every behavioural fix needs a test that fails on revert - proven both ways

For any fix that changes observable behaviour, run the new test in **both directions**:

- on the fix -> **passes**
- with the fix's source reverted (test kept) -> **fails**

`tools/check-revert-proof` runs both in a throwaway worktree and records the pair. A
test that passes in both directions asserts nothing and is worse than no test, because
it reads as coverage.

**The `toHaveBeenCalledWith` trap:** `expect(fn).toHaveBeenCalledWith(obj)` ignores keys
whose value is `undefined`, so an assertion about a key the fix *adds* passes on the
reverted code too. Use `toStrictEqual` on the captured argument (or
`expect(fn.mock.calls[0][0]).toStrictEqual({...})`) when the assertion is about a key's
presence.

**Why:** on PR **26203** an assertion added in an earlier round passed in both
directions for exactly this reason. It was recorded as a regression test for two rounds
before the two-direction run exposed it; `toStrictEqual` fixed it.

---

## R5 - The loop introduces its own regressions

Each round, re-check **the PR's own defect class**, not only the list the bot returned.
The fixes applied in rounds 1..n-1 are new, unreviewed code written under time pressure
from a review comment - they are exactly as likely to carry the PR's characteristic bug
as the original diff was.

Concretely: name the PR's defect class in stage 01 (what kind of mistake this change is
prone to - a missing guard, an unhandled depth, a wrong rounding, a lost tenant filter),
and re-run that specific check over the round's own diff before requesting the next round.

**Why:** the HIGH caught on PR **26205** round 9 was self-inflicted - introduced by an
earlier round's fix, not present in the original PR. The bot found it; the loop had not
been looking.

---

## R6 - Scope refusals get written down, not silently dropped

When a finding is real but fixing it would widen the PR beyond its ticket, follow the
procedure in `## Scope-refusal procedure` below. Never "note it mentally"; never widen
the PR to make a comment go away.

**Why:** an unrecorded scope refusal reads to the next human as an ignored review
comment, and to the next round's bot as an unaddressed finding it re-raises.

---

## R7 - Do not let a stale review round pass as current

Record the commit SHA **each round reviewed** and compare it to the PR head at that
moment. A review whose `commit_id` is not the current head reviewed code that no longer
exists; it is evidence about an old revision and must be labelled that way in the ledger
(`stale=yes`) and superseded by a fresh round, not counted as coverage of the current
code.

**Why:** on PR **26269** a review from two force-pushes earlier was reported as covering
the current code. Every conclusion drawn from it was about a revision nobody was going
to merge.

---

## R8 - Read CI honestly

Two failure modes, opposite directions, both real:

- **A green-looking wrapper hides a crashed step.** Never conclude "type-check passed"
  from grepping a log for an error count. A step that OOMs or is killed prints no errors
  and can leave the wrapper green. Read the per-step conclusion, and look for the crash
  markers (`FATAL ERROR`, `JavaScript heap out of memory`, `Killed`, exit code 137).
- **A red gate is not always real.** A quality-gate job can fail on a poll race while
  the underlying analysis passed with zero issues.

`tools/gather-ci` emits per-job/per-step conclusions and flags both shapes as
`# SUSPECT:` rows. Resolve every SUSPECT by reading the actual step, then state which
one it was: *real failure* or *infrastructure*. Never report a gate colour as a code fact.

**Why:** on PR **26203** a type-check OOM was grepped as zero errors and reported as
passing. On PR **26269** Sonar's own analysis passed with zero issues while the gate job
failed on a poll race, and the red was reported as a code problem.

---

## R9 - Any push requires a fresh round on the new head

Pushing a fix and declaring the loop done is a defect, not a shortcut. Every push
creates a head no bot has reviewed. The loop terminates only on a round whose
`reviewed_sha` equals the head at exit - so the last action of the loop is always a
**review**, never a **push**.

**Why:** it is the same error as R7 from the other end: R7 is an old review passed off
as current, R9 is new code passed off as reviewed. The fix pushed in the final round is
the least reviewed code in the PR and, per R5, the most likely to carry a new defect.

---

## R10 - Every bot thread is answered with its outcome and resolved as it is addressed

For each thread the bot opens: reply with what happened (`fixed in <sha>`,
`refused: <reason>`, `out of scope, tracked in <TICKET>`), then resolve the thread -
**at the time it is addressed**, not in a batch at the end.

**Why:** the human reviewer at the end of the loop is the point of the whole process
(the diagram's final node). Handing them a PR with dozens of open bot threads, each of
which may or may not have been dealt with, moves the triage work onto them and makes the
loop worse than no loop. An answered-and-resolved thread also stops the next round's bot
from re-raising the same item.

---

## R11 - Mark superseded bot rounds handled, but only after the loop converges

Three mechanisms, because GitHub gives the loop's three output shapes different affordances:

- **a review thread** is answered and then **resolved** (that is R10, done as each thread
  is addressed);
- **an issue comment** - the bot's round report - cannot be resolved, but it *can* be
  **collapsed**: GraphQL `minimizeComment` with `classifier: OUTDATED`
  (`tools/mark-superseded`);
- **our own review-request comment** - the loop's "@claude review, round N, head is X" -
  is also an issue comment, and it is collapsed the same way. **Extended by the captain's
  ruling of 2026-09-09:** unlike a bot report, a request comment carries nothing a human
  reviewer or a later round needs, so **every one is collapsed, including the last**.
  There is no "current" request comment to protect - the newest bot report is kept
  visible because it is the record of the loop's own findings; the newest request comment
  is not, it is only the machinery that asked for it. `tools/gather-requests` collects
  every `request_comment_id` written across all rounds and feeds them to the same
  `tools/mark-superseded`, unmodified - it already collapses anything the input TSV marks
  `superseded=yes`, so marking every request row `yes` (there is no "no" row) collapses
  all of them, last one included.

**The mechanism, proven and executed on PR 26204:** the mutation goes through the approved
wrapper at its `/graphql` path (`gh-axi api POST /graphql`) - the plain GitHub CLI route
for the same mutation is refused as a write. Every target goes in **one call, batched as
GraphQL aliases** (`m0:`, `m1:`, ...), so the whole cleanup costs the captain one approval
instead of one per comment.

**Ordering, and it is the whole rule:** cleanup happens **after the loop converges, never
during it**. While rounds are still coming, leave the earlier reports (and the round's own
request comment) expanded - that history is what the next round and the human actually
read. Once a round against the current head returns nothing actionable, collapse every
superseded bot report AND every request comment as the closing step. `ledger-audit --mode
converged` (the gate into 03-close) does not check collapsing; `--mode closed`, run at the
end of 03, checks both.

What stays visible, and what does not:

- **the final bot report stays visible** - it is the record that the loop converged, and
  it is the one the human needs;
- **the final request comment does NOT stay visible** - it is collapsed along with every
  earlier one. It is pure machinery and carries nothing the bot report doesn't already say;
- **a human's pending draft review is never touched.** `tools/mark-superseded` only ever
  minimizes issue comments authored by the given login, re-verified against the live PR; it
  cannot address a review, a thread, or anyone's unsubmitted draft.

The loop is not done while superseded rounds or request comments are still expanded.

**Why:** same reason as R10, one level up. A ten-round PR carries nine obsolete bot
reports. Left expanded they bury the current one, and the human reviewer - the entire
point of the process - has to work out which report is live before they can start. The
next round's bot reads them too. The same is true, doubled, for the request comments: a
ten-round PR also carries ten "@claude review" comments that said nothing but "go again" -
left expanded, they double the noise in the review space for zero information. PR 26204
is where both were collapsed together: seven bot reports and all seven request comments.

---

## R12 - A guard refusing one route is not proof the capability is missing

Before reporting a capability as unavailable or a step as blocked, try the **approved
wrapper**. A permission guard refuses a *route*, not a *capability*: the same operation
often goes through the sanctioned path with the approval the guard exists to ask for.

Concretely, for this loop: GitHub operations go through `gh-axi`, browser work through
ego-lite (the captain is logged in and it reuses that login). "The tool said no" is the
start of the check, not the end of it.

**Why:** R11's collapse step was nearly written off as impossible. The plain GitHub CLI
route for `minimizeComment` is refused as a write; the same mutation through
`gh-axi api POST /graphql` executed it on PR 26204. Had the first refusal been reported as
a blocker, a rule that is now proven and routine would have been dropped as unsupported.

---

## Scope-refusal procedure (R6)

When a finding is **real** but fixing it would widen the PR beyond its ticket:

1. **Do not widen the PR.** The ticket is the scope boundary; a review comment does not
   move it.
2. **Add a note to the PR description** stating that the item is deliberately out of
   scope, with the follow-up ticket to come.
3. **Say the same thing to the bot in the next round's reply**, in the thread, so the
   loop does not re-raise it (this is also the R10 reply for that thread).
4. **Create the follow-up ticket with the team's ticket-creator skill** (the one built
   under AILAB-379). Do not hand-create tickets - a hand-made ticket skips the fields and
   conventions the team's tooling enforces, and is the kind of ticket nobody triages.
5. **Add a reference back to that ticket in the PR description**, replacing the
   "ticket to come" placeholder from step 2 with the real ID.

The ledger row for the finding is `disposition=out-of-scope` with `ticket=<ID>` in its
reason; `tools/ledger-audit` fails the close gate if an `out-of-scope` row has no ticket
or the ticket never reached the PR body.

**Dependency, stated plainly:** the ticket-creator skill lives outside this runtime. If
it is not installed, step 4 **blocks** - stop and say so. Do not fall back to creating
the ticket by hand, and do not silently drop the follow-up: an out-of-scope refusal with
no ticket is an ignored finding with extra words.
