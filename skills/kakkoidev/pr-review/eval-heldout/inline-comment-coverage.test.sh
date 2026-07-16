#!/bin/sh
# Output-contract regression check, held out from the LLM grader.
#
# The miss this freezes (SOBA-103 #24618, 2026-07-16): a review produced 3 findings
# (F1/F2/F3) but posted only 1 inline comment - the deletion-only finding (F1) and the
# PR-wide finding (F3) were quietly demoted to the report body, and nothing signalled
# that 2 of 3 findings never made it onto the diff. 06-report now mandates one inline
# comment PER FINDING (deletion -> adjacent context line; PR-wide -> representative line)
# and a `Findings coverage:` receipt line that accounts for every finding by id. This
# check enforces that contract against the produced run via $ICM_RUN_DIR. Exit 0 = pass.
set -eu

[ -n "${ICM_RUN_DIR:-}" ] || { echo "FAIL: ICM_RUN_DIR not set"; exit 1; }
command -v jq >/dev/null 2>&1 || { echo "FAIL: jq not found"; exit 1; }

out="$ICM_RUN_DIR/06-report/output"
ndjson="$out/review-comments.ndjson"
json="$out/review-comments.json"
receipt="$out/report-receipt.md"
findings="$ICM_RUN_DIR/04-review/output/findings.md"

# Only applies when inline posting was in play: an ndjson with >=1 authored row.
if [ ! -s "$ndjson" ] || ! grep -q '[^[:space:]]' "$ndjson"; then
    echo "ok: no authored inline comments (review-comments.ndjson empty/absent) - nothing to reconcile"
    exit 0
fi

# 1. The receipt must carry the findings->comment reconciliation line.
[ -f "$receipt" ] || { echo "FAIL: report-receipt.md missing"; exit 1; }
cov=$(grep -iE 'Findings coverage:' "$receipt" | head -1 || true)
[ -n "$cov" ] \
    || { echo "FAIL: receipt has no 'Findings coverage:' line (inline-comment coverage freeze, #24618)"; exit 1; }

# 2. Claimed inline count == comments actually anchored in review-comments.json.
[ -s "$json" ] || { echo "FAIL: review-comments.ndjson has rows but review-comments.json is missing/empty (build-review-comments not run)"; exit 1; }
json_len=$(jq 'length' "$json" 2>/dev/null || echo -1)
inline_claimed=$(printf '%s' "$cov" | grep -oE 'F[0-9]+:inline' | wc -l | tr -d ' ')
[ "$inline_claimed" = "$json_len" ] \
    || { echo "FAIL: coverage claims $inline_claimed inline comment(s) but review-comments.json has $json_len (a dropped/over-claimed finding)"; exit 1; }

# 3. Every body-only disposition must carry a non-empty reason: F<n>:body-only(<reason>).
bo_total=$(printf '%s' "$cov" | grep -oE 'F[0-9]+:body-only' | wc -l | tr -d ' ')
bo_reason=$(printf '%s' "$cov" | grep -oE 'F[0-9]+:body-only\([^)]+\)' | wc -l | tr -d ' ')
[ "$bo_total" = "$bo_reason" ] \
    || { echo "FAIL: a 'body-only' disposition is missing its (reason) - $bo_total body-only, $bo_reason with a reason"; exit 1; }

# 4. Completeness: every finding id in findings.md is accounted for on the coverage line.
if [ -f "$findings" ]; then
    fids=$(grep -oE 'F[0-9]+' "$findings" | sort -u || true)
    cids=$(printf '%s' "$cov" | grep -oE 'F[0-9]+' | sort -u || true)
    missing=""
    for id in $fids; do
        printf '%s\n' "$cids" | grep -qx "$id" || missing="$missing $id"
    done
    [ -z "$missing" ] \
        || { echo "FAIL: finding(s) in findings.md absent from the coverage line:$missing"; exit 1; }
fi

echo "ok: inline-comment coverage ($json_len anchored, all findings accounted for)"
