# Stage 05: Assemble report and seal

<!-- ICM-TOOLS expect="(Write)" -->
<!-- ICM-GATE tools="Write" run="test -s ../04-verify/output/verification.md" -->

Assemble the final review report in the ported `REVIEW.md` contract and a receipt
with a deterministic verdict line. The gate blocks writing until verification
exists, so the report always carries execution results. Then seal the run.

## Inputs
| Source | Location | Scope |
|--------|----------|-------|
| Findings | ../03-review/output/findings.md | findings + preliminary 7-point |
| Verification | ../04-verify/output/verification.md | suite + mutation + live |
| PR context | ../01-context/output/pr-context.md | scope, title, PR number (the index) |
| Link graph | ../02-links/output/link-graph.md | Sources to cite |

## Process
1. Write `output/REVIEW-<PR#>.md` (`<PR#>` from pr-context) in this structure:
   - `**Verdict**: SHIP | SHIP WITH FIXES | BLOCK` + one-line rationale.
   - Scope (N files, +M/-L), PR title + link, specialists run.
   - `## 7-Point Validation` table: all 7 rows (Requirements traceability, Dead code, Scope, Security, Performance, Test coverage [from stage 04 mutation], Production readiness) with PASS/FAIL + note. Points 1-6 FAIL block SHIP.
   - `## Critical Issues` (CRITICAL/HIGH/MEDIUM): each with file:line, severity, category, found-by, blast-radius, description, fix, Regression spec, Mutation result.
   - `## Findings by Category`, `## Verification` (suite/mutation/live), `## Recommendations` (LOW).
   - `## Sources`: one clickable `[label](url)` per resolved link from the link graph; note any `walled-off` requirement the review could not verify against.
   - A trailing `REGRESSION-SPEC-JSON` HTML comment block (per CRITICAL/HIGH: finding, file, seam, assertion, fails_on_revert).
2. Write `output/report-receipt.md`: the report path, its line/finding counts, and a final line that is EXACTLY `VERIFIED: PASS` (report complete: verdict + 7-point + every CRITICAL/HIGH has file:line + Regression spec) or `VERIFIED: FAIL` (with what is missing).

## After Output (MANDATORY)
```bash
bash ~/.agents/skills/icm/runtime/icm.sh stage-done kakkoidev/pr-review --stage 05-report
bash ~/.agents/skills/icm/runtime/icm.sh seal kakkoidev/pr-review
```

## Outputs
| Artifact | Location | Format |
|----------|----------|--------|
| Review report | output/REVIEW-<PR#>.md | Verdict + rationale; 7-Point table (7 rows); Critical Issues (file:line, severity, blast-radius, fix, Regression, Mutation); Findings by Category; Verification; Recommendations; Sources (clickable, walled-off noted); REGRESSION-SPEC-JSON block |
| Report receipt | output/report-receipt.md | Report path + counts; final line exactly `VERIFIED: PASS` / `VERIFIED: FAIL` |
