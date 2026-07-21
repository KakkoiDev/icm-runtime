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
# Round 3 (gaming hardening): every consistency rule here is closed against the runs
# that satisfy the letter while violating the intent - duplicate/conflicting tokens,
# a forged value-claims.tsv (re-derived from the sealed diff when available), a
# non-array anchored payload, comments posted without parseable finding ids, a skipped
# judgment pass, identity-swapped comments, and noise rerouted via review-summary.md.
# Dispositions: F<n>:inline | F<n>:body-only(<reason>) | F<n>:report-only(<reason>) |
# F<n>:dropped(<reason>). Enforced against the produced run via $ICM_RUN_DIR. Exit 0 = pass.
set -eu

[ -n "${ICM_RUN_DIR:-}" ] || { echo "FAIL: ICM_RUN_DIR not set"; exit 1; }
command -v jq >/dev/null 2>&1 || { echo "FAIL: jq not found"; exit 1; }

out="$ICM_RUN_DIR/06-report/output"
ndjson="$out/review-comments.ndjson"
json="$out/review-comments.json"
receipt="$out/report-receipt.md"
summary="$out/review-summary.md"
findings="$ICM_RUN_DIR/04-review/output/findings.md"
prdiff="$ICM_RUN_DIR/01-context/output/pr.diff"

# Finding ids are harvested only from block-header lines (the id leads the line, after
# markup) - a prose mention ("recurs the #24618 F9 pattern") must not mint a phantom
# finding that then false-fails the coverage completeness assertion.
fids=""
[ -f "$findings" ] && fids=$(grep -oE '^[^[:alnum:]]*F[0-9]+' "$findings" | grep -oE 'F[0-9]+' | sort -u || true)

has_ndjson=0
if [ -s "$ndjson" ] && grep -q '[^[:space:]]' "$ndjson"; then has_ndjson=1; fi

# Comments authored with NO parseable finding ids: every per-finding rule below would
# silently vacuous-pass (empty fids loop), so refuse the shape outright.
if [ -z "$fids" ] && [ "$has_ndjson" = 1 ]; then
    echo "FAIL: review-comments.ndjson has rows but findings.md has no line-leading F<n> finding ids (per-finding checks disabled)"; exit 1
fi

# Applies when the run produced findings OR authored/anchored inline comments. A run
# with findings but an empty ndjson is NOT exempt - an over-aggressive filter that
# demotes everything to report-only must still reconcile against the coverage line;
# nor is an anchored payload with no ndjson source.
if [ -z "$fids" ] && [ "$has_ndjson" = 0 ] && { [ ! -s "$json" ] || [ "$(jq 'if type=="array" then length else -1 end' "$json" 2>/dev/null || echo -1)" = 0 ]; }; then
    echo "ok: no findings and no authored inline comments - nothing to reconcile"
    exit 0
fi

# 1. The receipt must carry the findings->disposition reconciliation line.
[ -f "$receipt" ] || { echo "FAIL: report-receipt.md missing"; exit 1; }
cov=$(grep -iE 'Findings coverage:' "$receipt" | head -1 || true)
[ -n "$cov" ] \
    || { echo "FAIL: receipt has no 'Findings coverage:' line (inline-comment coverage freeze, #24618)"; exit 1; }

# 2. Claimed inline count == comments actually anchored in review-comments.json,
#    which must be a real JSON array (a scalar/object cannot forge the count).
inline_claimed=$(printf '%s' "$cov" | grep -oE 'F[0-9]+:inline' | wc -l | tr -d ' ')
json_len=0
if [ -s "$json" ]; then
    json_len=$(jq 'if type=="array" then length else -1 end' "$json" 2>/dev/null || echo -1)
    [ "$json_len" -ge 0 ] || { echo "FAIL: review-comments.json is not a JSON array"; exit 1; }
elif [ "$inline_claimed" != 0 ]; then
    echo "FAIL: coverage claims $inline_claimed inline comment(s) but review-comments.json is missing/empty (build-review-comments not run)"; exit 1
fi
[ "$inline_claimed" = "$json_len" ] \
    || { echo "FAIL: coverage claims $inline_claimed inline comment(s) but review-comments.json has $json_len (a dropped/over-claimed finding)"; exit 1; }

# 3. Per-finding disposition tokens: every F<n> in findings.md appears on the coverage
#    line with EXACTLY ONE well-formed token; body-only/report-only/dropped carry a
#    non-empty reason. Duplicate tokens for one id (e.g. F2:report-only(...) AND
#    F2:inline) are a forgery vector, not a tie to resolve.
for id in $fids; do
    ntok=$(printf '%s' "$cov" | grep -oE "$id:(inline|body-only|report-only|dropped)" | sort -u | wc -l | tr -d ' ')
    [ "$ntok" -le 1 ] \
        || { echo "FAIL: $id has $ntok conflicting disposition tokens on the coverage line"; exit 1; }
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
#    Conflicting floor labels for one id FAIL (never silently first-wins).
if [ -n "$fids" ]; then
    pairs=$(awk '
        /^[^[:alnum:]]*F[0-9]+/ { if (match($0, /F[0-9]+/)) cur = substr($0, RSTART, RLENGTH) }
        /Value:.*floor=(pass|fail)/ { if (cur != "") { f = ($0 ~ /floor=pass/) ? "pass" : "fail"; print cur, f } }
    ' "$findings" | sort -u)
    [ -n "$pairs" ] \
        || { echo "FAIL: findings.md has findings but no 'Value: ... floor=pass|fail' lines (the value gate was skipped, #24618)"; exit 1; }
    for id in $fids; do
        nfloor=$(printf '%s\n' "$pairs" | awk -v id="$id" '$1==id' | wc -l | tr -d ' ')
        [ "$nfloor" -le 1 ] || { echo "FAIL: finding $id has conflicting floor=pass AND floor=fail Value lines"; exit 1; }
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

# 5. The self-graded floor was cross-checked: value-claims.tsv exists, carries no
#    unresolved SUSPECT, and has a row per finding. When the sealed diff is available,
#    RE-DERIVE the report with the tool and compare - a hand-forged tsv (never actually
#    produced by check-value-claims) must not pass as "deterministically checked".
if [ -n "$fids" ]; then
    vc="$ICM_RUN_DIR/05-verify/output/value-claims.tsv"
    [ -f "$vc" ] \
        || { echo "FAIL: 05-verify/output/value-claims.tsv missing - check-value-claims was not run (self-graded floor unchecked)"; exit 1; }
    if grep -q 'SUSPECT' "$vc"; then
        echo "FAIL: value-claims.tsv carries an unresolved SUSPECT row: $(grep 'SUSPECT' "$vc" | head -1)"; exit 1
    fi
    for id in $fids; do
        awk -F'\t' -v id="$id" '$1==id{found=1} END{exit !found}' "$vc" \
            || { echo "FAIL: finding $id has no row in value-claims.tsv (cross-check incomplete)"; exit 1; }
    done
    cvc="$(dirname "$0")/../tools/check-value-claims"
    if [ -x "$cvc" ] && [ -s "$prdiff" ]; then
        rerun=$(mktemp); trap 'rm -f "$rerun"' EXIT
        if "$cvc" "$findings" "$prdiff" > "$rerun" 2>/dev/null; then
            if ! cmp -s <(cut -f1,3 "$rerun" | sort) <(cut -f1,3 "$vc" | sort); then
                echo "FAIL: value-claims.tsv does not match a re-run of check-value-claims against the sealed diff (forged or stale cross-check)"; exit 1
            fi
        else
            echo "FAIL: check-value-claims failed on the sealed diff but value-claims.tsv exists (where did it come from?)"; exit 1
        fi
    fi
fi

# 6. Stage 05's judgment pass is MANDATORY when findings exist: verification.md must
#    carry one final Disposition per finding, and the receipt tokens must match -
#    disposition inline may land inline or body-only; report-only and dropped land
#    exactly as decided. An opt-in guard here would let a run skip the pass entirely
#    (the artifact under test must not control whether it is tested).
if [ -n "$fids" ]; then
    ver="$ICM_RUN_DIR/05-verify/output/verification.md"
    [ -f "$ver" ] || { echo "FAIL: 05-verify/output/verification.md missing (judgment pass skipped)"; exit 1; }
    for id in $fids; do
        fdisp=$(grep -oE "Disposition: $id final: (inline|report-only|dropped)" "$ver" | head -1 | awk '{print $4}' || true)
        [ -n "$fdisp" ] || { echo "FAIL: finding $id has no 'Disposition: $id final:' line in verification.md (judgment pass skipped or incomplete)"; exit 1; }
        tok=$(printf '%s' "$cov" | grep -oE "$id:(inline|body-only|report-only|dropped)" | head -1)
        disp=${tok#"$id":}
        case "$fdisp:$disp" in
            inline:inline|inline:body-only|report-only:report-only|dropped:dropped) : ;;
            *) echo "FAIL: $id stage-05 disposition '$fdisp' but receipt token '$disp' - 06 overruled 05"; exit 1 ;;
        esac
    done
fi

# 7. Identity check: the coverage line's :inline ids must be the ids actually leading
#    the authored comment bodies (count-matching alone lets a demoted finding post
#    under a posted finding's token). And review-summary.md - the review BODY, which
#    reaches the PR on submit - must carry every posted finding and NO report-only/
#    dropped finding (the noise-reroute channel).
nd_ids=""
[ "$has_ndjson" = 1 ] && nd_ids=$(jq -r '.body' "$ndjson" 2>/dev/null | grep -oE '^[^[:alnum:]]*F[0-9]+' | grep -oE 'F[0-9]+' | sort -u || true)
posted=0
for id in $fids; do
    tok=$(printf '%s' "$cov" | grep -oE "$id:(inline|body-only|report-only|dropped)" | head -1)
    disp=${tok#"$id":}
    case "$disp" in
        inline)
            posted=1
            printf '%s\n' "$nd_ids" | grep -qx "$id" \
                || { echo "FAIL: $id is :inline on the coverage line but no ndjson body leads with $id (identity mismatch)"; exit 1; }
            ;;
        body-only) posted=1 ;;
    esac
done
if [ "$posted" = 1 ]; then
    [ -s "$summary" ] || { echo "FAIL: findings were posted (inline/body-only) but review-summary.md is missing/empty (it is the pending review's body)"; exit 1; }
    for id in $fids; do
        tok=$(printf '%s' "$cov" | grep -oE "$id:(inline|body-only|report-only|dropped)" | head -1)
        disp=${tok#"$id":}
        case "$disp" in
            inline|body-only)
                grep -qE "$id([^0-9]|\$)" "$summary" \
                    || { echo "FAIL: posted finding $id absent from review-summary.md"; exit 1; }
                ;;
            report-only|dropped)
                if grep -qE "$id([^0-9]|\$)" "$summary"; then
                    echo "FAIL: $disp finding $id appears in review-summary.md - the summary is the review body and reaches the PR on submit (noise reroute)"; exit 1
                fi
                ;;
        esac
    done
fi

# 8. Soft concision check (warn only - the rule is prose: one concise engineer-natural
#    sentence; a hard cap would mangle code snippets).
if [ "$has_ndjson" = 1 ]; then
    long=$(jq -r 'select((.body | length) > 400) | .body[0:40]' "$ndjson" 2>/dev/null || true)
    [ -z "$long" ] || echo "warn: inline body >400 chars (concision rule says one sentence): $long..."
    bullets=$(jq -r 'select(.body | test("\\n[-*] ")) | .body[0:40]' "$ndjson" 2>/dev/null || true)
    [ -z "$bullets" ] || echo "warn: inline body contains a bullet list (no bullet essays inline): $bullets..."
fi

echo "ok: inline-comment coverage ($json_len anchored; every finding gated + accounted for)"
