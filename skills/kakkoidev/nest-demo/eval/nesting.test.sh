#!/bin/sh
# End-to-end nesting test against the REAL nest-demo + nest-demo-child skills.
# A parent run invokes a child run via --caller; the parent's publish gate is
# suspended while the child is open (so the child's legitimate publish is
# allowed), and resumes when the child closes. Exercises icm.sh init/gate-check/
# stage-done through a real nested init sequence, not constructed run dirs.
# Runs from the skill dir. Exit 0 = pass.
set -eu

ICM=$(cd ../../icm/runtime 2>/dev/null && pwd)/icm.sh
[ -f "$ICM" ] || { echo "FAIL: icm.sh not found at ../../icm/runtime/icm.sh"; exit 1; }

TMP=$(mktemp -d); trap 'rm -rf "$TMP"' EXIT
cd "$TMP"
fail() { echo "FAIL: $1"; exit 1; }

P=$(sh "$ICM" init kakkoidev/nest-demo 2>/dev/null) || fail "parent init"
pts=$(basename "$P")

# Baseline: parent's publish gate fails (no parent-evidence yet) -> DENY.
rc=0; out=$(sh "$ICM" gate-check --tool publish 2>&1) || rc=$?
{ [ "$rc" -eq 1 ] && printf '%s' "$out" | grep -q "DENY kakkoidev/nest-demo"; } \
    || fail "baseline: parent publish gate should deny (rc=$rc out=$out)"

# Delegate: child run invoked by the parent; child produces its evidence so its
# own gate passes.
C=$(sh "$ICM" init kakkoidev/nest-demo-child --caller "kakkoidev/nest-demo/$pts/01-delegate" 2>/dev/null) || fail "child init"
printf 'child did the work\n' > "$C/01-produce/output/child-evidence.md"

# While the child is open, the parent's gate is SUSPENDED -> child's publish allowed.
rc=0; out=$(sh "$ICM" gate-check --tool publish 2>&1) || rc=$?
{ [ "$rc" -eq 0 ] && [ -z "$out" ]; } \
    || fail "child open: parent gate should be suspended, publish allowed (rc=$rc out=$out)"

# gate-status agrees with enforcement: not BLOCKING while the parent is suspended.
st=$(sh "$ICM" gate-status 2>&1) || true
printf '%s' "$st" | grep -q "STATE: BLOCKING" \
    && fail "gate-status should not report BLOCKING while parent suspended: $st"
:

# Close the child -> the parent's gate resumes -> DENY again.
sh "$ICM" stage-done kakkoidev/nest-demo-child --stage 01-produce >/dev/null 2>&1 || fail "child stage-done"
rc=0; out=$(sh "$ICM" gate-check --tool publish 2>&1) || rc=$?
{ [ "$rc" -eq 1 ] && printf '%s' "$out" | grep -q "DENY kakkoidev/nest-demo"; } \
    || fail "child closed: parent gate should resume and deny (rc=$rc out=$out)"

# Parent satisfies its own precondition -> publish allowed.
printf 'parent evidence\n' > "$P/01-delegate/output/parent-evidence.md"
rc=0; out=$(sh "$ICM" gate-check --tool publish 2>&1) || rc=$?
{ [ "$rc" -eq 0 ] && [ -z "$out" ]; } \
    || fail "parent ready: publish should be allowed (rc=$rc out=$out)"

echo ok
