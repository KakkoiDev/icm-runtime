#!/bin/sh
# Regression test for tools/commitment-scan.
#
# Locks down the promise-ledger enumeration and three defects found by running it:
#   1. "ill be" matched inside "will be".
#   2. "i will" matched inside "UI will" - the same bug one layer deeper, and the
#      reason the fix is word-boundary matching rather than deleting one marker.
#      A tamper test that only removed "ill be" passed while the tool was still
#      broken, which is how (2) was found at all.
#   3. The comment open tag's own closing ">" leaked into the extracted text, so
#      every sentence came out prefixed with ">".
# Plus the property that actually matters: an owner promise to edit the document is
# found, and a polite "let me know" is not mistaken for one.
set -eu

here=$(cd "$(dirname "$0")/.." && pwd)
tool="$here/tools/commitment-scan"
work=$(mktemp -d)
trap 'rm -rf "$work"' EXIT INT TERM

cat > "$work/disc.md" <<'EOF'
Declared: 3
<discussion id="discussion://aaaaaaaa-0000-0000-0000-000000000001/bbbbbbbb-0000-0000-0000-000000000002/cccccccc-0000-0000-0000-000000000003" comment-count="2" resolved="false">
<comment id="c1" user-url="user://reviewer1" datetime="2026-07-22T05:00:00.000Z">Can you clarify the rounding basis? Let me know if this reads clearly.</comment>
<comment id="c2" user-url="user://owner1" datetime="2026-07-23T09:00:00.000Z">Good catch. I'll state "tax code" explicitly in the AC.</comment>
</discussion>
<discussion id="discussion://aaaaaaaa-0000-0000-0000-000000000001/bbbbbbbb-0000-0000-0000-000000000004/cccccccc-0000-0000-0000-000000000005" comment-count="1" resolved="false">
<comment id="c3" user-url="user://owner1" datetime="2026-07-28T00:00:00.000Z">The editing UI will be handled by US-05 and the dependency will be added there.</comment>
</discussion>
<discussion id="discussion://aaaaaaaa-0000-0000-0000-000000000001/bbbbbbbb-0000-0000-0000-000000000006/cccccccc-0000-0000-0000-000000000007" comment-count="1" resolved="false">
<comment id="c4" user-url="user://owner1" datetime="2026-07-30T01:00:00.000Z">A correction. I said we would change the US-06 criterion. That was wrong, the restriction stays.</comment>
</discussion>
<discussion id="discussion://aaaaaaaa-0000-0000-0000-000000000001/bbbbbbbb-0000-0000-0000-000000000008/cccccccc-0000-0000-0000-000000000009" comment-count="1" resolved="false">
<comment id="c5" user-url="user://reviewer1" datetime="2026-07-29T00:00:00.000Z">The UI will look different once the form lands, and the bill be sent separately.</comment>
</discussion>
EOF

"$tool" "$work/disc.md" > "$work/out" 2>"$work/err" || {
    echo "FAIL: tool exited non-zero"; cat "$work/err"; exit 1; }

fail=0
want() {
    grep -qF "$1" "$work/out" || { printf '  FAIL: expected to find %s\n' "$1"; fail=1; }
}
reject() {
    grep -qF "$1" "$work/out" && { printf '  FAIL: should not contain %s\n' "$1"; fail=1; } || :
}

# --- the promise is found, attributed to the right comment
want "I'll state"
want "c2"

# --- defects 1 and 2: a sentence containing "UI will" / "will be" / "bill be" and
#     no first-person promise must not be reported at all. c5 is exactly that
#     sentence. Asserting on the comment id rather than on one marker string is what
#     makes this catch the whole substring-matching class instead of one instance.
awk '/^## Commitments/{p=1} /^## Self-corrections/{p=0} p' "$work/out" \
    | grep -q '	c5	' && { echo "  FAIL: 'The UI will look different...' reported as a promise (substring matching regressed)"; fail=1; } || :

# --- no first-person marker may be attributed to c3, whose only promise is the
#     third-person "the dependency will be added there"
awk '/^## Commitments/{p=1} /^## Self-corrections/{p=0} p' "$work/out" \
    | grep '	c3	' | grep -qE "	(i'll|i will|ill be)	" \
    && { echo "  FAIL: a first-person marker matched inside 'UI will' / 'will be'"; fail=1; } || :

# --- defect 3: no leaked ">" prefix on any extracted sentence
if grep -E '^[^	]*	[^	]*	[^	]*	[^	]*	[^	]*	>' "$work/out" >/dev/null 2>&1; then
    echo "  FAIL: an extracted sentence still starts with a leaked '>'"; fail=1
fi

# --- "Let me know if this reads clearly" is courtesy, not a promise to edit
reject "Let me know if this reads clearly"

# --- the reversal lands in its own section, not among the commitments
awk '/^## Self-corrections/{p=1} p' "$work/out" | grep -qF "A correction" || {
    echo "  FAIL: the self-correction is not in the ## Self-corrections section"; fail=1; }
awk '/^## Commitments/{p=1} /^## Self-corrections/{p=0} p' "$work/out" \
    | grep -qF "A correction" && { echo "  FAIL: the self-correction leaked into ## Commitments"; fail=1; } || :

# --- counts are reported so a stage can assert every row got a disposition
grep -qE '^Commitments: [0-9]+$' "$work/out" || { echo "  FAIL: no 'Commitments: N' summary"; fail=1; }
grep -qE '^Self-corrections: [0-9]+$' "$work/out" || { echo "  FAIL: no 'Self-corrections: N' summary"; fail=1; }

# --- an empty harvest must not crash and must say so rather than silently pass
printf 'Declared: 0\n' > "$work/empty.md"
"$tool" "$work/empty.md" > "$work/out-empty" 2>&1 || { echo "  FAIL: empty input errored"; fail=1; }
grep -q '^Commitments: 0$' "$work/out-empty" || { echo "  FAIL: empty input did not report 0 commitments"; fail=1; }

[ "$fail" -eq 0 ] || { echo "FAIL: commitment-scan regressions"; exit 1; }
echo ok
