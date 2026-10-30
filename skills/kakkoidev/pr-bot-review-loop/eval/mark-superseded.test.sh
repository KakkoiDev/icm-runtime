#!/bin/sh
# Freezes tools/mark-superseded: R11's cleanup and its guardrails. The GitHub CLI is
# stubbed, so nothing is ever minimized for real here. Runs from the skill dir.
#
# What this pins, and why each one matters:
#   - the latest bot report is never collapsed (the human needs it);
#   - a comment the bot did not author is REFUSED (never a human's comment);
#   - an already-minimized comment is skipped (idempotent);
#   - a dry run makes NO mutation call at all;
#   - every target goes in ONE aliased call - the batching that makes the whole cleanup
#     cost the captain one approval instead of one per comment.
set -eu

tool="tools/mark-superseded"
test -x "$tool" || { echo "FAIL: $tool missing or not executable"; exit 1; }
command -v jq >/dev/null 2>&1 || { echo "SKIP: jq not installed"; exit 0; }

tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT
T=$(printf '\t')

cat > "$tmp/comments.json" <<'EOF'
[{"id":101,"node_id":"IC_kwOld1","user":{"login":"claude[bot]"}},
 {"id":102,"node_id":"IC_kwOld2","user":{"login":"claude[bot]"}},
 {"id":103,"node_id":"IC_kwHuman","user":{"login":"cyril"}},
 {"id":104,"node_id":"IC_kwLatest","user":{"login":"claude[bot]"}}]
EOF

cat > "$tmp/ghstub" <<'STUB'
#!/bin/sh
FX=${FX:?}
if [ "${1:-}" = api ] && [ "${2:-}" = POST ]; then
    echo "call" >> "$FX/calls"
    printf '%s\n' "${5:-}" >> "$FX/queries"
    echo '{"data":{"m0":{"minimizedComment":{"isMinimized":true}},"m1":{"minimizedComment":{"isMinimized":true}}}}'
    exit 0
fi
cat "$FX/comments.json"
STUB
chmod +x "$tmp/ghstub"
export FX="$tmp"

# 101 and 102 are superseded and expanded; 103 is a human's comment mislabelled as the
# bot's; 104 is the current report.
{
    printf '101%s2026-09-01T00:00:00Z%sno%syes\n' "$T" "$T" "$T"
    printf '102%s2026-09-02T00:00:00Z%sno%syes\n' "$T" "$T" "$T"
    printf '103%s2026-09-03T00:00:00Z%sno%syes\n' "$T" "$T" "$T"
    printf '104%s2026-09-04T00:00:00Z%sno%sno\n'  "$T" "$T" "$T"
} > "$tmp/bc.tsv"

# ---- dry run: reports intent, mutates nothing ----
: > "$tmp/calls"; : > "$tmp/queries"
out=$(GHBIN="$tmp/ghstub" sh "$tool" o/r 7 "$tmp/bc.tsv" --bot claude 2>&1 || true)
printf '%s' "$out" | grep -q "^WOULD-MINIMIZE${T}101" || { echo "FAIL: 101 should be a dry-run target"; printf '%s\n' "$out"; exit 1; }
printf '%s' "$out" | grep -q "^WOULD-MINIMIZE${T}102" || { echo "FAIL: 102 should be a dry-run target"; printf '%s\n' "$out"; exit 1; }
printf '%s' "$out" | grep -q "^REFUSE${T}103" || { echo "FAIL: 103 is authored by a human and must be REFUSED"; printf '%s\n' "$out"; exit 1; }
printf '%s' "$out" | grep -q "^SKIP${T}104" || { echo "FAIL: 104 is the latest report and must be skipped"; printf '%s\n' "$out"; exit 1; }
[ ! -s "$tmp/calls" ] || { echo "FAIL: a dry run must make no mutation call"; exit 1; }

# ---- apply: one batched call for both targets ----
: > "$tmp/calls"; : > "$tmp/queries"
out=$(GHBIN="$tmp/ghstub" sh "$tool" o/r 7 "$tmp/bc.tsv" --bot claude --apply 2>&1 || true)
n=$(awk 'END{print NR+0}' "$tmp/calls")
[ "$n" = 1 ] || { echo "FAIL: the cleanup must be ONE batched call (one approval), made $n"; exit 1; }
q=$(cat "$tmp/queries")
printf '%s' "$q" | grep -q 'm0: minimizeComment' || { echo "FAIL: the call must use GraphQL aliases"; exit 1; }
printf '%s' "$q" | grep -q 'm1: minimizeComment' || { echo "FAIL: both targets must be in the one call"; exit 1; }
printf '%s' "$q" | grep -q 'classifier:OUTDATED' || { echo "FAIL: the classifier must be OUTDATED"; exit 1; }
printf '%s' "$q" | grep -q 'IC_kwOld1' || { echo "FAIL: target 101's node id must be in the mutation"; exit 1; }
if printf '%s' "$q" | grep -q 'IC_kwLatest'; then echo "FAIL: the latest report must never be minimized"; exit 1; fi
if printf '%s' "$q" | grep -q 'IC_kwHuman'; then echo "FAIL: a human's comment must never be minimized"; exit 1; fi
printf '%s' "$out" | grep -q "^MINIMIZED${T}101" || { echo "FAIL: 101 should report MINIMIZED"; printf '%s\n' "$out"; exit 1; }

# ---- idempotent: an already-minimized comment is not re-sent ----
: > "$tmp/calls"; : > "$tmp/queries"
{
    printf '101%s2026-09-01T00:00:00Z%syes%syes\n' "$T" "$T" "$T"
    printf '104%s2026-09-04T00:00:00Z%sno%sno\n'   "$T" "$T" "$T"
} > "$tmp/bc-done.tsv"
out=$(GHBIN="$tmp/ghstub" sh "$tool" o/r 7 "$tmp/bc-done.tsv" --bot claude --apply 2>&1 || true)
printf '%s' "$out" | grep -q "^SKIP${T}101${T}already-minimized" || { echo "FAIL: an already-minimized comment must be skipped"; printf '%s\n' "$out"; exit 1; }
[ ! -s "$tmp/calls" ] || { echo "FAIL: nothing to do must make no mutation call"; exit 1; }

echo ok
