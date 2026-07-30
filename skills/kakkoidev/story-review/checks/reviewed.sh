#!/bin/sh
# Gate for stage 04's Write. Executed by icm.sh check_run with cwd = the
# 04-handoff stage dir, so paths are relative to it.
#
# The handoff is a reshaping of audited findings, never a place to originate them.
# This gate blocks it until the audit stages actually ran: findings.md must contain
# at least one `## F<n>` block, and stage 03's grounding audit must exist with a
# well-formed number. Without the second condition a handoff could be written off
# findings nobody checked for a quote, a confidence label, or evidence - which is
# exactly the hand-built artifact this stage replaced.
set -eu

f=../02-blind-review/output/findings.md
g=../03-score/output/grounding-audit.md

[ -s "$f" ] || { echo "review missing: $f empty (stage 02 not done)"; exit 1; }
grep -qE '^## F[0-9]+' "$f" || { echo "review malformed: $f has no '## F<n>' finding block"; exit 1; }
[ -s "$g" ] || { echo "audit missing: $g empty (stage 03 step 2 not done - no grounding number to carry into the handoff)"; exit 1; }
grep -qE '^Grounded: [0-9]+/[0-9]+$' "$g" || { echo "audit malformed: $g has no well-formed 'Grounded: N/M' line"; exit 1; }

echo "ok: audited findings present"
