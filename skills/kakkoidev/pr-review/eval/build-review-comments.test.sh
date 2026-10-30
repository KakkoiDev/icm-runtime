#!/bin/sh
# Held-out check for the inline-review anchoring guarantee.
#
# The miss this freezes: a review comment posted to the WRONG line because a line number
# was read as a diff-body offset instead of the new-file source line (hit live, first pass).
# build-review-comments resolves a quoted snippet to its real RIGHT-side line, so the fix is
# structural. This runs the tool against a FROZEN offline fixture with a known answer.
#
# The fixture's first hunk starts at +10, so the target line "const target = compute()" is
# NEW-FILE line 12 but only the 3rd line of the diff body. A naive offset counter yields 3;
# correct snippet resolution yields 12. Asserting 12 is the freeze. Also: a new-file line
# resolves, and a snippet absent from the diff lands in unanchored.tsv (never silently posted).
# Runs from the skill dir (or anywhere; it locates itself). Exit 0 = pass.
set -eu

HERE=$(cd "$(dirname "$0")/.." && pwd)
cd "$HERE"

TOOL=tools/build-review-comments
FIX=eval/fixtures/review-comments
test -x "$TOOL" || { echo "FAIL: $TOOL missing or not executable"; exit 1; }
test -f "$FIX/pr.diff" || { echo "FAIL: fixture $FIX/pr.diff missing"; exit 1; }
test -f "$FIX/comments.ndjson" || { echo "FAIL: fixture $FIX/comments.ndjson missing"; exit 1; }
command -v jq >/dev/null 2>&1 || { echo "FAIL: jq not found"; exit 1; }

OUT=$(mktemp -d); trap 'rm -rf "$OUT"' EXIT
sh "$TOOL" "$FIX/pr.diff" "$FIX/comments.ndjson" "$OUT" >/dev/null 2>&1 \
  || { echo "FAIL: build-review-comments exited non-zero"; exit 1; }
J="$OUT/review-comments.json"
U="$OUT/unanchored.tsv"
test -s "$J" || { echo "FAIL: review-comments.json not written"; exit 1; }

# A1 - exactly the 2 resolvable comments anchored (the 3rd is unanchorable).
n=$(jq 'length' "$J")
[ "$n" = "2" ] || { echo "FAIL(A1): expected 2 anchored comments, got $n"; exit 1; }

# A2 - THE FREEZE: the foo.ts target resolves to NEW-FILE line 12, not diff-offset 3.
line=$(jq -r '.[] | select(.path=="src/foo.ts") | .line' "$J")
[ "$line" = "12" ] || { echo "FAIL(A2): src/foo.ts must anchor to line 12 (source line), got '$line' (offset bug if 3)"; exit 1; }

# A3 - side is RIGHT and body carried through.
side=$(jq -r '.[] | select(.path=="src/foo.ts") | .side' "$J")
[ "$side" = "RIGHT" ] || { echo "FAIL(A3): side must be RIGHT, got '$side'"; exit 1; }

# A4 - a new file resolves too (bar.ts line 2).
bl=$(jq -r '.[] | select(.path=="src/bar.ts") | .line' "$J")
[ "$bl" = "2" ] || { echo "FAIL(A4): src/bar.ts must anchor to line 2, got '$bl'"; exit 1; }

# A5 - the absent snippet is SURFACED in unanchored.tsv, never silently dropped or mis-posted.
test -f "$U" || { echo "FAIL(A5): unanchored.tsv not written"; exit 1; }
grep -q 'this line is nowhere in the diff' "$U" \
  || { echo "FAIL(A5): unresolvable snippet not surfaced in unanchored.tsv"; exit 1; }
# and it must NOT have leaked into the posted payload.
if jq -e '.[] | select(.body | test("must land in unanchored"))' "$J" >/dev/null 2>&1; then
  echo "FAIL(A5): an unanchorable comment leaked into the posted payload"; exit 1
fi

echo "ok"
