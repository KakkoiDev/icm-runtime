#!/bin/sh
# Gate for stage 04's Write. Executed by icm.sh check_run with cwd = the
# 04-handoff stage dir, so paths are relative to it.
#
# The handoff is a reshaping of audited, reconciled findings, never a place to
# originate them. This gate blocks it until three things actually happened:
#   1. Stage 02 produced blind findings (`## F<n>` blocks).
#   2. Stage 03 produced a grounding audit with a well-formed number. Without it a
#      handoff could be written off findings nobody checked for a quote, a
#      confidence label, or evidence.
#   3. Stage 02b reconciled against the live comments AND proved its harvest was
#      complete. This third condition is the one written in blood: a handoff was
#      built on a comment read that returned 8 of 24 threads, and it published a
#      question as unanswered that the owner had answered in the same thread. A
#      partial harvest must not be able to reach a deliverable.
set -eu

f=../02-blind-review/output/findings.md
g=../03-score/output/grounding-audit.md
r=../02b-comment-pass/output

[ -s "$f" ] || { echo "review missing: $f empty (stage 02 not done)"; exit 1; }
grep -qE '^## F[0-9]+' "$f" || { echo "review malformed: $f has no '## F<n>' finding block"; exit 1; }
[ -s "$g" ] || { echo "audit missing: $g empty (stage 03 step 2 not done - no grounding number to carry into the handoff)"; exit 1; }
grep -qE '^Grounded: [0-9]+/[0-9]+$' "$g" || { echo "audit malformed: $g has no well-formed 'Grounded: N/M' line"; exit 1; }

[ -s "$r/coverage.txt" ] || { echo "reconcile missing: $r/coverage.txt empty (stage 02b step 1d not done - the comment harvest was never proven complete)"; exit 1; }
grep -q '^ok: harvest complete' "$r/coverage.txt" || {
    echo "reconcile FAILED: $r/coverage.txt does not end in a passing 'ok: harvest complete' line."
    echo "The comment harvest is partial. A truncated read is not a reconciliation - fetch the"
    echo "missing discussions by discussion_id and re-run tools/discussion-coverage."
    exit 1
}
[ -s "$r/dispositions.md" ] || { echo "reconcile missing: $r/dispositions.md empty (stage 02b step 4 not done - no finding has a verdict against the live threads)"; exit 1; }
[ -s "$r/drift-ledger.md" ] || { echo "reconcile missing: $r/drift-ledger.md empty (stage 02b step 3 not done - promises made in comments were never checked against the body)"; exit 1; }

# Every finding must carry a verdict out of 02b. A finding absent from
# dispositions.md reaches the handoff with no idea whether it is already answered.
missing=""
for fid in $(grep -oE '^## F[0-9]+' "$f" | grep -oE 'F[0-9]+' | sort -u); do
    grep -qE "(^|[^A-Za-z0-9])${fid}([^0-9]|$)" "$r/dispositions.md" || missing="$missing $fid"
done
[ -z "$missing" ] || { echo "reconcile incomplete: findings with no verdict in $r/dispositions.md:$missing"; exit 1; }

echo "ok: audited findings present, comment harvest complete, every finding dispositioned"
