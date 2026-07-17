#!/bin/sh
# Structural eval for pr-review: the 5 stages, their ICM-TOOLS declarations, the
# ordering gates, the deterministic tools, the frozen scars lens, and a ## Outputs
# table per stage (so icm-improve has expectations to grade). Runs from the skill
# dir. Exit 0 = pass.
set -eu

test -f SKILL.md || { echo "FAIL: SKILL.md missing"; exit 1; }
grep -q '^name: pr-review$' SKILL.md || { echo "FAIL: SKILL.md name frontmatter"; exit 1; }

STAGES="01-context 02-links 03-runtime-evidence 04-review 05-verify 06-report"
for s in $STAGES; do
    f="stages/$s.md"
    test -s "$f" || { echo "FAIL: $f missing or empty"; exit 1; }
    grep -q '<!-- ICM-TOOLS expect=' "$f" || { echo "FAIL: $f missing ICM-TOOLS"; exit 1; }
    grep -q '^## Outputs' "$f" || { echo "FAIL: $f missing ## Outputs"; exit 1; }
    grep -q "stage-done kakkoidev/pr-review --stage $s" "$f" || { echo "FAIL: $f missing its stage-done marker"; exit 1; }
done

# Ordering gates: each stage after 01 gates on the PRIOR stage's output existing.
# Grounding (03) precedes review (04): review gates on runtime-evidence, not the diff alone.
grep -q 'ICM-GATE .*run="test -s ../01-context/output/links.tsv"' stages/02-links.md || { echo "FAIL: 02 gate must require 01 links.tsv"; exit 1; }
grep -q 'ICM-GATE .*run="test -s ../02-links/output/link-graph.md"' stages/03-runtime-evidence.md || { echo "FAIL: 03 gate must require 02 link-graph.md"; exit 1; }
grep -q 'ICM-GATE .*run="checks/review-precondition.sh"' stages/04-review.md || { echo "FAIL: 04 gate must run checks/review-precondition.sh"; exit 1; }
# The checker subsumes the old inline 04 gate (03 grounding) and adds the diverged-state
# review-target decision (SOBA-285 #24370, review 4).
grep -q 'runtime-evidence.md' checks/review-precondition.sh || { echo "FAIL: review-precondition must still require 03 runtime-evidence.md"; exit 1; }
grep -q 'impact.md' checks/review-precondition.sh || { echo "FAIL: review-precondition must still require 03 impact.md (changed-value dual)"; exit 1; }
grep -q 'seal-decision' checks/review-precondition.sh || { echo "FAIL: review-precondition must enforce the seal-decision on divergence"; exit 1; }
grep -q 'ICM-GATE .*run="test -s ../04-review/output/findings.md"' stages/05-verify.md || { echo "FAIL: 05 gate must require 04 findings.md"; exit 1; }
grep -q 'ICM-GATE .*run="test -s ../05-verify/output/verification.md"' stages/06-report.md || { echo "FAIL: 06 gate must require 05 verification.md"; exit 1; }

# C1: the runtime-evidence stage runs the deterministic grounding tool.
grep -q 'gather-runtime-evidence' stages/03-runtime-evidence.md || { echo "FAIL: 03-runtime-evidence must invoke gather-runtime-evidence (C1)"; exit 1; }
# C-dual: the same stage runs the changed-value impact tool (dead-code's reverse direction).
grep -q 'gather-impact' stages/03-runtime-evidence.md || { echo "FAIL: 03-runtime-evidence must invoke gather-impact (changed-value dual)"; exit 1; }

# Deterministic tools present and executable.
for t in tools/gather-pr tools/fetch-web tools/gather-runtime-evidence tools/gather-impact tools/extract-checklist tools/build-review-comments tools/post-review; do
    test -x "$t" || { echo "FAIL: $t missing or not executable"; exit 1; }
done

# C-inline-review: 06 posts findings inline as a PENDING review, anchored deterministically
# and NEVER submitted. The line anchoring is a tool (snippet -> real RIGHT-side line, so a
# diff-offset vs source-line mixup cannot mis-post); the POST is pending-only.
grep -q 'build-review-comments' stages/06-report.md || { echo "FAIL: 06-report must invoke build-review-comments"; exit 1; }
grep -q 'post-review' stages/06-report.md || { echo "FAIL: 06-report must invoke post-review"; exit 1; }
grep -q 'NEVER SUBMITS' tools/post-review || { echo "FAIL: post-review must carry the NEVER-SUBMITS invariant"; exit 1; }
if grep -q 'submitPullRequestReview' tools/post-review; then echo "FAIL: post-review must never submit a review"; exit 1; fi
test -x eval/build-review-comments.test.sh || { echo "FAIL: eval/build-review-comments.test.sh missing or not executable"; exit 1; }
test -f eval/fixtures/review-comments/pr.diff || { echo "FAIL: review-comments fixture pr.diff missing"; exit 1; }
test -f eval/fixtures/review-comments/comments.ndjson || { echo "FAIL: review-comments fixture comments.ndjson missing"; exit 1; }

# C-inline-coverage (SOBA-103 #24618): 06 posts ONE inline comment per finding - a deletion-only
# finding anchors to the adjacent context line, a PR-wide finding to a representative line - and the
# receipt carries a `Findings coverage:` line accounting for every finding by id. The freeze that a
# review can no longer silently post 1 of 3 findings and drop the rest to the report body.
grep -qiE 'per finding' stages/06-report.md || { echo "FAIL: 06-report must mandate one inline comment per finding (#24618)"; exit 1; }
grep -qiE 'context line' stages/06-report.md || { echo "FAIL: 06-report must state anchors resolve context lines too (so deletion findings anchor to the adjacent context line)"; exit 1; }
grep -q 'Findings coverage:' stages/06-report.md || { echo "FAIL: 06-report must require the receipt 'Findings coverage:' reconciliation line"; exit 1; }
grep -qE 'F<n>' stages/04-review.md || { echo "FAIL: 04-review must mandate stable F<n> finding ids (used by the coverage line + freeze)"; exit 1; }
test -x eval-heldout/inline-comment-coverage.test.sh || { echo "FAIL: eval-heldout/inline-comment-coverage.test.sh missing or not executable (the #24618 coverage freeze)"; exit 1; }

# C-value-gate (SOBA-103 #24618 round 2): completeness alone regressed precision - forcing
# every finding inline posted true-but-noisy comments (pre-existing / out-of-scope / test-nag)
# that wasted the reviewer's time. Findings now carry a VALUE axis orthogonal to truth:
# 04 records the objective floor per finding, 05 runs the per-finding judgment pass to a final
# disposition, 06 posts inline ONLY the inline-disposition findings (report-only/dropped stay
# in the report, accounted for on the coverage line), and inline bodies are one concise sentence.
grep -q 'introduced-by-diff' stages/04-review.md || { echo "FAIL: 04-review must record the introduced-by-diff value field (#24618 round 2)"; exit 1; }
grep -q 'floor=' stages/04-review.md || { echo "FAIL: 04-review must record the objective floor (floor=pass|fail) per finding"; exit 1; }
grep -q 'NEVER demote' stages/04-review.md || { echo "FAIL: 04-review must state the asymmetric guardrail (never demote a diff-introduced correctness/security/data finding)"; exit 1; }
grep -q 'Disposition:' stages/05-verify.md || { echo "FAIL: 05-verify must resolve a final Disposition per finding (the value/judgment pass)"; exit 1; }
grep -qiE 'senior engineer' stages/05-verify.md || { echo "FAIL: 05-verify must carry the judgment-gate questions (would a senior engineer bother?)"; exit 1; }
grep -q 'report-only' stages/06-report.md || { echo "FAIL: 06-report must support the report-only disposition (low-value findings stay off the PR)"; exit 1; }
grep -qiE 'inline.-disposition' stages/06-report.md || { echo "FAIL: 06-report must post ndjson rows only for inline-disposition findings"; exit 1; }
grep -qiE 'ONE concise sentence' stages/06-report.md || { echo "FAIL: 06-report must mandate one-concise-sentence inline bodies (Ahmed's verbosity feedback)"; exit 1; }
test -x eval/inline-coverage-selftest.test.sh || { echo "FAIL: eval/inline-coverage-selftest.test.sh missing or not executable (proves the coverage check bites both directions)"; exit 1; }
# The floor is model-graded; 05 must cross-check the introduced-by-diff claims against
# the diff deterministically (a self-graded gate is prose, not enforcement).
test -x tools/check-value-claims || { echo "FAIL: tools/check-value-claims missing or not executable"; exit 1; }
grep -q 'check-value-claims' stages/05-verify.md || { echo "FAIL: 05-verify must run check-value-claims (self-graded floor cross-check)"; exit 1; }
test -x eval/check-value-claims.test.sh || { echo "FAIL: eval/check-value-claims.test.sh missing or not executable"; exit 1; }
# The feedback loop: posted-comment outcomes are harvested and logged, so gate precision
# is measured against ground truth instead of tuned per incident.
test -x tools/gather-review-feedback || { echo "FAIL: tools/gather-review-feedback missing or not executable"; exit 1; }
test -s references/calibration.md || { echo "FAIL: references/calibration.md missing (the value-gate ground-truth log)"; exit 1; }
grep -q 'gather-review-feedback' SKILL.md || { echo "FAIL: SKILL.md must document the feedback pass"; exit 1; }

# C0: gather-pr seals the diff (reproducible review artifact, not an ad-hoc re-fetch).
grep -q 'pr.diff' tools/gather-pr || { echo "FAIL: gather-pr must write output/pr.diff (C0)"; exit 1; }
# C-checklist: gather-pr extracts the PR-template checklist via the shared tool (no
# inline drift), so the checklist-audit lesson stays frozen by eval/.
grep -q 'extract-checklist' tools/gather-pr || { echo "FAIL: gather-pr must invoke extract-checklist"; exit 1; }
# C-provenance: gather-pr writes prior-runs + seal deterministically (the detection is
# a tool, not fragile stage prose - review 3 re-review had a cwd-trap false "fresh").
grep -q 'prior-runs.tsv' tools/gather-pr || { echo "FAIL: gather-pr must write prior-runs.tsv (deterministic re-review detection)"; exit 1; }
grep -q 'seal.tsv' tools/gather-pr || { echo "FAIL: gather-pr must write seal.tsv (reviewed-revision provenance)"; exit 1; }
grep -q 'dirty' tools/gather-pr || { echo "FAIL: gather-pr seal must include a dirty-tree check (diverged catches uncommitted edits, not just SHAs)"; exit 1; }
test -x eval/checklist-extraction.test.sh || { echo "FAIL: eval/checklist-extraction.test.sh missing or not executable"; exit 1; }
test -f eval/fixtures/checklist/body.md || { echo "FAIL: checklist fixture body.md missing"; exit 1; }
# C-diverged-gate: the diverged-state gate checker + its deterministic freeze.
test -x checks/review-precondition.sh || { echo "FAIL: checks/review-precondition.sh missing or not executable"; exit 1; }
test -x eval/review-precondition.test.sh || { echo "FAIL: eval/review-precondition.test.sh missing or not executable"; exit 1; }

# Scars lens frozen into the skill.
test -s references/scars.md || { echo "FAIL: references/scars.md missing"; exit 1; }

# Changed-value dual: the offline tool check + its frozen fixture present and runnable
# (in eval/ so `icm.sh eval` runs it - it is a deterministic tool check, not a graded contract).
test -x eval/changed-literal-impact.test.sh || { echo "FAIL: eval/changed-literal-impact.test.sh missing or not executable"; exit 1; }
test -f eval/fixtures/changed-literal/pr.diff || { echo "FAIL: changed-literal fixture diff missing"; exit 1; }
test -d eval/fixtures/changed-literal/repo || { echo "FAIL: changed-literal fixture repo missing"; exit 1; }

# No ICM-CALL: this skill's tool calls are not arg-verified, and a scraped
# ICM-CALL with no matching real call is a permanent audit deviation.
if grep -rq '<!-- ICM-CALL' stages/; then echo "FAIL: unexpected ICM-CALL (no arg-verified call in this skill)"; exit 1; fi

echo ok
