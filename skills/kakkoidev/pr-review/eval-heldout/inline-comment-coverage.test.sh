#!/bin/sh
# Output-contract regression check, held out from the LLM grader.
#
# Two misses frozen here, both from SOBA-103 #24618 (2026-07-16) - completeness AND
# precision, a paired contract:
# - Round 1 (completeness): 3 findings, but only 1 inline comment - the REAL finding (a
#   deletion-only one) and the PR-wide one were quietly demoted to the report body. The
#   coverage line + completeness assertions stop the silent drop.
# - Round 2 (precision): after the round-1 fix forced EVERY finding inline, the reviewer
#   (Ahmed) pushed back: 2 of 3 posted comments were TRUE but not worth his time
#   (pre-existing / out-of-scope / test-nag). Findings now carry a Value line with an
#   objective floor (floor=pass|fail); only floor-passing findings may post inline, and
#   floor-passing findings MUST post (or be dropped-with-reason) - the filter may not
#   suppress a diff-introduced defect.
# Dispositions: F<n>:inline | F<n>:body-only(<reason>) | F<n>:report-only(<reason>) |
# F<n>:dropped(<reason>). Enforced against the produced run via $ICM_RUN_DIR. Exit 0 = pass.
set -eu

[ -n "${ICM_RUN_DIR:-}" ] || { echo "FAIL: ICM_RUN_DIR not set"; exit 1; }
command -v jq >/dev/null 2>&1 || { echo "FAIL: jq not found"; exit 1; }

out="$ICM_RUN_DIR/06-report/output"
ndjson="$out/review-comments.ndjson"
json="$out/review-comments.json"
receipt="$out/report-receipt.md"
findings="$ICM_RUN_DIR/04-review/output/findings.md"

fids=""
[ -f "$findings" ] && fids=$(grep -oE 'F[0-9]+' "$findings" | sort -u || true)

# Applies when the run produced findings OR authored inline comments. A run with
# findings but an empty ndjson is NOT exempt - an over-aggressive filter that demotes
# everything to report-only must still reconcile against the coverage line.
if [ -z "$fids" ] && { [ ! -s "$ndjson" ] || ! grep -q '[^[:space:]]' "$ndjson"; }; then
    echo "ok: no findings and no authored inline comments - nothing to reconcile"
    exit 0
fi

# 1. The receipt must carry the findings->disposition reconciliation line.
[ -f "$receipt" ] || { echo "FAIL: report-receipt.md missing"; exit 1; }
cov=$(grep -iE 'Findings coverage:' "$receipt" | head -1 || true)
[ -n "$cov" ] \
    || { echo "FAIL: receipt has no 'Findings coverage:' line (inline-comment coverage freeze, #24618)"; exit 1; }

# 2. Claimed inline count == comments actually anchored in review-comments.json.
inline_claimed=$(printf '%s' "$cov" | grep -oE 'F[0-9]+:inline' | wc -l | tr -d ' ')
json_len=0
if [ -s "$json" ]; then
    json_len=$(jq 'length' "$json" 2>/dev/null || echo -1)
elif [ "$inline_claimed" != 0 ]; then
    echo "FAIL: coverage claims $inline_claimed inline comment(s) but review-comments.json is missing/empty (build-review-comments not run)"; exit 1
fi
[ "$inline_claimed" = "$json_len" ] \
    || { echo "FAIL: coverage claims $inline_claimed inline comment(s) but review-comments.json has $json_len (a dropped/over-claimed finding)"; exit 1; }

# 3. Per-finding disposition tokens: every F<n> in findings.md appears on the coverage
#    line with a well-formed token; body-only/report-only/dropped carry a non-empty reason.
for id in $fids; do
    tok=$(printf '%s' "$cov" | grep -oE "$id:(inline|body-only\([^)]+\)|report-only\([^)]+\)|dropped\([^)]+\))" | head -1 || true)
    if [ -z "$tok" ]; then
        if printf '%s' "$cov" | grep -qE "$id:"; then
            echo "FAIL: $id has a malformed disposition token (allowed: inline | body-only(<reason>) | report-only(<reason>) | dropped(<reason>), reason non-empty)"; exit 1
        fi
        echo "FAIL: finding $id in findings.md absent from the coverage line"; exit 1
    fi
done

# 4. The value gate ran: every finding carries a Value line with floor=pass|fail (#24618
#    round 2). A findings.md without them means the noise gate was skipped entirely.
if [ -n "$fids" ]; then
    pairs=$(awk '
        { while (match($0, /F[0-9]+/)) { cur = substr($0, RSTART, RLENGTH); $0 = substr($0, RSTART + RLENGTH) } }
        /floor=(pass|fail)/ { if (cur != "") { f = ($0 ~ /floor=pass/) ? "pass" : "fail"; print cur, f } }
    ' "$findings" | sort -u)
    [ -n "$pairs" ] \
        || { echo "FAIL: findings.md has findings but no 'Value: ... floor=pass|fail' lines (the value gate was skipped, #24618)"; exit 1; }
    for id in $fids; do
        floor=$(printf '%s\n' "$pairs" | awk -v id="$id" '$1==id{print $2; exit}')
        [ -n "$floor" ] || { echo "FAIL: finding $id has no Value line with floor=pass|fail"; exit 1; }
        tok=$(printf '%s' "$cov" | grep -oE "$id:(inline|body-only|report-only|dropped)" | head -1)
        disp=${tok#"$id":}
        # Precision: a floor-failing finding (pre-existing / out-of-scope / not
        # merge-changing) must never reach the PR.
        if [ "$floor" = fail ] && { [ "$disp" = inline ] || [ "$disp" = body-only ]; }; then
            echo "FAIL: $id has floor=fail but disposition '$disp' - a low-value finding was posted to the PR (precision, #24618 round 2)"; exit 1
        fi
        # Anti-over-filtering: a floor-passing finding (diff-introduced, merge-relevant)
        # must post (or be dropped with a reason as wrong/vacuous) - never demoted to
        # report-only.
        if [ "$floor" = pass ] && [ "$disp" = report-only ]; then
            echo "FAIL: $id has floor=pass but disposition 'report-only' - a diff-introduced merge-relevant finding was suppressed (the filter over-corrected)"; exit 1
        fi
    done
fi

# 5. The self-graded floor was cross-checked: value-claims.tsv exists and carries no
#    unresolved SUSPECT (a floor=pass claim no diff-touched file grounds).
if [ -n "$fids" ]; then
    vc="$ICM_RUN_DIR/05-verify/output/value-claims.tsv"
    [ -f "$vc" ] \
        || { echo "FAIL: 05-verify/output/value-claims.tsv missing - check-value-claims was not run (self-graded floor unchecked)"; exit 1; }
    if grep -q 'SUSPECT' "$vc"; then
        echo "FAIL: value-claims.tsv carries an unresolved SUSPECT row: $(grep 'SUSPECT' "$vc" | head -1)"; exit 1
    fi
fi

# 6. Receipt tokens match stage 05's final Disposition lines (when verification.md is
#    present): disposition inline may land inline or body-only; report-only and dropped
#    must land exactly as decided - 06 may not overrule 05 in either direction.
ver="$ICM_RUN_DIR/05-verify/output/verification.md"
if [ -f "$ver" ] && grep -qE 'Disposition: F[0-9]+ final:' "$ver"; then
    for id in $fids; do
        fdisp=$(grep -oE "Disposition: $id final: (inline|report-only|dropped)" "$ver" | head -1 | awk '{print $4}' || true)
        [ -n "$fdisp" ] || { echo "FAIL: finding $id has no 'Disposition: $id final:' line in verification.md"; exit 1; }
        tok=$(printf '%s' "$cov" | grep -oE "$id:(inline|body-only|report-only|dropped)" | head -1)
        disp=${tok#"$id":}
        case "$fdisp:$disp" in
            inline:inline|inline:body-only|report-only:report-only|dropped:dropped) : ;;
            *) echo "FAIL: $id stage-05 disposition '$fdisp' but receipt token '$disp' - 06 overruled 05"; exit 1 ;;
        esac
    done
fi

# 7. Soft concision check (warn only - the rule is prose: one concise engineer-natural
#    sentence; a hard cap would mangle code snippets).
if [ -s "$ndjson" ]; then
    long=$(jq -r 'select((.body | length) > 400) | .body[0:40]' "$ndjson" 2>/dev/null || true)
    [ -z "$long" ] || echo "warn: inline body >400 chars (concision rule says one sentence): $long..."
    bullets=$(jq -r 'select(.body | test("\\n[-*] ")) | .body[0:40]' "$ndjson" 2>/dev/null || true)
    [ -z "$bullets" ] || echo "warn: inline body contains a bullet list (no bullet essays inline): $bullets..."
fi

echo "ok: inline-comment coverage ($json_len anchored; every finding gated + accounted for)"
