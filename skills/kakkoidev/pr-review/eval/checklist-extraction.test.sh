#!/bin/sh
# Deterministic eval: tools/extract-checklist parses a PR body's task-list into
# `state <TAB> item` rows. Frozen ratchet for the checklist-audit miss (#24370):
# if the parse regresses, this fails offline via `icm.sh eval`. Runs from the skill
# dir. Exit 0 = pass.
set -eu

TOOL=tools/extract-checklist
FIX=eval/fixtures/checklist/body.md
test -x "$TOOL" || { echo "FAIL: $TOOL missing or not executable"; exit 1; }
test -f "$FIX" || { echo "FAIL: fixture $FIX missing"; exit 1; }

out=$("$TOOL" < "$FIX")
TAB=$(printf '\t')

# Exactly 6 checkboxes (2 not-a-checkbox bullets excluded; nested child included).
n=$(printf '%s\n' "$out" | grep -c . || true)
[ "$n" -eq 6 ] || { echo "FAIL: expected 6 checklist rows, got $n"; printf '%s\n' "$out"; exit 1; }

expect_row() {
  printf '%s\n' "$out" | grep -Fqx "$1" || { echo "FAIL: missing row: $(printf '%s' "$1" | tr "$TAB" '|')"; printf '%s\n' "$out"; exit 1; }
}
expect_row "checked${TAB}Unit tests"
expect_row "unchecked${TAB}Code has JSDoc."
expect_row "unchecked${TAB}Endpoints secured (RBAC)."
expect_row "checked${TAB}Alt-marker, upper-case X, checked"
expect_row "unchecked${TAB}Nested parent"
expect_row "unchecked${TAB}Nested child under a checkbox"

# A non-checkbox bullet must never appear.
printf '%s\n' "$out" | grep -q 'regular bullet' && { echo "FAIL: a non-checkbox bullet was extracted"; exit 1; }

echo "ok: extract-checklist parsed 6 rows with correct state + text"
