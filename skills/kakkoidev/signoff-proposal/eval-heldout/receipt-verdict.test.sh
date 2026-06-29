#!/bin/sh
# Output-contract regression check, held out from the LLM grader.
#
# 03-publish ## Outputs (stages/03-publish.md) mandates that the produced
# output/publish-receipt.md ends with a final line that is EXACTLY
# `VERIFIED: PASS` or `VERIFIED: FAIL`. The grader scores proposal CONTENT
# (diagram, table, linked sources), not this receipt format, so an editable
# Process-prose change that drops or garbles the verdict step can raise the
# grader's pass_rate while silently breaking this contract. This check reads the
# PRODUCED run output via $ICM_RUN_DIR and fails when the verdict line is gone.
#
# Run by `icm-improve.sh held-out <run-dir> <phase-dir> <tests-dir>`, which
# exports ICM_RUN_DIR to the produced run dir. Exit 0 = pass.
set -eu

[ -n "${ICM_RUN_DIR:-}" ] || { echo "FAIL: ICM_RUN_DIR not set (run via icm-improve.sh held-out)"; exit 1; }

receipt=$(ls "$ICM_RUN_DIR"/[0-9]*/output/publish-receipt.md 2>/dev/null | head -1 || true)
[ -n "$receipt" ] && [ -f "$receipt" ] || { echo "FAIL: publish-receipt.md not found under run output"; exit 1; }

last=$(grep -v '^[[:space:]]*$' "$receipt" | tail -1)
case "$last" in
    "VERIFIED: PASS"|"VERIFIED: FAIL") echo "ok: receipt verdict line present ($last)" ;;
    *) echo "FAIL: receipt last line must be exactly 'VERIFIED: PASS' or 'VERIFIED: FAIL' (got: '$last')"; exit 1 ;;
esac
