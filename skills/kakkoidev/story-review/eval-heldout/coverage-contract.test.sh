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

hits_line=$(grep -E '^Hits: [0-9]+/[0-9]+$' "$report" || true)
[ -n "$hits_line" ] || { echo "FAIL: no well-formed 'Hits: N/M' line in $report"; exit 1; }

for section in "## Matched" "## Missed" "## New candidates" "## Ambiguous overlap"; do
    grep -qF "$section" "$report" || { echo "FAIL: missing section '$section' in $report"; exit 1; }
done

echo "ok: $hits_line, all sections present"
