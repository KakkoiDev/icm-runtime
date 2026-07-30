#!/bin/sh
# Regression test for the answer-key target guard (added 2026-07-29).
#
# Real failure it encodes: a run reviewed a SIBLING story and stage 03 was pointed
# at the US-01-derived answer key anyway. The scorer happily returned a
# reasonable-looking hit count built entirely out of shared financial vocabulary,
# and only a human noticing "this key isn't for this story" stopped it from being
# reported as coverage. Fails on the pre-guard score-coverage (which ignored the
# id arguments and printed a number). Exit 0 = pass.
set -eu

workdir=$(mktemp -d)
trap 'rm -rf "$workdir"' EXIT

script_dir=$(cd "$(dirname "$0")/.." && pwd)

cat > "$workdir/findings.md" <<'EOF'
## F1 - L1 - low
The term "confirmed agreement" is never defined in this document.
EOF

cat > "$workdir/answer-key.tsv" <<'EOF'
id	lens	primary_regex	secondary_regex	description
T8	L1-jargon	(confirmed agreement)		vague business term used without a plain definition
EOF

echo "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa" > "$workdir/key-target.txt"

# --- 1. same target: must score normally ---------------------------------------
echo "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa" > "$workdir/target-same.txt"
out=$("$script_dir/tools/score-coverage" "$workdir/findings.md" "$workdir/answer-key.tsv" \
    "$workdir/target-same.txt" "$workdir/key-target.txt")
printf '%s\n' "$out" | grep -q '^Hits: 1/1$' || {
    echo "FAIL: matching target should score normally, expected 'Hits: 1/1', got:"
    printf '%s\n' "$out"; exit 1; }

# --- 2. dashed vs dashless form of the SAME id must still compare equal --------
echo "aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa" > "$workdir/target-dashed.txt"
out=$("$script_dir/tools/score-coverage" "$workdir/findings.md" "$workdir/answer-key.tsv" \
    "$workdir/target-dashed.txt" "$workdir/key-target.txt")
printf '%s\n' "$out" | grep -q '^Hits: 1/1$' || {
    echo "FAIL: dashed form of the same id must normalize equal, got:"
    printf '%s\n' "$out"; exit 1; }

# --- 3. different target: must REFUSE to emit a number ------------------------
echo "bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb" > "$workdir/target-other.txt"
out=$("$script_dir/tools/score-coverage" "$workdir/findings.md" "$workdir/answer-key.tsv" \
    "$workdir/target-other.txt" "$workdir/key-target.txt")
printf '%s\n' "$out" | grep -q '^Hits: n/a$' || {
    echo "FAIL: mismatched target must emit 'Hits: n/a', got:"
    printf '%s\n' "$out"; exit 1; }
printf '%s\n' "$out" | grep -qF '## Not applicable' || {
    echo "FAIL: mismatched target must emit a '## Not applicable' block"; exit 1; }
# the contract test downstream still requires every section to be present
for section in "## Matched" "## Missed" "## New candidates" "## Ambiguous overlap"; do
    printf '%s\n' "$out" | grep -qF "$section" || {
        echo "FAIL: not-applicable report is missing section '$section'"; exit 1; }
done

# --- 4. no id arguments: unchanged legacy behavior ----------------------------
out=$("$script_dir/tools/score-coverage" "$workdir/findings.md" "$workdir/answer-key.tsv")
printf '%s\n' "$out" | grep -q '^Hits: 1/1$' || {
    echo "FAIL: with no id args the scorer must behave exactly as before, got:"
    printf '%s\n' "$out"; exit 1; }

# --- 5. only one id argument: hard error, never a silent unguarded score ------
if "$script_dir/tools/score-coverage" "$workdir/findings.md" "$workdir/answer-key.tsv" \
    "$workdir/target-other.txt" >/dev/null 2>&1; then
    echo "FAIL: a single id argument must be an error, not a silently unguarded score"
    exit 1
fi

echo "ok: target guard scores on match, refuses on mismatch, normalizes dashes, stays back-compatible"
