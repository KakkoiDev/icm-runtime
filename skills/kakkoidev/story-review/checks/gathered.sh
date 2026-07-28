#!/bin/sh
# Gate for stage 02's Write. Executed by icm.sh check_run with cwd = the
# 02-blind-review stage dir, so paths are relative to it.
#
# Passes when stage 01's core artifacts exist and are non-empty - the review must
# be grounded in a real fetched body and real schema facts (and have done its
# prior-run check), not started blind on nothing.
set -eu

g=../01-gather/output
[ -s "$g/target-id.txt" ] || { echo "gather missing: $g/target-id.txt empty (stage 01 step 0 not done)"; exit 1; }
[ -f "$g/prior-runs.tsv" ] || { echo "gather missing: $g/prior-runs.tsv not found (stage 01 step 0b not done)"; exit 1; }
[ -s "$g/story-body.md" ] || { echo "gather missing: $g/story-body.md empty (stage 01 not done)"; exit 1; }
[ -s "$g/schema-facts.md" ] || { echo "gather missing: $g/schema-facts.md empty (stage 01 not done)"; exit 1; }

echo "ok: gather artifacts present"
