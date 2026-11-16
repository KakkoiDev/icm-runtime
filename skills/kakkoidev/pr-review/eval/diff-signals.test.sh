#!/bin/sh
# Freezes the diff-signals check (04 step 18): five finding classes a bot reviewer raised on
# one private-repo PR (2026-11) that pr-review had no step for. Each class is a code shape a
# script can find; whether the shape is a defect is the reviewer's call, but every hit must be
# accounted for in findings.md, so none is passed over unread.
#   new-table-access   a new table whose isolation (RLS call, policy) is weaker than the
#                      sibling it was copied from: tenant-only where the sibling is company-scoped.
#   entity-route       a route taking an entity id in its path, checked only by a class-level
#                      permission on another resource: no lookup proves the caller may see it.
#   bulk-copy          a copy job that loads every source row (any lifecycle state, already
#                      copied or not) into one unbounded insert.
#   query-no-error-state     a data hook whose error is never read, so a 403/500 renders as
#                            the empty state.
#   mutation-no-pending-state  a mutation whose in-flight state is never read, so a double
#                              click writes twice.
# Fixtures are synthetic (the source repo is private); shapes and false-positive neighbours
# mirror the real diff. Cases: D* the detector, C* the findings check, S* the stage wiring.
# Runs from anywhere - it locates itself. Exit 0 = pass.
set -eu

HERE=$(cd "$(dirname "$0")/.." && pwd)
cd "$HERE"

T=tools/gather-diff-signals
FX=eval/fixtures/diff-signals
test -x "$T" || { echo "FAIL: $T missing or not executable"; exit 1; }

TMP=$(mktemp -d "${TMPDIR:-/tmp}/diff-signals-eval.XXXXXX")
trap 'rm -f "$TMP"/*; rmdir "$TMP"' EXIT

"$T" "$FX/pr.diff" "$TMP" "$FX/repo" 2>/dev/null
S="$TMP/diff-signals.tsv"
test -f "$S" || { echo "FAIL: no diff-signals.tsv written"; exit 1; }

row() { # class path line evidence-substring
    awk -F'\t' -v c="$1" -v p="$2" -v l="$3" -v e="$4" '$1 == c && $2 == p && $3 == l && index($5, e) { f = 1 } END { exit !f }' "$S" \
        || { echo "FAIL($5): expected $1 $2:$3 with evidence containing: $4"; cat "$S"; exit 1; }
}
none() { # class path line
    awk -F'\t' -v c="$1" -v p="$2" -v l="$3" '$1 == c && $2 == p && $3 == l { f = 1 } END { exit f }' "$S" \
        || { echo "FAIL($4): unexpected $1 row at $2:$3"; cat "$S"; exit 1; }
}

M=db/migrations/20260101000000_add_attachment_tables/migration.sql
C=src/attachments/attachments.controller.ts
W=web/AttachmentsBlock.tsx

# D1 new-table-access: the new table's access calls next to the sibling's, read from the repo.
row new-table-access "$M" 2 "access=enable_tenant_rls sibling=Note(enable_company_rls,ENABLE ROW LEVEL SECURITY)" D1a
row new-table-access "$M" 10 "access=none sibling=Note(" D1b
row new-table-access "$M" 16 "access=CREATE POLICY" D1c

# D2 entity-route: path params are listed; a route without one is silent, test files too.
row entity-route "$C" 4 "params=targetType,targetId" D2a
row entity-route "$C" 9 "params=attachmentId" D2b
row entity-route "$C" 20 "params=id" D2c
none entity-route "$C" 14 D2d
none entity-route "$C" 21 D2e
none entity-route src/attachments/attachments.service.spec.ts 3 D2f

# D3 bulk-copy: INSERT ... SELECT across lines and an ORM bulk insert; VALUES inserts and
# test files are silent.
row bulk-copy "$M" 24 "INSERT INTO" D3a
row bulk-copy src/attachments/attachments.service.ts 14 "createMany(" D3b
none bulk-copy "$M" 26 D3c
none bulk-copy src/attachments/attachments.service.spec.ts 2 D3d

# D4 query-no-error-state: RTK, react-query and SWR destructures that never read the error.
row query-no-error-state "$W" 2 "useGetAttachmentsQuery" D4a
row query-no-error-state "$W" 9 "useQuery" D4b
row query-no-error-state "$W" 10 "useSWR" D4c
for l in 11 12 13 16 17 18; do none query-no-error-state "$W" "$l" "D4d:$l"; done

# D5 mutation-no-pending-state: a lone trigger, a mutate with no pending flag.
row mutation-no-pending-state "$W" 7 "useUseAttachmentMutation" D5a
row mutation-no-pending-state "$W" 8 "useMutation" D5b
for l in 5 14 15; do none mutation-no-pending-state "$W" "$l" "D5c:$l"; done

grep -q '^# TOTAL: 13 ' "$S" || { echo "FAIL(D6): expected exactly 13 signals"; cat "$S"; exit 1; }

# D7 a diff with none of the shapes says so explicitly.
cat > "$TMP/none.diff" <<'EOF'
diff --git a/src/a.ts b/src/a.ts
--- a/src/a.ts
+++ b/src/a.ts
@@ -1,1 +1,2 @@
 const a = 1
+const b = 2
EOF
mkdir "$TMP/n"
"$T" "$TMP/none.diff" "$TMP/n" 2>/dev/null
grep -q '^# NONE:' "$TMP/n/diff-signals.tsv" || { echo "FAIL(D7): expected # NONE: line"; cat "$TMP/n/diff-signals.tsv"; exit 1; }
rm -f "$TMP/n"/*; rmdir "$TMP/n"

# D8 without a repo root the sibling lookup is reported as not run, never as no sibling.
mkdir "$TMP/r"
"$T" "$FX/pr.diff" "$TMP/r" 2>/dev/null
awk -F'\t' '$1 == "new-table-access" && $3 == 2 && index($5, "sibling=NOT-RUN(no repo root)") { f = 1 } END { exit !f }' "$TMP/r/diff-signals.tsv" \
    || { echo "FAIL(D8): expected sibling=NOT-RUN(no repo root) without a repo root"; cat "$TMP/r/diff-signals.tsv"; exit 1; }
rm -f "$TMP/r"/*; rmdir "$TMP/r"

# C1 every row accounted -> OK.
awk -F'\t' '!/^#/ { v = (NR % 2) ? "finding(F1)" : "clear(not a defect here)"; print "Signal: " $1 " " $2 ":" $3 " verdict=" v }' "$S" > "$TMP/f.md"
printf '\n## F1 - HIGH - authorization\n' >> "$TMP/f.md"
"$T" --check "$S" "$TMP/f.md" > "$TMP/c.out" || { echo "FAIL(C1): full accounting rejected"; cat "$TMP/c.out"; exit 1; }

# C2 a dropped row is named.
grep -v "entity-route $C:9 " "$TMP/f.md" > "$TMP/f2.md"
if "$T" --check "$S" "$TMP/f2.md" > "$TMP/c.out"; then echo "FAIL(C2): dropped row accepted"; exit 1; fi
grep -q "^UNACCOUNTED: entity-route $C:9" "$TMP/c.out" || { echo "FAIL(C2): expected UNACCOUNTED for $C:9"; cat "$TMP/c.out"; exit 1; }

# C3 a verdict naming a finding with no block is dangling.
sed 's/finding(F1)/finding(F9)/' "$TMP/f.md" > "$TMP/f3.md"
if "$T" --check "$S" "$TMP/f3.md" > "$TMP/c.out"; then echo "FAIL(C3): dangling finding accepted"; exit 1; fi
grep -q '^DANGLING: F9' "$TMP/c.out" || { echo "FAIL(C3): expected DANGLING: F9"; cat "$TMP/c.out"; exit 1; }

# C4 a clear needs a reason; a bare verdict is rejected.
sed 's/clear(not a defect here)/clear/' "$TMP/f.md" > "$TMP/f4.md"
if "$T" --check "$S" "$TMP/f4.md" > "$TMP/c.out"; then echo "FAIL(C4): clear without reason accepted"; exit 1; fi
grep -q '^BAD-VERDICT:' "$TMP/c.out" || { echo "FAIL(C4): expected BAD-VERDICT"; cat "$TMP/c.out"; exit 1; }

# S1-S6 stage 04 runs the tool and its check, and states the judgment each class needs.
ST=stages/04-review.md
grep -q 'tools/gather-diff-signals ../01-context/output/pr.diff output' "$ST" || { echo "FAIL(S1): 04 does not run gather-diff-signals"; exit 1; }
grep -q 'tools/gather-diff-signals --check output/diff-signals.tsv output/findings.md' "$ST" || { echo "FAIL(S2): 04 does not run the --check"; exit 1; }
grep -q 'weaker than the sibling' "$ST" || { echo "FAIL(S3): new-table-access judgment missing"; exit 1; }
grep -q 'loads that entity under the caller' "$ST" || { echo "FAIL(S4): entity-route judgment missing"; exit 1; }
grep -q 'lifecycle state' "$ST" && grep -q 'already copied' "$ST" && grep -q 'unbounded' "$ST" || { echo "FAIL(S5): bulk-copy judgment missing"; exit 1; }
grep -q 'renders the empty state' "$ST" && grep -q 'double submit' "$ST" || { echo "FAIL(S6): request-state judgment missing"; exit 1; }
# S7 the sibling parity lens also asks for the sibling's helper (rule only, no signal).
grep -q 're-implements a helper the sibling' "$ST" || { echo "FAIL(S7): sibling helper-reuse lens missing"; exit 1; }
# S8 the outputs table lists the artifact.
grep -q '| Diff signals | output/diff-signals.tsv' "$ST" || { echo "FAIL(S8): outputs table missing diff-signals.tsv"; exit 1; }

echo "PASS: diff-signals (detector, check, stage wiring)"
