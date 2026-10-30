#!/bin/sh
# Freezes tools/gather-ci: R8, both directions.
#   GREEN-OVER-FAILED-STEP  a type-check step OOMs, the log's error count is zero, and
#                           the wrapper stays green.
#   RED-GATE                the analysis passes with zero issues while the gate job
#                           fails on a poll race.
# The GitHub CLI is stubbed, so the check is offline. Runs from the skill dir.
set -eu

tool="tools/gather-ci"
test -x "$tool" || { echo "FAIL: $tool missing or not executable"; exit 1; }
command -v jq >/dev/null 2>&1 || { echo "SKIP: jq not installed"; exit 0; }

tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT
mkdir -p "$tmp/out"

cat > "$tmp/ghstub" <<'STUB'
#!/bin/sh
FX=${FX:?}
case "$*" in
    *check-runs*) cat "$FX/checks.json" ;;
    */status*)    cat "$FX/status.json" ;;
    *pulls/7*)    printf 'deadbeef\n' ;;
    *) echo '{}' ;;
esac
STUB
chmod +x "$tmp/ghstub"
export FX="$tmp"

# A green check whose own type-check step failed, and a healthy one for contrast.
cat > "$tmp/checks.json" <<'EOF'
{"check_runs":[
  {"name":"build","conclusion":"success","app":{"slug":"github-actions"},
   "steps":[{"name":"install","conclusion":"success"},
            {"name":"type-check","conclusion":"failure"}]},
  {"name":"unit","conclusion":"success","app":{"slug":"github-actions"},
   "steps":[{"name":"jest","conclusion":"success"}]}
]}
EOF
cat > "$tmp/status.json" <<'EOF'
{"statuses":[{"context":"SonarQube Quality Gate","state":"failure"}]}
EOF

GHBIN="$tmp/ghstub" sh "$tool" o/r 7 "$tmp/out" 1 >/dev/null 2>&1 || { echo "FAIL: gather-ci exited non-zero"; exit 1; }
f="$tmp/out/ci-1.tsv"
test -s "$f" || { echo "FAIL: no ci-1.tsv written"; exit 1; }

grep -q '^# SUSPECT: GREEN-OVER-FAILED-STEP' "$f" \
    || { echo "FAIL: a green check over a failed step must be flagged"; cat "$f"; exit 1; }
grep -q 'type-check' "$f" \
    || { echo "FAIL: the flagged row must name the failing step"; cat "$f"; exit 1; }
grep -q '^# SUSPECT: RED-GATE' "$f" \
    || { echo "FAIL: a failed quality gate must be flagged as possibly-infrastructure"; cat "$f"; exit 1; }
grep -q '^# TOTAL:' "$f" || { echo "FAIL: the accounting line is missing"; exit 1; }
# The healthy check must not be flagged - a tool that suspects everything is ignored.
if grep '^# SUSPECT' "$f" | grep -q 'unit'; then
    echo "FAIL: a genuinely green check must not be flagged"; cat "$f"; exit 1
fi

# ---- the clean case must say so explicitly, not stay silent ----
cat > "$tmp/checks.json" <<'EOF'
{"check_runs":[
  {"name":"unit","conclusion":"success","app":{"slug":"github-actions"},
   "steps":[{"name":"jest","conclusion":"success"}]}
]}
EOF
echo '{"statuses":[]}' > "$tmp/status.json"
GHBIN="$tmp/ghstub" sh "$tool" o/r 7 "$tmp/out" 2 >/dev/null 2>&1 || { echo "FAIL: gather-ci exited non-zero on the clean case"; exit 1; }
grep -q '^# CLEAR:' "$tmp/out/ci-2.tsv" \
    || { echo "FAIL: searched-and-clean must be stated, never left as silence"; cat "$tmp/out/ci-2.tsv"; exit 1; }
if grep -q '^# SUSPECT' "$tmp/out/ci-2.tsv"; then
    echo "FAIL: the clean case must produce no SUSPECT rows"; cat "$tmp/out/ci-2.tsv"; exit 1
fi

echo ok
