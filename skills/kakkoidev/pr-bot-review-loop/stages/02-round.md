# Stage 02: The loop (repeat until a round comes back with nothing actionable)

<!-- ICM-TOOLS expect="(Bash|Read|Edit|Write)" -->
<!-- ICM-GATE tools="Write" run="test -s ../01-preflight/output/preflight.md" -->

This stage is not one round. It is **the whole loop** - the cycle
`D -> E -> F -> CC -> D` in the diagram - and it is not finished until a round comes back
with nothing actionable, on the current head, with every thread dealt with.

**There is no round cap (R2).** PR 26205 ran ten rounds and round 9 caught a HIGH
regression the PR itself had introduced. A round that produced a finding is not a quiet
round, however small the finding or however tired you are of the PR.

**Do not close this stage between rounds.** ICM stages seal once; a closed stage cannot be
reopened and the audit flags duplicate closures. `stage-done` runs once, after convergence.

## Inputs
| Source | Location | Scope |
|--------|----------|-------|
| Preflight | ../01-preflight/output/preflight.md | bot login, mention handle, the PR's defect class, the base ref |
| Ledgers | ../01-preflight/output/rounds.tsv, ledger.tsv | copy both into this stage's `output/` on first entry; every round appends here |
| Rules | ~/.agents/skills/kakkoidev/pr-bot-review-loop/references/loop-rules.md | the twelve rules, cited below as R<n> |

## Process

Run steps 1-9 for round `n`, then step 10 decides whether there is a round `n+1`.
Everything below writes into this stage's `output/`.

### 1. Request the round - and verify it fired (R1)
Post a comment containing the **literal mention handle** (`@claude`). Say what changed
since the last round, and restate any refusal that still stands (this is also R6 step 3
and the R10 reply for those threads), so the bot does not re-raise settled items.

Then verify - a posted comment is not a triggered review:
```bash
bash ~/.agents/skills/kakkoidev/pr-bot-review-loop/tools/verify-request-fired \
  <owner>/<repo> <pr#> <n> output <bot-login> [<comment-id>]
```
- `UNFIRED(no-mention)` - the comment cannot have triggered anything. Re-post **with** the
  mention. Do **not** advance `n`, and do not write a rounds.tsv row: the round did not
  happen. This is exactly what stalled PR 26205 round 9 and PR 26204.
- `UNCONFIRMED(no-activity)` - the mention is there and nothing has come back yet. Wait and
  re-run the tool. Never record it as `FIRED`; `rounds.tsv` only ever gets `FIRED`.
- `FIRED` - proceed.

### 2. Harvest the round against the commit it actually reviewed (R7)
```bash
bash ~/.agents/skills/kakkoidev/pr-bot-review-loop/tools/gather-round \
  <owner>/<repo> <pr#> <n> output <bot-login>
```
Read `output/round-<n>.md`. If `stale=yes`, the bot reviewed a commit that is no longer
the head: record the round, do **not** triage it as coverage of the current code, and go
back to step 1 for a fresh round. On PR 26269 a review from two force-pushes earlier was
reported as covering the current code, and every conclusion drawn from it was about a
revision nobody was going to merge. `stale=unknown` means no bot review with a commit id
was found at all - treat it as step 1 not having fired, not as a quiet round.

### 3. Read CI honestly (R8)
```bash
bash ~/.agents/skills/kakkoidev/pr-bot-review-loop/tools/gather-ci \
  <owner>/<repo> <pr#> output <n> --logs
```
Resolve **every** `# SUSPECT:` row by reading the actual step, and record which it was:
- `GREEN-OVER-FAILED-STEP` - a green wrapper over a step that failed or crashed. Never
  conclude "type-check passed" by grepping a log for an error count; a step that OOMs
  prints no errors (PR 26203).
- `RED-GATE` - a failed gate whose underlying analysis may have passed. On PR 26269 Sonar
  reported zero issues while the gate job failed on a poll race.
State the verdict as *real failure* or *infrastructure*, with what you read. Never report
a gate colour as a fact about the code.

### 4. Triage every finding as a hypothesis (R3)
For each finding, **read the source before agreeing**. Then assign exactly one disposition
and write the ledger row (`round, finding_id, severity, disposition, reason, evidence`):

| Disposition | Means |
|-------------|-------|
| `fixed` | true, in scope, and fixed this round. Evidence must carry `PROVEN` (step 5) or an explicit `no-behaviour-change`. |
| `refused-finding-wrong` | the behaviour the finding describes is not what the code does. Reason states what the code actually does. |
| `refused-fix-wrong` | the finding is right and the **proposed fix** is wrong. Accepting a diagnosis does not oblige you to accept the prescription - on PR 26205 the bot's proposed fix reused a message whose instruction is wrong at depth 1, and the refusal was settled with the bot's own stated criterion. |
| `out-of-scope` | true, but fixing it widens the PR beyond its ticket. Follow the procedure below; reason must contain `ticket=<ID>`. |
| `duplicate` | already dispositioned in an earlier round. Reason names that round and finding id. |

Every refusal and every out-of-scope item is written into the PR description as well as
the ledger - `tools/ledger-audit` fails the close gate if a refusal or a ticket never
reached the PR body. A refusal that lives only in your head is an ignored review comment.

**Out-of-scope procedure (R6), all five steps, in order:**
1. Do not widen the PR. The ticket is the scope boundary; a review comment does not move it.
2. Add a note to the PR description that the item is deliberately out of scope, with the
   follow-up ticket to come.
3. Say the same in the thread, in the next round's reply, so the loop stops re-raising it.
4. Create the follow-up ticket **with the team's ticket-creator skill** (AILAB-379). Do
   not hand-create tickets. **If that skill is not installed here, this blocks** - stop and
   say so; do not fall back to a hand-made ticket and do not silently drop the follow-up.
   Before calling anything blocked, apply **R12**: a guard refusing one route is not proof
   the capability is missing - try the approved wrapper (`gh-axi` for GitHub, ego-lite for
   the browser) first. R11's collapse step was nearly written off on exactly that mistake.
5. Replace the placeholder in the PR description with the real ticket ID.

### 5. Fix, and prove the test both ways (R4)
Implement only what step 4 marked `fixed`. For each behavioural fix, write the regression
test and run it in both directions:
```bash
bash ~/.agents/skills/kakkoidev/pr-bot-review-loop/tools/check-revert-proof \
  --repo <abs-repo-root> --base <base-ref> \
  --test '<the test command>' --test-file <path/to/test> \
  --out output/revert-proof-<n>.tsv <path/to/changed/source>...
```
`PROVEN` (passes on the fix, fails on the revert) is the only result that counts.
`NOT-PROVEN(passes-on-revert)` means the test asserts nothing about this change - do not
record it as coverage. Watch for the `# TRAP:` rows: `toHaveBeenCalledWith` ignores keys
whose value is `undefined`, so an assertion about a key the fix *adds* passes on the
reverted code too. That is what happened on PR 26203; `toStrictEqual` on the captured
argument is the fix.

### 6. Re-check the PR's own defect class (R5)
Run the check named in preflight over **this round's own diff**, not just the bot's list.
The fixes from rounds 1..n-1 are new, unreviewed code written under pressure from a review
comment, and are exactly as likely to carry this PR's characteristic bug as the original
diff was. PR 26205's round-9 HIGH was self-inflicted. Record `defect_class_recheck=done`
in the round's row; a round that pushes without this is a FAIL in the audit.

### 7. Answer and resolve every thread, as each is addressed (R10)
Reply in the thread with the outcome - `fixed in <sha>`, `refused: <reason>`,
`out of scope, tracked in <TICKET>` - then resolve it. **At the time you address it**, not
in a batch at the end. The human reviewer at the end of this loop is the point of the
whole process; handing them a wall of open threads moves the triage onto them and makes
the loop worse than no loop.

Do **not** minimize the round's report here. Collapsing superseded reports is the closing
step (R11), performed in 03 after convergence: while rounds are still coming, that history
is what the next round and the human read.

### 8. Push
Push the round's fixes. Record `pushed_sha`. If nothing was fixed this round, record `-`.

### 9. Append the ledger
Append one row to `output/rounds.tsv` and one row per finding to `output/ledger.tsv`.
Refresh `output/pr-body.md` from the live PR description **after** you have updated it
with this round's refusals and tickets - the close gate reads that file, and a stale copy
would let a refusal that never reached GitHub pass as recorded.

### 10. Loop or converge (R2, R9)
The loop continues unless **all** of these hold for round `n`:
- `actionable = 0` - the round produced nothing to act on (R2);
- `pushed_sha = -` - nothing was pushed in this round. **A push always requires a fresh
  round on the new head (R9): pushing and declaring done is a defect**, because the code
  you just pushed is the least reviewed code in the PR and, per R5, the most likely to
  carry a new defect;
- `stale = no` - the round reviewed the current head (R7);
- `threads_open = 0` and `threads_unanswered = 0` (R10).

Otherwise `n = n + 1` and go back to step 1. There is no other exit.

On convergence, and only then:
```bash
bash ~/.agents/skills/kakkoidev/pr-bot-review-loop/tools/gather-round \
  --head-only <owner>/<repo> <pr#> output
bash ~/.agents/skills/kakkoidev/pr-bot-review-loop/tools/ledger-audit \
  --rounds output/rounds.tsv --ledger output/ledger.tsv --pr-body output/pr-body.md \
  --mode audit
```
Resolve every `FAIL` row before closing the stage. `--mode audit` is safe to run at any
point mid-loop, and running it each round is cheaper than discovering at round 9 that
round 2's ledger row was never written.

## After Output (MANDATORY)
```bash
bash ~/.agents/skills/icm/runtime/icm.sh stage-done kakkoidev/pr-bot-review-loop --stage 02-round
```

## Outputs
| Artifact | Location | Format |
|----------|----------|--------|
| Round record | output/round-\<n\>.md | Per round: the bot's review body and every thread comment verbatim, with the reviewed_sha / head_sha / stale header. One file per round; earlier rounds are never overwritten. |
| Round metrics | output/round-\<n\>.tsv | `gather-round` key/value: reviewed_sha, head_sha, stale, threads_total/open/unanswered, bot_comments_total/superseded/superseded_expanded. |
| Request proof | output/request-\<n\>.tsv | `verify-request-fired` key/value: mention, the three bot-activity signals, run_started, verdict. Only a `FIRED` verdict may produce a rounds.tsv row. |
| Threads | output/threads-\<n\>.tsv | `root_id, path, line, resolved, outdated, answered`. `unknown` resolution counts as open (fail-closed). |
| Bot reports | output/bot-comments-\<n\>.tsv | `id, created_at, minimized, superseded`. Input to 03's R11 cleanup; nothing is minimized in this stage. |
| CI read | output/ci-\<n\>.tsv | `gather-ci` rows plus every `# SUSPECT:` line, each resolved in the round record as *real failure* or *infrastructure*, with what was read. |
| Revert proofs | output/revert-proof-\<n\>.tsv | Per behavioural fix: base, test command, on_head, on_revert, verdict, plus any `# TRAP:` row. `PROVEN` is the only passing verdict. |
| Rounds ledger | output/rounds.tsv | One row per round that actually fired: round, request_verdict, reviewed_sha, head_sha, stale, findings, actionable, threads_open, threads_unanswered, pushed_sha, defect_class_recheck. |
| Findings ledger | output/ledger.tsv | One row per finding: round, finding_id, severity, disposition, reason, evidence. Every refusal and out-of-scope item also appears in the PR description. |
| PR body snapshot | output/pr-body.md | The live PR description as of the end of the last round, including the refusal ledger and the out-of-scope tickets. Read by the close gate. |
| Exit head | output/exit-head.tsv | `head_sha` + `observed_at`, written by `gather-round --head-only` at convergence. The close gate compares it to the last round's reviewed_sha (R9) without re-fetching. |
