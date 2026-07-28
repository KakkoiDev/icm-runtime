#!/bin/sh
# Output-contract regression check, held out from the LLM grader.
#
# The raw Hits: N/M line overstated real coverage in 7 of 7 runs on
# 2026-07-28 (see aidb SYNTHESIS-story-review-7-run-variance-study.md) -
# stage 03 now mandates a self-audit pass. This proves that pass actually
# happened and covered every matched row, not that its judgments are correct
# (that's a quality signal read from self-audit.md by a human, not a
# mechanical check this script can make).
# Reads the produced run output via $ICM_RUN_DIR. Exit 0 = pass.
set -eu

[ -n "${ICM_RUN_DIR:-}" ] || { echo "FAIL: ICM_RUN_DIR not set (run via icm-improve held-out)"; exit 1; }

report="$ICM_RUN_DIR/03-score/output/coverage-report.md"
audit="$ICM_RUN_DIR/03-score/output/self-audit.md"

[ -f "$report" ] || { echo "FAIL: coverage-report.md not found at $report"; exit 1; }
[ -f "$audit" ] || { echo "FAIL: self-audit.md not found at $audit - stage 03's mandatory self-audit step was skipped"; exit 1; }

grep -qE '^Corrected count: [0-9]+/[0-9]+$' "$audit" || {
    echo "FAIL: self-audit.md has no well-formed 'Corrected count: N/M' line"
    exit 1
}

# every T-id under coverage-report.md's ## Matched section must appear in self-audit.md
matched_tids=$(awk '/^## Matched$/{p=1; next} /^## /{p=0} p' "$report" | grep -oE '^- T[0-9]+' | grep -oE 'T[0-9]+' | sort -u)
missing=""
for tid in $matched_tids; do
    grep -qE "^- ${tid}: (GENUINE|COINCIDENTAL)" "$audit" || missing="$missing $tid"
done
[ -z "$missing" ] || { echo "FAIL: self-audit.md is missing a GENUINE/COINCIDENTAL line for:$missing"; exit 1; }

echo "ok: self-audit.md present, well-formed, covers every matched row"
