#!/bin/sh
# Held-out check for the changed-value breakage guarantee (the dual of dead-code).
#
# Born from the SOBA-265 / PR #24198 A/B: the skill deleted a dead i18n key but MISSED
# a latent E2E break - an existing test asserted the Japanese value the PR stopped
# rendering (balance.spec.ts asserts 原価 via Label.COST_PRICE). The review agent caught
# it by reading the e2e tree; the skill had no mechanism to. gather-impact is that
# mechanism; this check locks it so a future edit can't silently regress it.
#
# NOT a tautology: it runs the tool against a FROZEN offline fixture with a known answer
# (no gh, no network, no live repo). It asserts the RESOLUTION ran (value present, not just
# "a file was written"), the TEST-TREE-SCOPED grep found the real consumer, the precision
# filter held (a non-i18n literal is NOT emitted), and CLEARED is distinguished from
# NOT-SEARCHED. Fails on the two known bad reverts:
#   - resolve keys by a naive ns->filename transform / skip resolution  -> A1 fails
#   - grep the whole repo instead of scoping to the test tree           -> A2/A3 drift
# Runs from the skill dir (or anywhere - it locates itself). Exit 0 = pass.
set -eu

HERE=$(cd "$(dirname "$0")/.." && pwd)
cd "$HERE"

TOOL=tools/gather-impact
FIX=eval/fixtures/changed-literal
test -x "$TOOL" || { echo "FAIL: $TOOL missing or not executable"; exit 1; }
test -f "$FIX/pr.diff" || { echo "FAIL: fixture diff $FIX/pr.diff missing"; exit 1; }
test -d "$FIX/repo" || { echo "FAIL: fixture repo $FIX/repo missing"; exit 1; }

OUT=$(mktemp -d); trap 'rm -rf "$OUT"' EXIT
sh "$TOOL" "$FIX/pr.diff" "$OUT" "$FIX/repo" >/dev/null 2>&1 || { echo "FAIL: gather-impact exited non-zero"; exit 1; }
R="$OUT/impact.md"
test -s "$R" || { echo "FAIL: impact.md not written"; exit 1; }

# A1 - resolution ran: the removed key 'Cost price' was resolved to its dict VALUE 原価.
#      (A file merely written, or a name-transform resolver that finds nothing, fails here.)
grep -q '原価' "$R" || { echo "FAIL(A1): resolved value 原価 absent - key->value resolution did not run"; exit 1; }

# A2 - test-tree-scoped grep found the REAL consumer (the alias constant an e2e spec uses).
grep -Eq 'constants\.ts:[0-9]+:.*原価' "$R" \
    || { echo "FAIL(A2): consumer tests/e2e/constants.ts not listed for 原価 - scoped grep missed it"; exit 1; }

# A3 - the consumer is a TEST-TREE file, not the dictionary itself. A whole-repo grep
#      (the bad revert) would also list the dict source; scoping must exclude it.
if grep -E ':[0-9]+:' "$R" | grep -q 'balance-management.ts'; then
    echo "FAIL(A3): dictionary source listed as a consumer - grep was not scoped to the test tree"; exit 1
fi

# A4 - precision / negative control: a non-i18n literal ("Save", changed outside t())
#      must NOT be emitted as a value.
grep -q 'Save' "$R" && { echo "FAIL(A4): non-i18n literal 'Save' leaked into impact - precision filter broken"; exit 1; }

# A5 - CLEARED is distinguished from NOT-SEARCHED: the removed value 孤独 (no test
#      consumer) yields an explicit 0-consumers CLEAR line, not silence.
awk '/value: "孤独"/{f=1} f&&/0 consumers/{ok=1} END{exit ok?0:1}' "$R" \
    || { echo "FAIL(A5): 孤独 has no explicit '0 consumers' clear line - cannot tell CLEARED from NOT-SEARCHED"; exit 1; }

echo "ok: changed-value impact (resolution + test-tree scope + precision + clear/not-searched)"
