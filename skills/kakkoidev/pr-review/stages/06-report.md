# Stage 06: Assemble report and seal

<!-- ICM-TOOLS expect="(Write)" -->
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
2. Write `output/report-receipt.md`: the report path, its line/finding counts, and a final line that is EXACTLY `VERIFIED: PASS` (report complete: verdict + 7-point + the PR-Template Checklist Audit section present whenever `../01-context/output/checklist.tsv` is non-empty + every CRITICAL/HIGH has file:line + Regression spec + a status with evidence) or `VERIFIED: FAIL` (with what is missing - a non-empty checklist.tsv with no audit section in the report is a FAIL).

## After Output (MANDATORY)
```bash
bash ~/.agents/skills/icm/runtime/icm.sh stage-done kakkoidev/pr-review --stage 06-report
bash ~/.agents/skills/icm/runtime/icm.sh seal kakkoidev/pr-review
```

## Outputs
| Artifact | Location | Format |
|----------|----------|--------|
| Review report | output/REVIEW-<PR#>.md | Verdict + rationale; 7-Point table (7 rows); PR-Template Checklist Audit table + Bias-alarm line (when a template checklist exists); Critical Issues (file:line, severity, blast-radius, fix, Regression, Mutation, status CONFIRMED/PLAUSIBLE/REFUTED + evidence); Findings by Category; Verification; Recommendations; Sources (clickable, walled-off noted); REGRESSION-SPEC-JSON block |
| Report receipt | output/report-receipt.md | Report path + counts; final line exactly `VERIFIED: PASS` / `VERIFIED: FAIL` |
