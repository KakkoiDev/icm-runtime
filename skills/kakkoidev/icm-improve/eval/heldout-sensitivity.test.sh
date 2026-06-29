#!/bin/sh
# heldout-sensitivity.test.sh -- the held-out check must read the run's PRODUCED
# output via ICM_RUN_DIR, and a different output must yield a different result.
# This is the regression test for the inert-canary bug: pre-fix `cmd_heldout`
# took <candidate-dir> <phase-dir> and read no run output, so it returned the
# same result regardless of output. It FAILS on pre-fix code (which produces
# "0 passed, 0 failed" here and never sets ICM_RUN_DIR). Runs from the skill dir.
set -eu

SCRIPT="scripts/icm-improve.sh"
[ -f "$SCRIPT" ] || { echo "FAIL: $SCRIPT not found (run from the skill dir)"; exit 1; }

TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT

# Fixture held-out test: records the ICM_RUN_DIR it was given, then asserts the
# produced receipt's last line is exactly VERIFIED: PASS.
mkdir -p "$TMP/tests"
cat > "$TMP/tests/verdict.test.sh" <<'EOF'
#!/bin/sh
set -eu
[ -n "${ICM_RUN_DIR:-}" ] || exit 1
printf '%s\n' "$ICM_RUN_DIR" > "$ICM_RUN_DIR/sentinel.txt"
receipt=$(ls "$ICM_RUN_DIR"/[0-9]*/output/publish-receipt.md 2>/dev/null | head -1 || true)
[ -n "$receipt" ] && [ -f "$receipt" ] || exit 1
last=$(grep -v '^[[:space:]]*$' "$receipt" | tail -1)
[ "$last" = "VERIFIED: PASS" ] || exit 1
EOF

# A produced run whose receipt PASSES the contract.
RUN="$TMP/run"; mkdir -p "$RUN/03-publish/output"
printf 'sub-page: x\nVERIFIED: PASS\n' > "$RUN/03-publish/output/publish-receipt.md"
mkdir -p "$TMP/pA"
sh "$SCRIPT" held-out "$RUN" "$TMP/pA" "$TMP/tests" >/dev/null 2>&1 || true
grep -q '1 passed, 0 failed' "$TMP/pA/heldout.txt" 2>/dev/null \
    || { echo "FAIL: held-out did not run the contract test against produced output (got: $(cat "$TMP/pA/heldout.txt" 2>/dev/null || echo none))"; exit 1; }

# ICM_RUN_DIR must have been exported, pointing at the produced run dir.
[ -f "$RUN/sentinel.txt" ] || { echo "FAIL: ICM_RUN_DIR not exported to the held-out test"; exit 1; }
[ "$(cat "$RUN/sentinel.txt")" = "$(cd "$RUN" && pwd -P)" ] \
    || { echo "FAIL: ICM_RUN_DIR not set to the produced run dir"; exit 1; }

# A DIFFERENT produced output (verdict line broken) must FAIL the held-out.
RUN2="$TMP/run2"; mkdir -p "$RUN2/03-publish/output"
printf 'sub-page: x\nall good\n' > "$RUN2/03-publish/output/publish-receipt.md"
mkdir -p "$TMP/pB"
sh "$SCRIPT" held-out "$RUN2" "$TMP/pB" "$TMP/tests" >/dev/null 2>&1 || true
grep -q '0 passed, 1 failed' "$TMP/pB/heldout.txt" 2>/dev/null \
    || { echo "FAIL: held-out did not fail on a broken verdict line (got: $(cat "$TMP/pB/heldout.txt" 2>/dev/null || echo none))"; exit 1; }

echo "heldout-sensitivity.test.sh: all assertions passed"
