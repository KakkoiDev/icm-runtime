#!/bin/sh
# Freezes tools/extract-body-claims: the deterministic extraction of factual claims from a
# PR body, so stage 04 verifies each against the diff instead of reading the body as
# context. Born from PR bodies whose claims the code contradicted: "now once" false on one
# path, "no version moves" false, "same shape already used" false, a fix the diff did not
# contain, stale test counts.
# Cases: counts, "now"/"once"/"no"/"same as"/"fixes"/"only"/"already" sentences are
# extracted with their line number and markers; headings, checkbox lines, code fences and
# bare links are not; a body with no claims writes an explicit NONE line.
# Runs from anywhere - it locates itself. Exit 0 = pass.
set -eu

HERE=$(cd "$(dirname "$0")/.." && pwd)
cd "$HERE"

T=tools/extract-body-claims
test -x "$T" || { echo "FAIL: $T missing or not executable"; exit 1; }

out=$(cat <<'EOF' | "$T"
## Summary
The worker now retries once on an encrypted file.
- [x] Tests added
No version moves in this PR.
```
const n = 3
```
Uses the same shape already used by the upload path.
Fixes the filters.yml nesting bug.
https://example.com/ticket/1
Adds 42 tests across 3 suites.
Refactor of the helper.
EOF
)

has() { printf '%s\n' "$out" | grep -q "^$1	[^	]*	$2" || { echo "FAIL($3): expected claim at body line $1: $2"; exit 1; }; }
has 2 'The worker now retries once' C1
has 4 'No version moves' C2
has 8 'Uses the same shape already used' C3
has 9 'Fixes the filters.yml' C4
has 11 'Adds 42 tests' C5

printf '%s\n' "$out" | grep -qE '^(1|3|6|10|12)	' \
    && { echo "FAIL(P1): a heading, checkbox, code-fence line, bare link or marker-free line was extracted"; exit 1; }
printf '%s\n' "$out" | grep -q '^2	[^	]*now' \
    || { echo "FAIL(C6): the matched markers column must name what fired"; exit 1; }
printf '%s\n' "$out" | grep -q '^# TOTAL: 5 ' \
    || { echo "FAIL(C7): expected '# TOTAL: 5' claims"; exit 1; }

none=$(printf 'Refactor of the helper.\n' | "$T")
printf '%s\n' "$none" | grep -q '^# NONE:' \
    || { echo "FAIL(C8): a claim-free body must write an explicit NONE line"; exit 1; }

echo "PASS: body claims extracted with line and markers; headings, checkboxes, code, bare links and marker-free lines skipped; NONE when clear"
