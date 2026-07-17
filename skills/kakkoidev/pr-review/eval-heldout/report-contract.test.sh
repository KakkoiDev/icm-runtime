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

# When the PR carried a template checklist (01-context extracted rows), the report
# MUST reconcile it - a code review that never audits the PR against its own
# mandatory checklist is the miss this section closes.
checklist="$ICM_RUN_DIR/01-context/output/checklist.tsv"
if [ -s "$checklist" ]; then
    grep -qiE 'checklist audit' "$report" \
        || { echo "FAIL: checklist.tsv is non-empty but the report has no 'Checklist Audit' section"; exit 1; }
    grep -qiE 'bias alarm' "$report" \
        || { echo "FAIL: checklist audit present but missing the required Bias-alarm self-check line"; exit 1; }
fi

# Re-review independence - cross-checked against the ON-DISK prior reviews, NOT the
# prior-runs.tsv file. A broken detection (empty prior-runs.tsv) must not pass as
# "fresh": count sealed REVIEW-<PR#>.md in sibling runs directly (SOBA-285 #24370).
pr=$(basename "$report" .md); pr=${pr#REVIEW-}
runs_root=$(cd "$ICM_RUN_DIR/.." 2>/dev/null && pwd || echo "")
prior_count=0
if [ -n "$runs_root" ]; then
    for rev in "$runs_root"/*/06-report/output/REVIEW-"$pr".md; do
        [ -f "$rev" ] || continue
        case "$rev" in "$ICM_RUN_DIR"/*) continue ;; esac
        prior_count=$((prior_count + 1))
    done
fi
if [ "$prior_count" -gt 0 ]; then
    grep -qiE 'independence' "$report" \
        || { echo "FAIL: $prior_count prior same-PR review(s) on disk but the report has no Independence disclosure"; exit 1; }
    # A re-review must not claim to be fresh / have no prior.
    if grep -iE 'independence' "$report" | grep -qiE 'fresh|no prior'; then
        echo "FAIL: $prior_count prior same-PR review(s) on disk, but the report's Independence line claims fresh/no-prior"; exit 1
    fi
fi

# Out-of-seal disclosure: if the local checkout diverged from the PR head, the report
# must disclose the reviewed revision / out-of-seal status (SOBA-285 #24370, review 3).
seal="$ICM_RUN_DIR/01-context/output/seal.tsv"
if [ -f "$seal" ] && awk -F'\t' '$1=="diverged"{exit ($2=="yes")?0:1}' "$seal"; then
    grep -qiE 'out-of-seal|reviewed revision|diverged|not the (pr|local) head|behind the reviewed' "$report" \
        || { echo "FAIL: seal.tsv says diverged=yes but the report has no reviewed-revision / out-of-seal disclosure"; exit 1; }
    # A diverged run must carry a recorded, consistent review-target decision: default
    # sealed, or working-tree WITH human approval (never a silent local review).
    dec="$ICM_RUN_DIR/01-context/output/seal-decision.tsv"
    [ -f "$dec" ] || { echo "FAIL: seal.tsv diverged=yes but seal-decision.tsv is missing (01 must record the review target)"; exit 1; }
    dtarget=$(awk -F'\t' '$1=="target"{print $2; exit}' "$dec")
    dappr=$(awk -F'\t' '$1=="human_approved"{print $2; exit}' "$dec")
    case "$dtarget" in
        sealed) : ;;
        working-tree) [ "$dappr" = yes ] || { echo "FAIL: seal-decision target=working-tree without human_approved=yes"; exit 1; } ;;
        *) echo "FAIL: seal-decision.tsv target must be 'sealed' or 'working-tree' (got: '${dtarget:-<empty>}')"; exit 1 ;;
    esac
fi

receipt=$(ls "$ICM_RUN_DIR"/06-report/output/report-receipt.md 2>/dev/null | head -1 || true)
[ -n "$receipt" ] && [ -f "$receipt" ] || { echo "FAIL: report-receipt.md not found"; exit 1; }

# Report-only/dropped findings must be VISIBLE in the report (the value gate keeps them
# off the PR, never out of sight - #24618 round 2), and a run that posted a draft must
# hand off to the human (read, rewrite in your own words, submit - the reviewer's ask).
cov=$(grep -iE 'Findings coverage:' "$receipt" | head -1 || true)
if [ -n "$cov" ]; then
    for id in $(printf '%s' "$cov" | grep -oE 'F[0-9]+:(report-only|dropped)' | cut -d: -f1); do
        grep -q "$id" "$report" \
            || { echo "FAIL: $id is report-only/dropped on the coverage line but never appears in the report (silently invisible)"; exit 1; }
    done
    if printf '%s' "$cov" | grep -qE 'F[0-9]+:inline'; then
        grep -qiE 'Human handoff:' "$receipt" \
            || { echo "FAIL: inline comments were drafted but the receipt has no 'Human handoff:' line (read/rewrite/submit)"; exit 1; }
    fi
fi
last=$(grep -v '^[[:space:]]*$' "$receipt" | tail -1)
case "$last" in
    "VERIFIED: PASS"|"VERIFIED: FAIL") echo "ok: report + receipt verdict ($last)" ;;
    *) echo "FAIL: receipt last line must be exactly 'VERIFIED: PASS' or 'VERIFIED: FAIL' (got: '$last')"; exit 1 ;;
esac
