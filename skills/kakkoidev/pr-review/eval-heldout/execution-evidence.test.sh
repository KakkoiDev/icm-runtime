#!/bin/sh
# Output-contract regression check, held out from the LLM grader.
#
# Weakness #3 (iteration 11, #24126): a report asserted its top finding while the
# load-bearing assumption beneath it was never executed - the structure looked complete.
# This is the deterministic FLOOR that maps to that failure (per-finding rigor is enforced
# by stage prose + the LLM; this check catches the silent-confirmation SHAPE):
#   - if the report carries CRITICAL/HIGH findings, it MUST use the status vocabulary
#     (CONFIRMED / PLAUSIBLE / REFUTED) - an unexamined assumption can no longer read as
#     a bare blocker with no status;
#   - any CONFIRMED finding requires SOME evidence token present in the report: a source
#     citation (file:line) OR an execution token (runtime-evidence / verification reference).
#     Reading source IS evidence, so this never false-fails a genuinely grounded report
#     (the contract fix - it does not demand a command was run).
# Reads the produced run output via $ICM_RUN_DIR. Exit 0 = pass.
set -eu

[ -n "${ICM_RUN_DIR:-}" ] || { echo "FAIL: ICM_RUN_DIR not set"; exit 1; }

report=$(ls "$ICM_RUN_DIR"/06-report/output/REVIEW-*.md 2>/dev/null | head -1 || true)
[ -n "$report" ] && [ -f "$report" ] || { echo "FAIL: REVIEW-<PR#>.md not found under 06-report/output"; exit 1; }

# Status discipline: only required when there are blocker-class findings (uppercase
# severity labels; prose "high" is lowercase and does not trigger this).
if grep -qE '(CRITICAL|HIGH)' "$report"; then
    grep -qE '(CONFIRMED|PLAUSIBLE|REFUTED)' "$report" \
        || { echo "FAIL: report has CRITICAL/HIGH findings but no CONFIRMED/PLAUSIBLE/REFUTED status - an assumption can read as a bare blocker"; exit 1; }
fi

# Evidence floor: a CONFIRMED finding requires some evidence token present in the report -
# a file:line citation OR a runtime-evidence/verification reference.
if grep -q 'CONFIRMED' "$report"; then
    if grep -qE '[A-Za-z0-9_./-]+:[0-9]+' "$report" || grep -qiE 'runtime-evidence|verification' "$report"; then
        :
    else
        echo "FAIL: report asserts CONFIRMED but carries no evidence token (no file:line citation, no runtime-evidence/verification reference)"
        exit 1
    fi
fi

echo "ok: execution-evidence contract (status discipline + evidence floor)"
