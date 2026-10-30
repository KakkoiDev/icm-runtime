#!/bin/sh
# Regression test for the block-splitter bug found live during the 2026-07-28
# variance study: a non-`## F<n>` header (a reviewer's own lens-divider, e.g.
# `## L2 - ...`) used to glue onto the PRECEDING finding block instead of
# terminating it, inflating that block's keyword surface with unrelated text.
# This test fails on the pre-fix score-coverage and passes on the fix.
# Exit 0 = pass.
set -eu

workdir=$(mktemp -d)
trap 'rm -rf "$workdir"' EXIT

cat > "$workdir/findings.md" <<'EOF'
## F1 - L1 - high
This finding discusses something else entirely, nothing about the test topic.

## L2 - grounding check
No sibling grounding this run, entirely unrelated to F1's own topic.

## F2 - L3 - medium
Second finding text, standalone, unrelated to the divider above.
EOF

cat > "$workdir/answer-key.tsv" <<'EOF'
id	lens	primary_regex	secondary_regex	description
TX	L8	(rounding)	(unrelated)	test row - the divider's "grounding" text must not be credited to F1
EOF

script_dir=$(cd "$(dirname "$0")/.." && pwd)
out=$("$script_dir/tools/score-coverage" "$workdir/findings.md" "$workdir/answer-key.tsv")

if printf '%s\n' "$out" | grep -q "matched by: F1"; then
    echo "FAIL: TX was credited to F1 - the L2 divider line leaked into F1's block (block-splitter regression)"
    printf '%s\n' "$out"
    exit 1
fi

if ! printf '%s\n' "$out" | grep -q "^Hits: 0/1"; then
    echo "FAIL: expected Hits: 0/1 (TX should not match either block), got:"
    printf '%s\n' "$out"
    exit 1
fi

echo "ok: divider text correctly excluded from F1's block"
