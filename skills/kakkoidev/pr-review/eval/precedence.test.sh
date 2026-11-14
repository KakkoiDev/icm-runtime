#!/bin/sh
# Freezes the precedence check: a diff that reorders a merge (spread order, Object.assign
# arguments) silently changes which source wins, and the review must name the old and new
# winner, flag it unless the PR states the change is intended, and ask for a regression test.
# Born from https://github.com/meetsmore/use-ai/pull/96 at a9d4e7a30108c7e27f9fac88f780849ed7c4b20c:
# `...config.attributes` moved before the run span's own keys, so runId, sessionId and
# functionId overrode what a caller passed (the reverse of before). A human reviewer caught
# it (discussion_r4562227394); pr-review did not. The PR body stated the new order only for
# the AISDKAgent metadata path, and its one test pins sessionId through that path only.
# Cases: D* the detector on the PR 96 diff and synthetic shapes; C* the findings check on
# the expected review and on reviews that drop or misstate a row; S* the stage wiring.
# Runs from anywhere - it locates itself. Exit 0 = pass.
set -eu

HERE=$(cd "$(dirname "$0")/.." && pwd)
cd "$HERE"

T=tools/detect-precedence-changes
FX=eval/fixtures/precedence
test -x "$T" || { echo "FAIL: $T missing or not executable"; exit 1; }

TMP=$(mktemp -d "${TMPDIR:-/tmp}/precedence-eval.XXXXXX")
trap 'rm -f "$TMP"/*; rmdir "$TMP"' EXIT

# D1: PR 96 - one row per run span key whose order against the spread flipped.
"$T" "$FX/pr.diff" > "$TMP/p.tsv"
for k in ai.telemetry.functionId ai.telemetry.metadata.runId ai.telemetry.metadata.sessionId; do
    grep -q "^packages/server/src/telemetry.ts	[0-9]*	object-literal	\.\.\.config\.attributes	$k	\.\.\.config\.attributes	$k$" "$TMP/p.tsv" \
        || { echo "FAIL(D1): expected row: ...config.attributes vs $k, old winner the spread, new winner the key"; cat "$TMP/p.tsv"; exit 1; }
done
grep -q '^# TOTAL: 3 ' "$TMP/p.tsv" \
    || { echo "FAIL(D2): expected exactly 3 rows on PR 96 (the test file and AISDKAgent hunks hold no reorder)"; cat "$TMP/p.tsv"; exit 1; }

# D3: no reorder - a spread added fresh, a key added after a spread that stays last.
cat > "$TMP/none.diff" <<'EOF'
diff --git a/src/a.ts b/src/a.ts
--- a/src/a.ts
+++ b/src/a.ts
@@ -1,6 +1,8 @@
 const o = {
+  ...extra,
   a: 1,
+  b: 2,
   ...rest,
 };
-const p = { x: 1 };
+const p = { x: 1, y: 2 };
EOF
"$T" "$TMP/none.diff" | grep -q '^# NONE:' \
    || { echo "FAIL(D3): an added spread or key that flips no existing pair must write NONE"; "$T" "$TMP/none.diff"; exit 1; }

# D4: single-line spread swap and Object.assign argument swap.
cat > "$TMP/inline.diff" <<'EOF'
diff --git a/src/b.ts b/src/b.ts
--- a/src/b.ts
+++ b/src/b.ts
@@ -10,2 +10,2 @@
-const cfg = { ...defaults, ...overrides };
-Object.assign(target, base, local);
+const cfg = { ...overrides, ...defaults };
+Object.assign(target, local, base);
EOF
"$T" "$TMP/inline.diff" > "$TMP/i.tsv"
grep -q '^src/b.ts	10	inline	' "$TMP/i.tsv" \
    || { echo "FAIL(D4): a reordered single-line spread must be reported as inline at its new line"; cat "$TMP/i.tsv"; exit 1; }
grep -q '^src/b.ts	11	inline	' "$TMP/i.tsv" \
    || { echo "FAIL(D5): reordered Object.assign arguments must be reported as inline"; cat "$TMP/i.tsv"; exit 1; }

# D6: shapes that flagged falsely on meetsone history - a typed literal opening on `} = {`,
# and one spread name in several literals and a destructuring of one hunk.
cat > "$TMP/fp.diff" <<'EOF'
diff --git a/src/c.ts b/src/c.ts
--- a/src/c.ts
+++ b/src/c.ts
@@ -1,24 +1,24 @@
-const merged: Base & { id: string } = {
+const merged: Base & {
+  id: string
+} = {
   ...DEFAULTS,
   id: el.id,
 }
 const one = {
   a: 1,
   ...rest,
 }
-const two = { ...rest }
+const two = {
+  ...rest,
+  a: 2,
+}
-const { portal, ...rest } = row
+const {
+  portal,
+  ...rest
+} = row
 return {
   data: { ...rest, portal },
 }
EOF
"$T" "$TMP/fp.diff" | grep -q '^# NONE:' \
    || { echo "FAIL(D6): typed-literal opener, repeated spread or destructuring rest must not flag"; "$T" "$TMP/fp.diff"; exit 1; }

# C1: the expected review of PR 96 accounts for every row.
"$T" --check "$TMP/p.tsv" "$FX/expected-findings.md" > "$TMP/c.out" 2>&1 \
    || { echo "FAIL(C1): the expected PR 96 review must pass the check"; cat "$TMP/c.out"; exit 1; }

expect_fail() {
    if "$T" --check "$TMP/p.tsv" "$TMP/f.md" > "$TMP/c.out" 2>&1; then
        echo "FAIL($1): $2"; exit 1
    fi
    grep -q "$3" "$TMP/c.out" || { echo "FAIL($1): message must name $3"; cat "$TMP/c.out"; exit 1; }
}

# C2: a review that never states one row's winners (the PR 96 miss itself).
grep -v 'metadata.runId old-winner' "$FX/expected-findings.md" > "$TMP/f.md"
expect_fail C2 'a row with no Precedence line must fail' 'ai.telemetry.metadata.runId'

# C3: a missing test with no finding.
sed 's/test=missing finding=F1/test=missing finding=none/' "$FX/expected-findings.md" > "$TMP/f.md"
expect_fail C3 'test=missing with finding=none must fail' 'finding'

# C4: winners swapped against the diff.
sed 's/functionId old-winner=\.\.\.config\.attributes new-winner=ai\.telemetry\.functionId/functionId old-winner=ai.telemetry.functionId new-winner=...config.attributes/' \
    "$FX/expected-findings.md" > "$TMP/f.md"
expect_fail C4 'winners that contradict the diff must fail' 'winner'

# C5: a finding id with no finding block.
sed 's/finding=F1/finding=F9/' "$FX/expected-findings.md" > "$TMP/f.md"
expect_fail C5 'a finding id with no block must fail' 'F9'

# C6: intent stated only for some callers does not clear the flag.
sed 's/intent=partial(\([^)]*\)) test=missing finding=F1/intent=partial(\1) test=packages\/x.test.ts:1 finding=none/' \
    "$FX/expected-findings.md" > "$TMP/f.md"
expect_fail C6 'intent=partial with finding=none must fail' 'finding'

# S1: stage 04 runs the detector and the check, and names both winners.
grep -q 'detect-precedence-changes ../01-context/output/pr.diff' stages/04-review.md \
    || { echo "FAIL(S1): 04-review must run detect-precedence-changes on the sealed diff"; exit 1; }
grep -q 'detect-precedence-changes --check' stages/04-review.md \
    || { echo "FAIL(S2): 04-review must run the findings check"; exit 1; }
grep -q 'old-winner=' stages/04-review.md && grep -q 'new-winner=' stages/04-review.md \
    || { echo "FAIL(S3): 04-review must mandate the old and new winner per reorder"; exit 1; }

echo "PASS: precedence reorders detected (PR 96 config.attributes, inline spread, Object.assign), none on non-reorders; the findings check bites on a dropped row, a missing test without a finding, swapped winners, a dangling id and partial intent"
