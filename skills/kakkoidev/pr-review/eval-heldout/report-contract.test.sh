#!/bin/sh
# Output-contract regression check, held out from the LLM grader.
#
# 06-report ## Outputs mandates a REVIEW-<PR#>.md with a verdict line and a
# 7-Point table, plus a report-receipt.md whose last non-empty line is exactly
# VERIFIED: PASS or VERIFIED: FAIL. Reads the produced run output via $ICM_RUN_DIR.
# Exit 0 = pass.
set -eu

[ -n "${ICM_RUN_DIR:-}" ] || { echo "FAIL: ICM_RUN_DIR not set"; exit 1; }

report=$(ls "$ICM_RUN_DIR"/06-report/output/REVIEW-*.md 2>/dev/null | head -1 || true)
[ -n "$report" ] && [ -f "$report" ] || { echo "FAIL: REVIEW-<PR#>.md not found under 06-report/output"; exit 1; }

grep -qiE '\*\*?Verdict\*?\*?:[[:space:]]*(SHIP|SHIP WITH FIXES|BLOCK)' "$report" \
    || { echo "FAIL: report missing a 'Verdict: SHIP|SHIP WITH FIXES|BLOCK' line"; exit 1; }
grep -qiE '7[- ]?Point' "$report" \
    || { echo "FAIL: report missing the 7-Point validation section"; exit 1; }

receipt=$(ls "$ICM_RUN_DIR"/06-report/output/report-receipt.md 2>/dev/null | head -1 || true)
[ -n "$receipt" ] && [ -f "$receipt" ] || { echo "FAIL: report-receipt.md not found"; exit 1; }
last=$(grep -v '^[[:space:]]*$' "$receipt" | tail -1)
case "$last" in
    "VERIFIED: PASS"|"VERIFIED: FAIL") echo "ok: report + receipt verdict ($last)" ;;
    *) echo "FAIL: receipt last line must be exactly 'VERIFIED: PASS' or 'VERIFIED: FAIL' (got: '$last')"; exit 1 ;;
esac
