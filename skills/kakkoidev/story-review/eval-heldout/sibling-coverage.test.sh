#!/bin/sh
# Output-contract regression check, held out from the LLM grader.
#
# Mirrors pr-review's link-coverage guarantee: when a parent epic id was given,
# every candidate sibling story enumerated in epic-siblings.tsv (the complete,
# pre-judgment candidate set from stage 01 step 4a) MUST appear - fetched or
# explicitly skipped, never silently absent - in siblings-fetched.md (the
# post-judgment disposition file from step 4c). If epic-siblings.tsv doesn't
# exist, no parent epic was given this run and there is nothing to check (pass
# trivially, per the skill's stated optional-input design).
#
# Reads the produced run output via $ICM_RUN_DIR. Exit 0 = pass.
set -eu

[ -n "${ICM_RUN_DIR:-}" ] || { echo "FAIL: ICM_RUN_DIR not set (run via icm-improve held-out)"; exit 1; }

candidates="$ICM_RUN_DIR/01-gather/output/epic-siblings.tsv"
manifest="$ICM_RUN_DIR/01-gather/output/siblings-fetched.md"

if [ ! -f "$candidates" ]; then
    echo "ok: no epic-siblings.tsv (no parent epic id given this run) - nothing to check"
    exit 0
fi

[ -f "$manifest" ] || { echo "FAIL: epic-siblings.tsv exists but siblings-fetched.md is missing"; exit 1; }

missing=$(awk -F'\t' '{print $1}' "$candidates" | while IFS= read -r id; do
    [ -n "$id" ] || continue
    grep -Fq "$id" "$manifest" || printf '%s\n' "$id"
done)

if [ -n "$missing" ]; then
    echo "FAIL: sibling candidates not accounted for in siblings-fetched.md (silently dropped):"
    printf '%s\n' "$missing"
    exit 1
fi

n=$(awk -F'\t' 'END{print NR}' "$candidates")
echo "ok: all $n candidate sibling(s) accounted for in siblings-fetched.md"
