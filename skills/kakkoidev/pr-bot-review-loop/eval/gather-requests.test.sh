#!/bin/sh
# Freezes tools/gather-requests: R11 extended (captain's ruling, 2026-09-09) - every
# review-request comment the loop posted is collected for collapsing, including the last
# one, by marking every row superseded=yes (unlike a bot report, no request comment is
# "the current one"). The GitHub CLI is stubbed, so nothing ever leaves the box here.
# Runs from the skill dir.
set -eu

tool="tools/gather-requests"
test -x "$tool" || { echo "FAIL: $tool missing or not executable"; exit 1; }
command -v jq >/dev/null 2>&1 || { echo "SKIP: jq not installed"; exit 0; }

tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT
T=$(printf '\t')
mkdir -p "$tmp/rounds"

cat > "$tmp/ghstub" <<'STUB'
#!/bin/sh
FX=${FX:?}
if [ "${1:-}" = api ] && [ "${2:-}" = POST ]; then
    cat "$FX/gql.json"
    exit "${GQL_EXIT:-0}"
fi
echo '[]'
STUB
chmod +x "$tmp/ghstub"
export FX="$tmp"
export GQL_EXIT=0
cat > "$tmp/gql.json" <<'EOF'
{"data":{"repository":{"pullRequest":{"comments":{"nodes":[
  {"databaseId":201,"isMinimized":true},
  {"databaseId":202,"isMinimized":false}
]}}}}}
EOF

# round 1: a real request comment
{
    printf 'round%s1\n' "$T"
    printf 'request_comment_id%s201\n' "$T"
    printf 'request_at%s2026-09-01T00:00:00Z\n' "$T"
    printf 'request_author%scyril\n' "$T"
    printf 'verdict%sFIRED\n' "$T"
} > "$tmp/rounds/request-1.tsv"

# round 2: another real one, not yet minimized
{
    printf 'round%s2\n' "$T"
    printf 'request_comment_id%s202\n' "$T"
    printf 'request_at%s2026-09-02T00:00:00Z\n' "$T"
    printf 'request_author%scyril\n' "$T"
    printf 'verdict%sFIRED\n' "$T"
} > "$tmp/rounds/request-2.tsv"

# round 3: request never fired - "-" must not become a target (R1)
{
    printf 'round%s3\n' "$T"
    printf 'request_comment_id%s-\n' "$T"
    printf 'request_at%s-\n' "$T"
    printf 'verdict%sUNFIRED(no-mention)\n' "$T"
} > "$tmp/rounds/request-3.tsv"

# round 4: verify-request-fired re-run against the same comment as round 1 (dedup)
{
    printf 'round%s4\n' "$T"
    printf 'request_comment_id%s201\n' "$T"
    printf 'request_at%s2026-09-01T00:00:00Z\n' "$T"
    printf 'verdict%sFIRED\n' "$T"
} > "$tmp/rounds/request-4.tsv"

out="$tmp/requests.tsv"
GHBIN="$tmp/ghstub" sh "$tool" o/r 7 "$tmp/rounds" "$out"

n=$(awk 'END{print NR+0}' "$out")
[ "$n" = 2 ] || { echo "FAIL: expected exactly 2 rows (201, 202 deduped, '-' skipped), got $n"; cat "$out"; exit 1; }

grep -q "^201${T}2026-09-01T00:00:00Z${T}yes${T}yes\$" "$out" \
    || { echo "FAIL: 201 should be minimized=yes, superseded=yes"; cat "$out"; exit 1; }
grep -q "^202${T}2026-09-02T00:00:00Z${T}no${T}yes\$" "$out" \
    || { echo "FAIL: 202 should be minimized=no, superseded=yes"; cat "$out"; exit 1; }
if grep -q '^-' "$out"; then echo "FAIL: an unfired request ('-') must never become a target"; exit 1; fi

# every row must say superseded=yes - there is no exempt "latest" request comment
bad=$(awk -F'\t' '$4!="yes"{n++} END{print n+0}' "$out")
[ "$bad" = 0 ] || { echo "FAIL: every request-comment row must be superseded=yes, including the newest"; exit 1; }

# ---- no request comments found at all: empty output, exit 0 ----
mkdir -p "$tmp/rounds-empty"
: > "$tmp/rounds-empty/request-1.tsv"
GHBIN="$tmp/ghstub" sh "$tool" o/r 7 "$tmp/rounds-empty" "$tmp/empty.tsv"
[ ! -s "$tmp/empty.tsv" ] || { echo "FAIL: no request comments should yield empty output"; exit 1; }

# ---- the GraphQL read fails: minimized falls back to unknown, never crashes ----
GQL_EXIT=1 GHBIN="$tmp/ghstub" sh "$tool" o/r 7 "$tmp/rounds" "$tmp/degraded.tsv"
grep -q "^201${T}2026-09-01T00:00:00Z${T}unknown${T}yes\$" "$tmp/degraded.tsv" \
    || { echo "FAIL: a failed GraphQL read must degrade minimized to 'unknown', not crash"; cat "$tmp/degraded.tsv"; exit 1; }

echo ok
