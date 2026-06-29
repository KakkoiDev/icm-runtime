#!/bin/sh
# Output-contract regression check, held out from the LLM grader.
#
# The skill's signature guarantee: every link the deterministic gather found
# (01-context/output/links.tsv) is ACCOUNTED FOR in the link graph
# (02-links/output/link-graph.md) - resolved, walled-off, or explicitly skipped.
# No link is silently dropped. Reads the produced run output via $ICM_RUN_DIR.
# Exit 0 = pass.
set -eu

[ -n "${ICM_RUN_DIR:-}" ] || { echo "FAIL: ICM_RUN_DIR not set (run via icm-improve held-out)"; exit 1; }

links="$ICM_RUN_DIR/01-context/output/links.tsv"
graph="$ICM_RUN_DIR/02-links/output/link-graph.md"
[ -f "$links" ] || { echo "FAIL: links.tsv not found at $links"; exit 1; }
[ -f "$graph" ] || { echo "FAIL: link-graph.md not found at $graph"; exit 1; }

missing=$(cut -f1 "$links" | sort -u | while IFS= read -r u; do
    [ -n "$u" ] || continue
    grep -Fq "$u" "$graph" || printf '%s\n' "$u"
done)

if [ -n "$missing" ]; then
    echo "FAIL: links not accounted for in the link graph (silently dropped):"
    printf '%s\n' "$missing"
    exit 1
fi

n=$(cut -f1 "$links" | sort -u | grep -c .)
echo "ok: all $n links accounted for in the link graph"
