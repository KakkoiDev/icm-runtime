#!/bin/sh
# Freezes the gather-impact root guard: the tool refuses a repo root the diff does not
# belong to, instead of inventorying that tree and printing a clean values=0.
#
# Born from the 2026-08-17 run: stage 03 called the tool with no repo-root, so the
# `git rev-parse --show-toplevel` default resolved to the REVIEWER's own repo (in an ICM
# run the cwd is the run dir), and impact.md reported a repo root plus a test-file count
# for a tree whose files the diff never touches. That reads as evidence and is a false
# clear - the worst failure for a tool whose only job is catching a missed breakage.
#
# Cases: a root the diff does not belong to -> non-zero, a message naming the resolved
# root and an unfound diff path, and NO impact.md; the real checkout -> still scans
# (the guard is path-based, not a blanket refusal); deletion-only and add-only diffs ->
# checked via the file's directory (their content is absent at a base checkout), so
# neither is an exemption and neither false-refuses its own repo.
# Runs from the skill dir (or anywhere - it locates itself). Exit 0 = pass.
set -eu

HERE=$(cd "$(dirname "$0")/.." && pwd)
cd "$HERE"

TOOL=tools/gather-impact
test -x "$TOOL" || { echo "FAIL: $TOOL missing or not executable"; exit 1; }

tmp=$(mktemp -d); trap 'rm -rf "$tmp"' EXIT
mkdir -p "$tmp/repo/apps/server/src/orders" "$tmp/elsewhere/lib"
: > "$tmp/repo/apps/server/src/orders/order.service.ts"

cat > "$tmp/pr.diff" <<'EOF'
diff --git a/apps/server/src/orders/order.service.ts b/apps/server/src/orders/order.service.ts
--- a/apps/server/src/orders/order.service.ts
+++ b/apps/server/src/orders/order.service.ts
@@ -1,3 +1,2 @@
 context
-  label: t('orders:archived'),
 keep()
EOF

# G1 - a root the diff does not belong to is refused, loudly and non-zero.
if out=$(sh "$TOOL" "$tmp/pr.diff" "$tmp/out-wrong" "$tmp/elsewhere" 2>&1); then
    echo "FAIL(G1): gather-impact exited 0 on a root the diff does not belong to"
    printf '%s\n' "$out"; exit 1
fi
printf '%s\n' "$out" | grep -Fq "$tmp/elsewhere" \
    || { echo "FAIL(G1): the refusal does not name the resolved root"; printf '%s\n' "$out"; exit 1; }
printf '%s\n' "$out" | grep -Fq 'apps/server/src/orders/order.service.ts' \
    || { echo "FAIL(G1): the refusal names no example diff path that was not found"; printf '%s\n' "$out"; exit 1; }
if [ -f "$tmp/out-wrong/impact.md" ]; then
    echo "FAIL(G1): impact.md was written for the wrong tree - that is the false clear this guard exists to stop"; exit 1
fi

# G2 - the guard is path-based: the checkout the diff DOES belong to still scans.
sh "$TOOL" "$tmp/pr.diff" "$tmp/out-right" "$tmp/repo" >/dev/null 2>&1 \
    || { echo "FAIL(G2): gather-impact refused the checkout the diff belongs to"; exit 1; }
test -s "$tmp/out-right/impact.md" \
    || { echo "FAIL(G2): impact.md not written for the correct root"; exit 1; }

# G3 - deletion-only diff: the removed file cannot exist at head, so the witness is the
# directory that held it - present in the real checkout, absent in the unrelated tree.
cat > "$tmp/del.diff" <<'EOF'
diff --git a/apps/server/src/orders/order.service.ts b/apps/server/src/orders/order.service.ts
deleted file mode 100644
--- a/apps/server/src/orders/order.service.ts
+++ /dev/null
@@ -1,2 +0,0 @@
-  label: t('orders:archived'),
-keep()
EOF
sh "$TOOL" "$tmp/del.diff" "$tmp/out-del" "$tmp/repo" >/dev/null 2>&1 \
    || { echo "FAIL(G3): a deletion-only diff was refused against its own checkout"; exit 1; }
if sh "$TOOL" "$tmp/del.diff" "$tmp/out-del-wrong" "$tmp/elsewhere" >/dev/null 2>&1; then
    echo "FAIL(G3): a deletion-only diff scanned an unrelated tree - deletions are not an exemption"; exit 1
fi

# G4 - add-only diff: the created file is absent from a checkout sitting on the base commit,
# so the same directory witness applies - the guard must not refuse the PR's own repo.
cat > "$tmp/add.diff" <<'EOF'
diff --git a/apps/server/src/orders/archive.service.ts b/apps/server/src/orders/archive.service.ts
new file mode 100644
--- /dev/null
+++ b/apps/server/src/orders/archive.service.ts
@@ -0,0 +1,2 @@
+export const archive = () => null
+keep()
EOF
sh "$TOOL" "$tmp/add.diff" "$tmp/out-add" "$tmp/repo" >/dev/null 2>&1 \
    || { echo "FAIL(G4): an add-only diff was refused against its own checkout (file absent at base is expected)"; exit 1; }
if sh "$TOOL" "$tmp/add.diff" "$tmp/out-add-wrong" "$tmp/elsewhere" >/dev/null 2>&1; then
    echo "FAIL(G4): an add-only diff scanned an unrelated tree"; exit 1
fi

echo "ok: gather-impact refuses a root the diff does not belong to (modified, deletion-only, add-only) and still scans the right one"
