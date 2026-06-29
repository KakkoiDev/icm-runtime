# Stage 03: Review (ported judgment)

<!-- ICM-TOOLS expect="(Read|Grep|Bash|Task)" -->
<!-- ICM-GATE tools="Write" run="test -s ../02-links/output/link-graph.md" -->

Run the code review against the gathered context and the resolved requirements.
The gate blocks writing findings until the link graph exists - the review must be
grounded in the followed links, not the diff alone. You are a reviewer in a bad
mood: assume the diff was written by a competitor that compiles and passes lint.

## Inputs
| Source | Location | Scope |
|--------|----------|-------|
| PR context | ../01-context/output/pr-context.md | summary, buckets, action feed |
| Link graph | ../02-links/output/link-graph.md | resolved tickets + authoritative requirements |
| Diff | `gh pr diff <pr#> --repo <owner/repo>` (read-only) | the change to review |
| Scars | references/scars.md | documented past failures (frozen this run) |

## Process
Read EVERY file in the diff end-to-end before judging (scars #9: a partial read is not a review).

1. **Depth by bucket** (from pr-context): prod = deep (full validation + adversarial); test = medium (does it lock correct behavior? scars #5); config = deep (insecure defaults, secrets); generated/lockfile/docs = shallow.
2. **Base review**: blind pass (read the diff cold, flag obvious security/perf/logic), then contextual pass (read TASK.md/CLAUDE.md/AC, check requirements traceability).
3. **Security / OWASP**: auth, crypto, input, SQL, user data. Spawn `owasp-security` (Task) for security-relevant diffs.
4. **Differential**: for large diffs (>=50 files or >=500 lines) spawn `differential-review` (Task).
5. **External-rule check (grounded in stage 02)**: for every hardcoded constant that encodes a domain rule (tax code list, rate, regex, limit, code list, date cutoff), verify it matches the authoritative requirement fetched in the link graph - NOT the PR's own tests (scars: self-consistent tests prove nothing). If the requirement was `walled-off` or absent, the constant is `Unverified external constant` (HIGH).
6. **Adversarial + blast radius**: per HIGH-RISK file, give 3 attack vectors (precondition, exploit, impact); for new public exports, grep callers and classify blast radius.
7. **Dead code + scope drift**: every added symbol has a consumer outside tests; every changed file serves the PR (scars: "for future callers" / "for consistency" / dead error handling are defects, not style).
8. **Scars check**: scan the diff for recurrence of any documented failure in references/scars.md; cite the scar by ticket id when one matches.
9. **Severity**: CRITICAL (data loss/auth bypass/RCE/payment/schema), HIGH (2 specialists same line, or 1 + reproducible vector, or unverified external constant), MEDIUM (1 specialist + file:line evidence), LOW (style only -> Recommendations, not blockers). No nits.

Write `output/findings.md`: a preliminary 7-point table (Requirements traceability, Dead code, Scope, Security/adversarial, Performance, Test coverage [filled in stage 04], Production readiness) and one entry per finding (file:line, severity, category, found-by, blast-radius, description, fix, and a Regression spec: seam + assertion + fails-on-revert). Findings are hypotheses (scars #7): every CRITICAL/HIGH cites the source line you read.

## After Output (MANDATORY)
```bash
bash ~/.agents/skills/icm/runtime/icm.sh stage-done kakkoidev/pr-review --stage 03-review
```

## Outputs
| Artifact | Location | Format |
|----------|----------|--------|
| Findings | output/findings.md | Preliminary 7-point table (7 rows, PASS/FAIL + note); per-finding blocks (file:line, severity, category, found-by, blast-radius, description, fix, Regression spec). External-rule findings cite the authoritative requirement from the link graph (or flag it unverified). Scar matches cite the scar id. |
