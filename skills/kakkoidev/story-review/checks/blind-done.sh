#!/bin/sh
# Gate for stage 02b's Write. Executed by icm.sh check_run with cwd = the
# 02b-comment-pass stage dir, so paths are relative to it.
#
# The comment pass is a SECOND look at findings that already exist. It must not be
# the place a finding is born, because a finding written while reading the owner's
# answers is a lookup, not a review, and it skipped the refutation and grounding
# passes every other finding went through. This gate makes that ordering mechanical:
# no frozen blind findings, no comment pass.
#
# It deliberately does NOT require stage 03's grounding audit - stage 03 runs after
# this one. Stage 04's gate (checks/reviewed.sh) is where the audit becomes required.
set -eu

f=../02-blind-review/output/findings.md

[ -s "$f" ] || { echo "review missing: $f empty (stage 02 not done - the comment pass has nothing to reconcile)"; exit 1; }
grep -qE '^## F[0-9]+' "$f" || { echo "review malformed: $f has no '## F<n>' finding block"; exit 1; }
grep -q '^Independence:' "$f" || { echo "review malformed: $f has no 'Independence:' first line (stage 02 step 0 not done)"; exit 1; }

echo "ok: frozen blind findings present"
