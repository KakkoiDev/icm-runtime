#!/bin/sh
# Freezes tools/ledger-audit: the mechanical half of the loop rules. Every case below is
# one of the twelve rules failing in the shape it failed on a real PR, plus the clean case
# that must still pass. Runs from the skill dir. Exit 0 = pass.
set -eu

tool="tools/ledger-audit"
test -x "$tool" || { echo "FAIL: $tool missing or not executable"; exit 1; }

tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT
T=$(printf '\t')

# ---- the clean, converged loop ----
# round 1 found 3 things and pushed; round 2 came back quiet on the new head and pushed
# nothing. That last part is R9: the loop's final action is a review, never a push.
mkrounds() {
    printf '# round\trequest_verdict\treviewed_sha\thead_sha\tstale\tfindings\tactionable\tthreads_open\tthreads_unanswered\tpushed_sha\tdefect_class_recheck\n' > "$1"
    printf '1%sFIRED%ssha1%ssha1%sno%s3%s3%s0%s0%ssha2%sdone\n' "$T" "$T" "$T" "$T" "$T" "$T" "$T" "$T" "$T" "$T" >> "$1"
    printf '2%sFIRED%ssha2%ssha2%sno%s1%s0%s0%s0%s-%sn/a\n'    "$T" "$T" "$T" "$T" "$T" "$T" "$T" "$T" "$T" "$T" >> "$1"
}
mkledger() {
    printf '# round\tfinding_id\tseverity\tdisposition\treason\tevidence\n' > "$1"
    printf '1%sF1%sHIGH%sfixed%smissing depth guard%sPROVEN (revert-proof-1.tsv)\n' "$T" "$T" "$T" "$T" "$T" >> "$1"
    printf '1%sF2%sMEDIUM%srefused-fix-wrong%sthe proposed message is wrong at depth 1%ssource read\n' "$T" "$T" "$T" "$T" "$T" >> "$1"
    printf '1%sF3%sLOW%sout-of-scope%swidens past the ticket; ticket=AILAB-999%s-\n' "$T" "$T" "$T" "$T" "$T" >> "$1"
}
cat > "$tmp/pr-body.md" <<'EOF'
## Refusals
- F2: refused the proposed fix (the message is wrong at depth 1).
## Out of scope
- Tracked in AILAB-999.
EOF
printf 'head_sha%ssha2\nobserved_at%s2026-09-09T01:00:00Z\n' "$T" "$T" > "$tmp/exit-head.tsv"

mkrounds "$tmp/rounds.tsv"
mkledger "$tmp/ledger.tsv"

audit() {
    # audit <rounds> <ledger> <pr-body> <mode> [extra args...]
    r=$1; l=$2; b=$3; m=$4; shift 4
    "$tool" --rounds "$r" --ledger "$l" --pr-body "$b" --mode "$m" "$@" 2>&1 || true
}

expect_pass_all() {
    out=$1; name=$2
    if printf '%s' "$out" | grep -q '^FAIL'; then
        echo "FAIL: $name should have passed every check, got:"; printf '%s\n' "$out"; exit 1
    fi
}
expect_fail() {
    out=$1; check=$2; name=$3
    printf '%s' "$out" | grep -q "^FAIL${T}${check}${T}" || {
        echo "FAIL: $name should have failed check '$check', got:"; printf '%s\n' "$out"; exit 1; }
}

# 1. clean loop, converged mode: everything passes, exit 0
out=$(audit "$tmp/rounds.tsv" "$tmp/ledger.tsv" "$tmp/pr-body.md" converged --exit-head "$tmp/exit-head.tsv")
expect_pass_all "$out" "the clean converged loop"
"$tool" --rounds "$tmp/rounds.tsv" --ledger "$tmp/ledger.tsv" --pr-body "$tmp/pr-body.md" \
    --mode converged --exit-head "$tmp/exit-head.tsv" >/dev/null 2>&1 \
    || { echo "FAIL: the clean converged loop must exit 0"; exit 1; }

# 2. R1 - a round whose request never fired is not a round (PR 26205 round 9)
mkrounds "$tmp/r-unfired.tsv"
printf '3%sUNCONFIRMED(no-activity)%ssha2%ssha2%sno%s0%s0%s0%s0%s-%sn/a\n' "$T" "$T" "$T" "$T" "$T" "$T" "$T" "$T" "$T" "$T" >> "$tmp/r-unfired.tsv"
out=$(audit "$tmp/r-unfired.tsv" "$tmp/ledger.tsv" "$tmp/pr-body.md" audit)
expect_fail "$out" "request-fired" "an UNCONFIRMED round"

# 3. R2 - a round that produced a finding is not a quiet round
mkrounds "$tmp/r-noisy.tsv"
printf '3%sFIRED%ssha2%ssha2%sno%s2%s2%s0%s0%s-%sn/a\n' "$T" "$T" "$T" "$T" "$T" "$T" "$T" "$T" "$T" "$T" >> "$tmp/r-noisy.tsv"
out=$(audit "$tmp/r-noisy.tsv" "$tmp/ledger.tsv" "$tmp/pr-body.md" converged --exit-head "$tmp/exit-head.tsv")
expect_fail "$out" "quiet-round" "a last round with actionable findings"

# 4. R9 - pushing and declaring done is a defect
mkrounds "$tmp/r-pushed.tsv"
printf '3%sFIRED%ssha2%ssha2%sno%s1%s0%s0%s0%ssha3%sdone\n' "$T" "$T" "$T" "$T" "$T" "$T" "$T" "$T" "$T" "$T" >> "$tmp/r-pushed.tsv"
out=$(audit "$tmp/r-pushed.tsv" "$tmp/ledger.tsv" "$tmp/pr-body.md" converged --exit-head "$tmp/exit-head.tsv")
expect_fail "$out" "push-then-review" "a last round that pushed"

# 5. R9 - the head moved after the last round: the current code was never reviewed
printf 'head_sha%ssha9\nobserved_at%s2026-09-09T01:00:00Z\n' "$T" "$T" > "$tmp/exit-head-moved.tsv"
out=$(audit "$tmp/rounds.tsv" "$tmp/ledger.tsv" "$tmp/pr-body.md" converged --exit-head "$tmp/exit-head-moved.tsv")
expect_fail "$out" "reviewed-is-head" "a head that moved past the last round"

# 6. R7 - a stale round is never the last word (PR 26269)
mkrounds "$tmp/r-stale.tsv"
printf '3%sFIRED%sold%ssha2%syes%s0%s0%s0%s0%s-%sn/a\n' "$T" "$T" "$T" "$T" "$T" "$T" "$T" "$T" "$T" "$T" >> "$tmp/r-stale.tsv"
out=$(audit "$tmp/r-stale.tsv" "$tmp/ledger.tsv" "$tmp/pr-body.md" audit)
expect_fail "$out" "stale-round" "a stale last round"

# 7. R10 - threads left open or unanswered land on the human
mkrounds "$tmp/r-threads.tsv"
printf '3%sFIRED%ssha2%ssha2%sno%s0%s0%s2%s1%s-%sn/a\n' "$T" "$T" "$T" "$T" "$T" "$T" "$T" "$T" "$T" "$T" >> "$tmp/r-threads.tsv"
out=$(audit "$tmp/r-threads.tsv" "$tmp/ledger.tsv" "$tmp/pr-body.md" converged --exit-head "$tmp/exit-head.tsv")
expect_fail "$out" "threads-closed" "open and unanswered threads"

# 8. R5 - a round that pushed without re-checking the PR's own defect class (PR 26205 r9)
mkrounds "$tmp/r-norecheck.tsv"
printf '3%sFIRED%ssha2%ssha2%sno%s1%s1%s0%s0%ssha4%sskipped\n' "$T" "$T" "$T" "$T" "$T" "$T" "$T" "$T" "$T" "$T" >> "$tmp/r-norecheck.tsv"
out=$(audit "$tmp/r-norecheck.tsv" "$tmp/ledger.tsv" "$tmp/pr-body.md" audit)
expect_fail "$out" "defect-class-recheck" "a pushing round that skipped the defect-class re-check"

# 9. R4 - a fix with no two-direction evidence (PR 26203)
mkledger "$tmp/l-noproof.tsv"
printf '2%sF4%sHIGH%sfixed%sadded the guard%sadded a test\n' "$T" "$T" "$T" "$T" "$T" >> "$tmp/l-noproof.tsv"
out=$(audit "$tmp/rounds.tsv" "$tmp/l-noproof.tsv" "$tmp/pr-body.md" audit)
expect_fail "$out" "revert-proof" "a fix whose evidence is not PROVEN"

# 9b. an explicit no-behaviour-change fix is allowed - the escape must exist and be stated
mkledger "$tmp/l-nobehav.tsv"
printf '2%sF4%sLOW%sfixed%srenamed a local%sno-behaviour-change\n' "$T" "$T" "$T" "$T" "$T" >> "$tmp/l-nobehav.tsv"
out=$(audit "$tmp/rounds.tsv" "$tmp/l-nobehav.tsv" "$tmp/pr-body.md" audit)
if printf '%s' "$out" | grep -q "^FAIL${T}revert-proof${T}"; then
    echo "FAIL: an explicit no-behaviour-change fix must not fail the revert-proof check"; exit 1
fi

# 10. R3 - a finding with no valid disposition
mkledger "$tmp/l-nodisp.tsv"
printf '2%sF5%sLOW%s%snothing said%s-\n' "$T" "$T" "$T" "$T" "$T" >> "$tmp/l-nodisp.tsv"
out=$(audit "$tmp/rounds.tsv" "$tmp/l-nodisp.tsv" "$tmp/pr-body.md" audit)
expect_fail "$out" "disposition" "a finding with no disposition"

# 11. R6 - an out-of-scope refusal with no ticket
mkledger "$tmp/l-noticket.tsv"
printf '2%sF6%sMEDIUM%sout-of-scope%swould widen the PR%s-\n' "$T" "$T" "$T" "$T" "$T" >> "$tmp/l-noticket.tsv"
out=$(audit "$tmp/rounds.tsv" "$tmp/l-noticket.tsv" "$tmp/pr-body.md" audit)
expect_fail "$out" "out-of-scope-ticket" "an out-of-scope refusal with no ticket"

# 12. R6 - the ticket exists but never reached the PR description
mkledger "$tmp/l-ticket-unlisted.tsv"
printf '2%sF7%sMEDIUM%sout-of-scope%swould widen the PR; ticket=AILAB-555%s-\n' "$T" "$T" "$T" "$T" "$T" >> "$tmp/l-ticket-unlisted.tsv"
out=$(audit "$tmp/rounds.tsv" "$tmp/l-ticket-unlisted.tsv" "$tmp/pr-body.md" audit)
expect_fail "$out" "out-of-scope-in-pr-body" "a ticket missing from the PR description"

# 13. R3 - a refusal that never reached the PR description
mkledger "$tmp/l-refusal-unlisted.tsv"
printf '2%sF8%sHIGH%srefused-finding-wrong%sthe code does not do that%ssource read\n' "$T" "$T" "$T" "$T" "$T" >> "$tmp/l-refusal-unlisted.tsv"
out=$(audit "$tmp/rounds.tsv" "$tmp/l-refusal-unlisted.tsv" "$tmp/pr-body.md" audit)
expect_fail "$out" "refusals-in-pr-body" "a refusal missing from the PR description"

# 14. converged mode without --exit-head must FAIL, not silently skip the head comparison
out=$(audit "$tmp/rounds.tsv" "$tmp/ledger.tsv" "$tmp/pr-body.md" converged)
expect_fail "$out" "reviewed-is-head" "converged mode with no --exit-head"

# 15. R11, closed mode - cleanup is checked only here, and only after it should have run
printf 'bot_comments_superseded_expanded%s0\n' "$T" > "$tmp/final-clean.tsv"
printf 'bot_comments_superseded_expanded%s3\n' "$T" > "$tmp/final-dirty.tsv"
printf '11%s2026-09-08T00:00:00Z%syes%syes\n' "$T" "$T" "$T" > "$tmp/bc-clean.tsv"
printf '22%s2026-09-09T00:00:00Z%sno%sno\n'  "$T" "$T" "$T" >> "$tmp/bc-clean.tsv"
printf '22%s2026-09-09T00:00:00Z%syes%sno\n' "$T" "$T" "$T" > "$tmp/bc-hidden.tsv"

# request comments: every row is superseded=yes (no exempt "latest" one). Clean = every
# one collapsed, including the last; dirty = the last one is still expanded.
printf '31%s2026-09-01T00:00:00Z%syes%syes\n' "$T" "$T" "$T" > "$tmp/req-clean.tsv"
printf '32%s2026-09-02T00:00:00Z%syes%syes\n' "$T" "$T" "$T" >> "$tmp/req-clean.tsv"
printf '31%s2026-09-01T00:00:00Z%syes%syes\n' "$T" "$T" "$T" > "$tmp/req-dirty.tsv"
printf '32%s2026-09-02T00:00:00Z%sno%syes\n'  "$T" "$T" "$T" >> "$tmp/req-dirty.tsv"
: > "$tmp/req-empty.tsv"

out=$(audit "$tmp/rounds.tsv" "$tmp/ledger.tsv" "$tmp/pr-body.md" closed \
      --exit-head "$tmp/exit-head.tsv" --final-round "$tmp/final-clean.tsv" \
      --final-bot-comments "$tmp/bc-clean.tsv" --final-requests "$tmp/req-clean.tsv")
expect_pass_all "$out" "the clean closed loop"

out=$(audit "$tmp/rounds.tsv" "$tmp/ledger.tsv" "$tmp/pr-body.md" closed \
      --exit-head "$tmp/exit-head.tsv" --final-round "$tmp/final-dirty.tsv" \
      --final-bot-comments "$tmp/bc-clean.tsv" --final-requests "$tmp/req-clean.tsv")
expect_fail "$out" "superseded-collapsed" "superseded reports still expanded"

out=$(audit "$tmp/rounds.tsv" "$tmp/ledger.tsv" "$tmp/pr-body.md" closed \
      --exit-head "$tmp/exit-head.tsv" --final-round "$tmp/final-clean.tsv" \
      --final-bot-comments "$tmp/bc-hidden.tsv" --final-requests "$tmp/req-clean.tsv")
expect_fail "$out" "final-report-visible" "the final report minimized away from the human"

# 15b. R11 extended - the loop's LAST request comment must also be collapsed, not exempted
out=$(audit "$tmp/rounds.tsv" "$tmp/ledger.tsv" "$tmp/pr-body.md" closed \
      --exit-head "$tmp/exit-head.tsv" --final-round "$tmp/final-clean.tsv" \
      --final-bot-comments "$tmp/bc-clean.tsv" --final-requests "$tmp/req-dirty.tsv")
expect_fail "$out" "requests-collapsed" "the last request comment left expanded"

# 15c. closed mode with no --final-requests must FAIL, not silently skip the check
out=$(audit "$tmp/rounds.tsv" "$tmp/ledger.tsv" "$tmp/pr-body.md" closed \
      --exit-head "$tmp/exit-head.tsv" --final-round "$tmp/final-clean.tsv" \
      --final-bot-comments "$tmp/bc-clean.tsv")
expect_fail "$out" "requests-collapsed" "closed mode with no --final-requests"

# 15d. an empty request-comments file is not proof of a clean cleanup
out=$(audit "$tmp/rounds.tsv" "$tmp/ledger.tsv" "$tmp/pr-body.md" closed \
      --exit-head "$tmp/exit-head.tsv" --final-round "$tmp/final-clean.tsv" \
      --final-bot-comments "$tmp/bc-clean.tsv" --final-requests "$tmp/req-empty.tsv")
expect_fail "$out" "requests-collapsed" "an empty final-requests file"

# 16. converged mode must NOT check the R11 cleanup - it happens inside 03, after the gate
out=$(audit "$tmp/rounds.tsv" "$tmp/ledger.tsv" "$tmp/pr-body.md" converged --exit-head "$tmp/exit-head.tsv")
if printf '%s' "$out" | grep -q 'superseded-collapsed'; then
    echo "FAIL: converged mode must not gate on the R11 cleanup (it is the closing step)"; exit 1
fi
if printf '%s' "$out" | grep -q 'requests-collapsed'; then
    echo "FAIL: converged mode must not gate on the request-comment cleanup either"; exit 1
fi

# 17. an empty rounds file is no loop, not a clean one
printf '# round\theader only\n' > "$tmp/r-empty.tsv"
if "$tool" --rounds "$tmp/r-empty.tsv" --ledger "$tmp/ledger.tsv" --pr-body "$tmp/pr-body.md" \
        --mode audit >/dev/null 2>&1; then
    echo "FAIL: an empty rounds file must be refused, not reported as all-PASS"; exit 1
fi

echo ok
