#!/bin/sh
# Regression test for tools/discussion-coverage.
#
# The incident: `notion-get-comments` returned `total-count="24" shown-count="8"`
# and the read was treated as complete. Sixteen threads went unread. A finding was
# then published as "still unanswered" when the owner had answered it in the same
# thread four hours below the comment that was read.
#
# What this locks down is that a partial harvest CANNOT exit 0, in both the ways a
# harvest can be partial: fewer blocks than declared, and a thread the body points
# at that was never fetched. Also that a clean harvest does exit 0, since a check
# that fails on everything gets disabled by whoever is in a hurry.
set -eu

here=$(cd "$(dirname "$0")/.." && pwd)
tool="$here/tools/discussion-coverage"
work=$(mktemp -d)
trap 'rm -rf "$work"' EXIT INT TERM

D1=discussion://3a01ff99-6922-81f8-ac7c-c0e9c98f9ab9/71e729c8-cce9-46bc-92d5-8a5d1b76914e/3a51ff99-6922-80a5-88b5-001ca1df8773
D2=discussion://3a01ff99-6922-81f8-ac7c-c0e9c98f9ab9/a7b0afe8-0534-4d19-856d-81d63a16584c/3a51ff99-6922-8009-9850-001c19863299

mk_body() {
    printf '%s\n' \
        "- [ ] <span discussion-urls=\"$D1\">AC one</span>" \
        "- [ ] <span discussion-urls=\"$D2\">AC two</span>" \
        > "$work/body.md"
}

mk_disc() {
    printf 'Declared: %s\n' "$1" > "$work/disc.md"
    shift
    for d in "$@"; do
        printf '<discussion id="%s" comment-count="1" resolved="false">\n' "$d" >> "$work/disc.md"
        printf '<comment id="c1" user-url="user://u1" datetime="2026-07-22T00:00:00.000Z">text</comment>\n' >> "$work/disc.md"
        printf '</discussion>\n' >> "$work/disc.md"
    done
}

fail=0
check() {
    if [ "$1" = "$2" ]; then
        printf '  ok: %s\n' "$3"
    else
        printf '  FAIL: %s (got exit %s, expected %s)\n' "$3" "$1" "$2"
        fail=1
    fi
}

mk_body

# 1. the incident shape: declared 24, harvested 2
mk_disc 24 "$D1" "$D2"
set +e; "$tool" "$work/disc.md" "$work/body.md" >"$work/out1" 2>&1; rc=$?; set -e
check "$rc" 1 "declared 24 / harvested 2 is rejected"
grep -q 'partial' "$work/out1" || { echo "  FAIL: no 'partial' in the message"; fail=1; }

# 2. counts agree but a body-anchored thread was never fetched
mk_disc 1 "$D1"
set +e; "$tool" "$work/disc.md" "$work/body.md" >"$work/out2" 2>&1; rc=$?; set -e
check "$rc" 1 "count-consistent harvest missing a body-anchored thread is rejected"
grep -qF "$D2" "$work/out2" || { echo "  FAIL: the missing thread id is not named"; fail=1; }

# 3. no Declared header at all - there is nothing to check against
mk_disc 2 "$D1" "$D2"
grep -v '^Declared:' "$work/disc.md" > "$work/nodecl.md"
set +e; "$tool" "$work/nodecl.md" "$work/body.md" >"$work/out3" 2>&1; rc=$?; set -e
check "$rc" 1 "a harvest with no 'Declared: N' line is rejected"

# 4. lowering Declared to match a short harvest must NOT buy a pass: the body-span
#    check is independent of the declared number and still catches it.
mk_disc 1 "$D1"
set +e; "$tool" "$work/disc.md" "$work/body.md" >"$work/out4" 2>&1; rc=$?; set -e
check "$rc" 1 "faking Declared down to the harvested count is still rejected"

# 5. a genuinely complete harvest passes
mk_disc 2 "$D1" "$D2"
set +e; "$tool" "$work/disc.md" "$work/body.md" >"$work/out5" 2>&1; rc=$?; set -e
check "$rc" 0 "a complete harvest passes"
grep -q '^ok: harvest complete' "$work/out5" || { echo "  FAIL: no 'ok: harvest complete' line"; fail=1; }

# 6. duplicate harvest of the same thread must not inflate past Declared. Isolated
#    against a one-thread body so the over-count is the ONLY reason it can fail.
printf '%s\n' "- [ ] <span discussion-urls=\"$D1\">AC one</span>" > "$work/body1.md"
mk_disc 1 "$D1" "$D1"
set +e; "$tool" "$work/disc.md" "$work/body1.md" >"$work/out6" 2>&1; rc=$?; set -e
check "$rc" 1 "harvesting one thread twice past the declared count is rejected"
grep -q 'harvested 2 but declared only 1' "$work/out6" || { echo "  FAIL: over-count not diagnosed"; fail=1; }

[ "$fail" -eq 0 ] || { echo "FAIL: discussion-coverage regressions"; exit 1; }
echo ok
