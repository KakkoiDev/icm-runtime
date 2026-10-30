#!/bin/sh
# Freezes tools/check-revert-proof: R4, and specifically the both-ways shape - a test that
# passes in BOTH directions and therefore asserts nothing, while reading as coverage.
# Uses a real throwaway git repo and a trivial shell "test command", so no runtime is
# needed. Runs from the skill dir. Exit 0 = pass.
set -eu

tool="tools/check-revert-proof"
test -x "$tool" || { echo "FAIL: $tool missing or not executable"; exit 1; }
command -v git >/dev/null 2>&1 || { echo "SKIP: git not installed"; exit 0; }

tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT
repo="$tmp/repo"
mkdir -p "$repo"

git -C "$repo" init -q
git -C "$repo" config user.email t@example.com
git -C "$repo" config user.name t

# base: the source has no guard.
printf 'guard=absent\n' > "$repo/src.txt"
printf 'grep -q "guard=present" src.txt\n' > "$repo/spec.sh"
git -C "$repo" add -A
git -C "$repo" commit -qm base
base=$(git -C "$repo" rev-parse HEAD)

# fix: the guard is added. The test asserts the guard, so it must fail without it.
printf 'guard=present\n' > "$repo/src.txt"
git -C "$repo" add -A
git -C "$repo" commit -qm fix

verdict() { awk -F'\t' '$1=="verdict"{print $2; exit}' "$1"; }

# ---- 1. a real regression test: passes on the fix, fails on the revert ----
sh "$tool" --repo "$repo" --base "$base" --test 'sh spec.sh' --test-file spec.sh \
    --out "$tmp/p1.tsv" src.txt >/dev/null 2>&1 || true
[ "$(verdict "$tmp/p1.tsv")" = "PROVEN" ] \
    || { echo "FAIL: a test that fails on revert must be PROVEN, got $(verdict "$tmp/p1.tsv")"; cat "$tmp/p1.tsv"; exit 1; }

# ---- 2. an assertion that passes both ways ----
# `grep -q guard=` matches "absent" as well as "present" - exactly the way
# toHaveBeenCalledWith matches when the key it asserts is undefined on the old code.
printf 'grep -q "guard=" src.txt\n' > "$repo/spec.sh"
git -C "$repo" add -A
git -C "$repo" commit -qm "weak assertion"
sh "$tool" --repo "$repo" --base "$base" --test 'sh spec.sh' --test-file spec.sh \
    --out "$tmp/p2.tsv" src.txt >/dev/null 2>&1 || true
[ "$(verdict "$tmp/p2.tsv")" = "NOT-PROVEN(passes-on-revert)" ] \
    || { echo "FAIL: an assertion that survives the revert must be NOT-PROVEN(passes-on-revert), got $(verdict "$tmp/p2.tsv")"; cat "$tmp/p2.tsv"; exit 1; }

# ---- 3. a test that does not even pass on the fix ----
printf 'grep -q "nothing-like-this" src.txt\n' > "$repo/spec.sh"
git -C "$repo" add -A
git -C "$repo" commit -qm "broken assertion"
sh "$tool" --repo "$repo" --base "$base" --test 'sh spec.sh' --test-file spec.sh \
    --out "$tmp/p3.tsv" src.txt >/dev/null 2>&1 || true
[ "$(verdict "$tmp/p3.tsv")" = "NOT-PROVEN(fails-on-head)" ] \
    || { echo "FAIL: a test failing on the fix must be NOT-PROVEN(fails-on-head), got $(verdict "$tmp/p3.tsv")"; exit 1; }

# ---- 4. the trap that makes a proof meaningless: reverting the test with the source ----
if sh "$tool" --repo "$repo" --base "$base" --test 'sh spec.sh' --test-file spec.sh \
        --out "$tmp/p4.tsv" src.txt spec.sh >/dev/null 2>&1; then
    echo "FAIL: passing the test file in the reverted source list must be refused"; exit 1
fi

# ---- 5. a non-zero exit accompanies every NOT-PROVEN, so a caller cannot ignore it ----
if sh "$tool" --repo "$repo" --base "$base" --test 'sh spec.sh' --test-file spec.sh \
        --out "$tmp/p5.tsv" src.txt >/dev/null 2>&1; then
    echo "FAIL: a NOT-PROVEN result must exit non-zero"; exit 1
fi

# ---- 6. the tracked tree is left exactly as it was ----
[ "$(git -C "$repo" status --porcelain)" = "" ] \
    || { echo "FAIL: the tool must not modify the tracked tree"; git -C "$repo" status --short; exit 1; }
[ "$(git -C "$repo" worktree list | awk 'END{print NR}')" = 1 ] \
    || { echo "FAIL: the throwaway worktree must be removed"; git -C "$repo" worktree list; exit 1; }

echo ok
