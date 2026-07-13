#!/bin/sh
# Gate for stage 04's Write (the review output). Executed by icm.sh check_run with
# cwd = the 04-review stage dir, so paths are relative to it.
#
# Passes when: (a) the stage-03 grounding exists (the review must be grounded, not
# diff-only), AND (b) the reviewed revision is settled - either the seal did NOT
# diverge, or a valid seal-decision.tsv records the human's review-target choice.
#
# This is the harness half of the diverged-state rule (SOBA-285 #24370, review 4): on
# divergence the review must default to the sealed PR or carry a RECORDED human
# approval to review the local working tree - never silently review local code.
#
# Deterministic, fail-closed, no deps beyond POSIX sh + awk.
set -eu

ctx=../01-context/output
ev=../03-runtime-evidence/output

# (a) grounding (subsumes the old inline gate: runtime-evidence.md + impact.md)
[ -s "$ev/runtime-evidence.md" ] || { echo "grounding missing: $ev/runtime-evidence.md empty (stage 03 not done)"; exit 1; }
[ -s "$ev/impact.md" ] || { echo "grounding missing: $ev/impact.md empty (stage 03 not done)"; exit 1; }

# (b) reviewed-revision decision, only required when the seal diverged
seal="$ctx/seal.tsv"
if [ -f "$seal" ] && awk -F'\t' '$1=="diverged"{exit ($2=="yes")?0:1}' "$seal"; then
    dec="$ctx/seal-decision.tsv"
    [ -f "$dec" ] || { echo "seal diverged=yes but $dec is missing: stage 01 must record the review-target decision (target=sealed | working-tree)"; exit 1; }
    target=$(awk -F'\t' '$1=="target"{print $2; exit}' "$dec")
    approved=$(awk -F'\t' '$1=="human_approved"{print $2; exit}' "$dec")
    case "$target" in
        sealed)
            : ;;  # reviewing the actual PR is always allowed
        working-tree)
            [ "$approved" = yes ] || { echo "seal-decision target=working-tree requires human_approved=yes (reviewing local code instead of the PR needs recorded human approval)"; exit 1; } ;;
        *)
            echo "seal-decision.tsv target must be 'sealed' or 'working-tree' (got: '${target:-<empty>}')"; exit 1 ;;
    esac
fi

echo "ok: review precondition met"
