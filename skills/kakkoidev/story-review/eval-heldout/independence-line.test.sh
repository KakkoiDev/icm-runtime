#!/bin/sh
# Output-contract regression check, held out from the LLM grader.
#
# The skill's signature guarantee against prior-run contamination: findings.md's
# FIRST LINE must be a well-formed Independence disclosure, and if prior-runs.tsv
# names ANY same_target=yes row, findings.md must NOT claim "fresh" - a false
# "fresh" claim is exactly the failure mode this whole isolation mechanism exists
# to make impossible to state by accident.
#
# Reads the produced run output via $ICM_RUN_DIR. Exit 0 = pass.
set -eu

[ -n "${ICM_RUN_DIR:-}" ] || { echo "FAIL: ICM_RUN_DIR not set (run via icm-improve held-out)"; exit 1; }

findings="$ICM_RUN_DIR/02-blind-review/output/findings.md"
prior="$ICM_RUN_DIR/01-gather/output/prior-runs.tsv"

[ -f "$findings" ] || { echo "FAIL: findings.md not found at $findings"; exit 1; }

first_line=$(head -n1 "$findings")
case "$first_line" in
    Independence:\ fresh\ *|Independence:\ re-review\ *) : ;;
    *) echo "FAIL: findings.md's first line is not a well-formed Independence disclosure: '$first_line'"; exit 1 ;;
esac

if [ -f "$prior" ] && awk -F'\t' 'NR>1 && $3=="yes"{found=1} END{exit !found}' "$prior"; then
    case "$first_line" in
        Independence:\ fresh\ *)
            echo "FAIL: prior-runs.tsv shows a same_target=yes row, but findings.md claims 'fresh'"
            exit 1
            ;;
    esac
fi

echo "ok: $first_line"
