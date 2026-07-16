# Stage 06: Assemble report and seal

<!-- ICM-TOOLS expect="(Write|Bash)" -->
<!-- ICM-GATE tools="Write" run="test -s ../05-verify/output/verification.md" -->

Assemble the final review report in the ported `REVIEW.md` contract and a receipt
with a deterministic verdict line. The gate blocks writing until verification
exists, so the report always carries execution results. Then seal the run.

## Inputs
| Source | Location | Scope |
|--------|----------|-------|
| Findings | ../04-review/output/findings.md | findings + preliminary 7-point + statuses |
| Checklist audit | ../04-review/output/checklist-audit.md | per-item verdicts (MET/GAP/N-A, verified/asserted) |
| Verification | ../05-verify/output/verification.md | suite + mutation + live + adversarial + checklist-exercise verdicts |
| PR context | ../01-context/output/pr-context.md | scope, title, PR number (the index) |
| Prior runs | ../01-context/output/prior-runs.tsv | prior same-PR reviews - drives the Independence header line |
| Seal | ../01-context/output/seal.tsv | pr_head_sha / local_head_sha / diverged - drives the reviewed-revision disclosure |
| Link graph | ../02-links/output/link-graph.md | Sources to cite |

## Process
1. Write `output/REVIEW-<PR#>.md` (`<PR#>` from pr-context) in this structure:
   - `**Verdict**: SHIP | SHIP WITH FIXES | BLOCK` + one-line rationale.
   - Scope (N files, +M/-L), PR title + link, specialists run.
   - `Independence:` line from `../01-context/output/prior-runs.tsv` - `fresh` if empty, else `re-review (N prior same-PR runs; prior review read: yes/no)`. If a predecessor review was read, this run's findings are not fully independent of it - say so plainly. Do NOT claim `fresh` if `prior-runs.tsv` is non-empty; the report-contract cross-checks the on-disk prior reviews and FAILS a false `fresh`.
   - `Reviewed revision:` line from `../01-context/output/seal.tsv` + `seal-decision.tsv` - the sealed `pr.diff` is `pr_head_sha`. If `diverged=yes`, state the local `local_head_sha` differs (different commit and/or dirty tree) and name the recorded decision: `target=sealed` (reviewed the PR; divergence is one finding; local reads tagged `OUT-OF-SEAL` per 04) or `target=working-tree` (human_approved) - in which case say up front the ENTIRE review is non-reproducible/out-of-seal. Never present a working-tree review as the PR. If `diverged=no`, `Reviewed revision: <pr_head_sha> (PR head == local)`.
   - `## 7-Point Validation` table: all 7 rows (Requirements traceability, Dead code, Scope, Security, Performance, Test coverage [from stage 05 mutation], Production readiness) with PASS/FAIL + note. Points 1-6 FAIL block SHIP.
   - `## PR-Template Checklist Audit` (when `checklist-audit.md` is non-empty): the per-item table from stage 04 folded with stage 05's exercise results - `item | mandated | author-tick | verdict (MET/GAP/N-A) | method (verified/asserted->now exercised) | basis`. Then the **Bias alarm** line (did gaps land only on the scannable items or a primed hint?). Any `GAP` here is a finding in Critical Issues at its severity; the author's tick state is reported as a claim, and the section states plainly that ticking the boxes is the human's to do - the audit gives them grounded evidence, it does not tick for them. If the repo has no template checklist, state that in one line.
   - `## Critical Issues` (CRITICAL/HIGH/MEDIUM): each with file:line, severity, category, found-by, blast-radius, description, fix, Regression spec, Mutation result, AND its **status** (`CONFIRMED` / `PLAUSIBLE` / `REFUTED` from stage 05) with the evidence (source citation or execution token) that settled it. A finding not reproducible from the sealed `pr.diff` (only from a diverged local file) MUST carry an `OUT-OF-SEAL` tag naming where it lives (per 04) - do not report it as a plain diff finding. A finding asserted CONFIRMED with no evidence token is a contract violation - carry the evidence or downgrade it. A load-bearing assumption that could not be executed is reported `UNVERIFIED: <why>`, never silently as confirmed.
   - `## Findings by Category`, `## Verification` (suite/mutation/live/adversarial verdicts), `## Recommendations` (LOW).
   - `## Sources`: one clickable `[label](url)` per resolved link from the link graph; note any `walled-off` requirement the review could not verify against.
   - A trailing `REGRESSION-SPEC-JSON` HTML comment block (per CRITICAL/HIGH: finding, file, seam, assertion, fails_on_revert).
2. **Post the findings inline on the PR as a PENDING draft review (automatic; NEVER submitted).**
   The report is the record; this puts each finding on the exact line it is about, as a draft a
   human then submits. Determinism split: the line anchoring + payload is a tool; the POST is a
   gated pending-only write (never a submit).

   **Coverage rule - one inline comment PER FINDING.** EVERY finding in `findings.md` gets its own
   ndjson row: every Critical Issue (CRITICAL/HIGH/MEDIUM) AND every LOW recommendation. Posting a
   finding inline does NOT make it a blocker - the severity tag in the body carries that - so there
   is no reason to demote a finding to the summary body. Do NOT drop a finding to body-only because
   it "has no added line": `build-review-comments` anchors ADDED **or context** lines (both carry a
   RIGHT-side new-file number and are commentable), so almost every finding has a home. Recipes for
   the two shapes that fooled an earlier run (SOBA-103 #24618 - only 1 of 3 findings got posted):
   - **Deletion-only finding** (the PR REMOVED the offending code, so there is no added line):
     anchor to the nearest unchanged **context** line adjacent to the removed code, and say in the
     body "the removed `X` was on the line above." A pure deletion still gets an inline comment.
   - **PR-wide finding** (no single line, e.g. "no test covers this change"): anchor to the most
     representative changed line and prefix the body `(PR-wide)`.
   - Only a finding with NO reachable line anywhere in the diff stays body-only, and then step 3's
     receipt MUST record it as `F<n>:body-only(<reason>)`. "It felt like a summary point" is not a
     reason; "no code locus in the diff" is.
   a. Write `output/review-comments.ndjson` - one JSON object PER FINDING:
      `{"path","snippet","severity","body"}`. **`snippet` MUST be copied verbatim from an ADDED or
      CONTEXT line of `../01-context/output/pr.diff` for that file** (a `+` added line or a ` `
      context line - both are commentable; a `-` deleted line is NOT, so anchor its finding to the
      adjacent context line). Quote the code; the tool resolves it to the real RIGHT-side line. Do
      NOT hand-compute line numbers (a diff-offset vs source line mixup is the exact miss this
      design removes). `body` = the finding id + severity + the one-line problem + the fix, leading
      with `**F<n> - <SEV> - <category>.**` so the draft, the report, and the receipt cross-reference
      the same id. Also write `output/review-summary.md` (verdict + one line per finding) for the
      review body.
   b. Build the anchored payload (deterministic - validates every anchor against the sealed diff):
      ```bash
      bash ~/.agents/skills/kakkoidev/pr-review/tools/build-review-comments \
        ../01-context/output/pr.diff output/review-comments.ndjson output
      ```
      Then READ `output/unanchored.tsv`: any row there did NOT anchor (snippet absent or
      ambiguous in the diff). Fix its `snippet` (try a neighbouring context line) and rebuild, or
      record it body-only in the receipt - never leave a finding silently unposted.
      **Reconcile before posting.** Every finding in `findings.md` MUST now be exactly one of:
      (i) anchored in `review-comments.json`, (ii) surfaced in `unanchored.tsv`, or (iii)
      recorded body-only with a reason (step 3). A finding that is none of these is the miss this
      rule exists to stop - author its row and rebuild until the count of anchored comments plus
      body-only plus unanchored equals the number of findings.
   c. Post as a PENDING review (create-or-append, NEVER submit):
      ```bash
      bash ~/.agents/skills/kakkoidev/pr-review/tools/post-review <owner>/<repo> <PR#> \
        output/review-comments.json --body-file output/review-summary.md
      ```
      `post-review` creates a draft review, or appends to a pending review the human already
      started (no 422, no clobber), and passes NO `event` so nothing is published until a human
      submits in the GitHub UI. If it fails (no write scope / offline), record the error and
      continue - the sealed report is the primary artifact, posting is a convenience.
3. Write `output/report-receipt.md`: the report path, its line/finding counts, the inline-post
   result (`created`/`appended`/`skipped`/`failed` + anchored/unanchored counts), a **`Findings
   coverage:`** line that accounts for EVERY finding by id and disposition - one space-separated
   token per finding in the form `F<n>:inline` | `F<n>:unanchored` | `F<n>:body-only(<reason>)`
   (e.g. `Findings coverage: F1:inline F2:inline F3:body-only(no code locus - PR-wide test gap)`).
   The count of `:inline` tokens MUST equal the number of comments in `review-comments.json`, every
   `body-only` MUST carry a non-empty reason, and every `F<n>` id in `findings.md` MUST appear on
   this line. Then a final line that is EXACTLY `VERIFIED: PASS` (report complete: verdict + 7-point
   + the PR-Template Checklist Audit section present whenever `../01-context/output/checklist.tsv`
   is non-empty + every CRITICAL/HIGH has file:line + Regression spec + a status with evidence +
   every finding in `findings.md` accounted for on the `Findings coverage:` line) or `VERIFIED:
   FAIL` (with what is missing - a non-empty checklist.tsv with no audit section, OR a finding not
   accounted for on the coverage line, is a FAIL). The inline-post *outcome* (created/appended vs a
   network/scope failure) is recorded but does NOT gate the verdict; coverage completeness DOES -
   a post that silently omits a finding is the failure this closes.

## After Output (MANDATORY)
```bash
bash ~/.agents/skills/icm/runtime/icm.sh stage-done kakkoidev/pr-review --stage 06-report
bash ~/.agents/skills/icm/runtime/icm.sh seal kakkoidev/pr-review
```

## Outputs
| Artifact | Location | Format |
|----------|----------|--------|
| Review report | output/REVIEW-<PR#>.md | Verdict + rationale; 7-Point table (7 rows); PR-Template Checklist Audit table + Bias-alarm line (when a template checklist exists); Critical Issues (file:line, severity, blast-radius, fix, Regression, Mutation, status CONFIRMED/PLAUSIBLE/REFUTED + evidence); Findings by Category; Verification; Recommendations; Sources (clickable, walled-off noted); REGRESSION-SPEC-JSON block |
| Inline-comment source | output/review-comments.ndjson | One JSON object PER FINDING in findings.md (every Critical Issue + every LOW): `{path, snippet (verbatim from an added OR context pr.diff line), severity, body}`. Deletion-only findings anchor to the adjacent context line; PR-wide findings to a representative line with a `(PR-wide)` body prefix. Model-authored; the anchor is a quoted snippet, never a hand-computed line. |
| Review summary | output/review-summary.md | Verdict + one line per finding; used as the pending review's body on create. |
| Anchored payload | output/review-comments.json | Deterministic `tools/build-review-comments` output: JSON array of `{path, line, side:RIGHT, body}`, each line resolved from its snippet against `pr.diff`. |
| Unanchored | output/unanchored.tsv | `path<TAB>reason<TAB>snippet` for every comment that did NOT anchor (snippet absent/ambiguous). Must be surfaced or fixed - never a silent drop. |
| Report receipt | output/report-receipt.md | Report path + counts + inline-post result (created/appended/skipped/failed, anchored/unanchored); a `Findings coverage:` line accounting for every finding by id (`F<n>:inline` / `F<n>:unanchored` / `F<n>:body-only(<reason>)`, `:inline` count == comments in review-comments.json); final line exactly `VERIFIED: PASS` / `VERIFIED: FAIL` |
