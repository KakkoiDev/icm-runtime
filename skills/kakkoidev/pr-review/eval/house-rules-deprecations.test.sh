#!/bin/sh
# Held-out check for the two house-standards dimensions.
#
# Born from meetsone PR #25350: the review's dimensions were all generic, so two whole
# classes of finding had no mechanism behind them. First, the repo writes down its own
# standards - a guidelines tree, decision records, a contributor guide - and a review
# that never opens them audits against the reviewer's taste. Second, the diff's new
# handlers took a decorator whose own definition says "use the context one instead";
# nothing in the pipeline looked at a definition site to notice.
#
# NOT a tautology: both tools run against a FROZEN offline fixture with a known answer
# (no gh, no network, no live repo). It asserts discovery is complete AND scoped
# (a vendored doc under node_modules is not a house rule), that the relevance hint is
# emitted without becoming a filter, that a real deprecated symbol is found at its
# definition with its replacement note, and - the precision half - that a deprecated
# private member with a generic name does NOT produce a finding.
# Fails on the known bad reverts:
#   - discover docs by a bare `find -name '*.md'` without excluding vendored trees -> B2
#   - resolve declarations with the BSD-broken sed interval, or accept a bare `name(`
#     line as a declaration                                                        -> C1/C3
# Runs from anywhere - it locates itself. Exit 0 = pass.
set -eu

HERE=$(cd "$(dirname "$0")/.." && pwd)
cd "$HERE"

HR=tools/gather-house-rules
DEP=tools/gather-deprecations
FIX=eval/fixtures/house-rules
test -x "$HR" || { echo "FAIL: $HR missing or not executable"; exit 1; }
test -x "$DEP" || { echo "FAIL: $DEP missing or not executable"; exit 1; }
test -f "$FIX/pr.diff" || { echo "FAIL: fixture diff $FIX/pr.diff missing"; exit 1; }
test -d "$FIX/repo" || { echo "FAIL: fixture repo $FIX/repo missing"; exit 1; }

OUT=$(mktemp -d); trap 'rm -rf "$OUT"' EXIT

# ------------------------------------------------------------------ house rules
sh "$HR" "$FIX/pr.diff" "$OUT" "$FIX/repo" >/dev/null 2>&1 \
    || { echo "FAIL: gather-house-rules exited non-zero"; exit 1; }
R="$OUT/house-rules.tsv"
test -s "$R" || { echo "FAIL: house-rules.tsv not written"; exit 1; }

# B1 - the guideline, the decision record and the contributor guide are all discovered.
for want in docs/guidelines/api/api-types.md docs/architecture-decisions/0001-explicit-tenant.md CONTRIBUTING.md; do
    grep -q "^$want	" "$R" \
        || { echo "FAIL(B1): $want not discovered - the audit cannot cite a doc it never listed"; exit 1; }
done

# B2 - discovery is SCOPED: a dependency's own guidelines are not this repo's standards.
grep -q 'node_modules' "$R" \
    && { echo "FAIL(B2): a vendored node_modules doc was listed as a house rule"; exit 1; }

# B3 - the relevance hint is emitted, and the api guideline is hinted from the diff's
#      own paths (an .dto.ts / controller change). A hint, never a filter: every row
#      still has to be accounted for, which is why the totals line says so.
grep -q '^docs/guidelines/api/api-types.md	.*	likely	' "$R" \
    || { echo "FAIL(B3): api guideline not marked likely - relevance hint did not compute"; exit 1; }
grep -q '^# TOTAL: .* documents discovered' "$R" \
    || { echo "FAIL(B3): totals line absent - a skipped doc could pass as an audited one"; exit 1; }

# B4 - an empty discovery says so explicitly, so "no rows" can never read as "clean".
EMPTY=$(mktemp -d); mkdir -p "$EMPTY/repo"
sh "$HR" "$FIX/pr.diff" "$EMPTY/out" "$EMPTY/repo" >/dev/null 2>&1 \
    || { echo "FAIL(B4): gather-house-rules failed on a repo with no docs"; rm -rf "$EMPTY"; exit 1; }
grep -q '^# NONE:' "$EMPTY/out/house-rules.tsv" \
    || { echo "FAIL(B4): no explicit NONE marker when nothing was discovered"; rm -rf "$EMPTY"; exit 1; }
rm -rf "$EMPTY"

# ----------------------------------------------------------------- deprecations
sh "$DEP" "$FIX/pr.diff" "$OUT" "$FIX/repo" >/dev/null 2>&1 \
    || { echo "FAIL: gather-deprecations exited non-zero"; exit 1; }
D="$OUT/deprecations.tsv"
test -s "$D" || { echo "FAIL: deprecations.tsv not written"; exit 1; }

# C1 - the deprecated symbol the diff uses is found, at its DEFINITION site.
grep -q '^LegacyUser	src/auth/legacy-user.decorator.ts:[0-9]' "$D" \
    || { echo "FAIL(C1): LegacyUser not resolved to its definition - declaration extraction broke"; exit 1; }

# C2 - the note travels with it, so the fix names the replacement instead of "don't use this".
grep -q 'Use .*@Context()' "$D" \
    || { echo "FAIL(C2): the deprecation note (naming the replacement) was not carried"; exit 1; }

# C3 - precision, guard 1 (the generic-name stoplist): a deprecated member named `rows`
#      is not a finding. The diff contains `const rows = [1, 2, 3]`; matching that on the
#      strength of a shared common noun would be pure noise.
grep -q '^rows	' "$D" \
    && { echo "FAIL(C3): generic member 'rows' reported - the stoplist guard regressed"; exit 1; }

# C3b - precision, guard 2 (a bare `name(` line is only a declaration after an access
#       modifier): the marker above an object-literal method shorthand must not resolve.
#       Reverting that one guard alone makes `toPayload` appear here, so this assertion
#       fails on revert independently of the stoplist above.
#       Cost of the guard, accepted and documented in the tool header: a deprecated
#       object-literal method the diff really does call is a recall miss.
grep -q '^toPayload	' "$D" \
    && { echo "FAIL(C3b): object-literal shorthand accepted as a declaration - the modifier guard regressed"; exit 1; }

# C4 - a clean diff records a SEARCHED-and-clear result, distinct from not-checked.
CLEAN=$(mktemp -d)
printf '+++ b/src/feature/other.ts\n+export const x = 1\n' > "$CLEAN/pr.diff"
sh "$DEP" "$CLEAN/pr.diff" "$CLEAN/out" "$FIX/repo" >/dev/null 2>&1 \
    || { echo "FAIL(C4): gather-deprecations failed on a clean diff"; rm -rf "$CLEAN"; exit 1; }
grep -q '^# CLEAR:' "$CLEAN/out/deprecations.tsv" \
    || { echo "FAIL(C4): no explicit CLEAR marker - an unchecked run would look identical"; rm -rf "$CLEAN"; exit 1; }
rm -rf "$CLEAN"

echo "PASS: house-rules discovery scoped + accounted; deprecation use sites resolved with notes, generic members excluded"
