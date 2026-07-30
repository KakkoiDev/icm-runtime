#!/bin/sh
# Output-contract regression check, held out from the LLM grader.
#
# The skill's signature guarantee: stage 03 always produces a well-formed
# coverage-report.md with a numeric `Hits: N/M` line and all three sections
# present. This does NOT judge quality (the hit-count trend across icm-improve
# phases, read from results.md, is the real quality signal) - it only catches a
# prose edit that breaks the report's shape. Reads the produced run output via
# $ICM_RUN_DIR. Exit 0 = pass.
set -eu

[ -n "${ICM_RUN_DIR:-}" ] || { echo "FAIL: ICM_RUN_DIR not set (run via icm-improve held-out)"; exit 1; }

report="$ICM_RUN_DIR/03-score/output/coverage-report.md"
[ -f "$report" ] || { echo "FAIL: coverage-report.md not found at $report"; exit 1; }

# `Hits: n/a` is a legitimate, load-bearing outcome: the answer key is bound to one
# story, and score-coverage's target guard refuses to emit a number for any other.
# A guard that fired must still produce a well-formed report, hence both forms.
hits_line=$(grep -E '^Hits: ([0-9]+/[0-9]+|n/a)$' "$report" || true)
[ -n "$hits_line" ] || { echo "FAIL: no well-formed 'Hits: N/M' or 'Hits: n/a' line in $report"; exit 1; }

if [ "$hits_line" = "Hits: n/a" ]; then
    grep -qF '## Not applicable' "$report" || {
        echo "FAIL: 'Hits: n/a' without a '## Not applicable' block explaining the target mismatch"
        exit 1
    }
fi

for section in "## Matched" "## Missed" "## New candidates" "## Ambiguous overlap"; do
    grep -qF "$section" "$report" || { echo "FAIL: missing section '$section' in $report"; exit 1; }
done

# The grounding audit is the target-INDEPENDENT number, and the only quality signal
# a run on a non-source target has at all - so it must exist either way.
audit="$ICM_RUN_DIR/03-score/output/grounding-audit.md"
[ -f "$audit" ] || { echo "FAIL: grounding-audit.md not found at $audit (stage 03 step 2 skipped)"; exit 1; }
grep -qE '^Grounded: [0-9]+/[0-9]+$' "$audit" || {
    echo "FAIL: no well-formed 'Grounded: N/M' line in $audit"; exit 1; }
grep -qE '^Survival rate: ([0-9]+/[0-9]+|n/a)' "$audit" || {
    echo "FAIL: no well-formed 'Survival rate:' line in $audit"; exit 1; }
grep -qF '## Ungrounded findings' "$audit" || {
    echo "FAIL: missing '## Ungrounded findings' section in $audit"; exit 1; }

echo "ok: $hits_line, all sections present, grounding audit well-formed"
