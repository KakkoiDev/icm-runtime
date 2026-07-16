#!/bin/sh
# Freezes tools/check-value-claims: the deterministic cross-check of the self-graded
# introduced-by-diff/floor claims (#24618 hardening). Cases: a grounded claim is
# consistent; an inline-bound claim citing no diff-touched file is SUSPECT; no cited
# file at all is SUSPECT; introduced-by-diff=no and floor=fail are exempt; a finding
# without a Value line is SUSPECT. Runs from the skill dir. Exit 0 = pass.
set -eu

tool="tools/check-value-claims"
test -x "$tool" || { echo "FAIL: $tool missing or not executable"; exit 1; }

tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT

cat > "$tmp/pr.diff" <<'EOF'
--- a/apps/web/src/components/ShareDialog/hooks.ts
+++ b/apps/web/src/components/ShareDialog/hooks.ts
@@ -1,3 +1,2 @@
 context
-removed()
 copyToClipboard(url)
--- a/apps/web/src/pages/balance/index.page.tsx
+++ b/apps/web/src/pages/balance/index.page.tsx
@@ -1,2 +1,3 @@
 context
+documentId={balanceId}
EOF

cat > "$tmp/findings.md" <<'EOF'
## F1 - LOW - scope
At apps/web/src/components/ShareDialog/hooks.ts:128 the removal is org-wide.
Value: introduced-by-diff=yes in-scope=yes merge-decision=yes floor=pass -> proposed: inline
## F2 - LOW - robustness
The pre-existing pattern lives in apps/web/src/lib/download.ts:45.
Value: introduced-by-diff=yes in-scope=no merge-decision=no floor=pass -> proposed: inline
## F3 - MEDIUM - test coverage
No automated test anywhere.
Value: introduced-by-diff=yes in-scope=yes merge-decision=yes floor=pass -> proposed: inline
## F4 - LOW - style
Naming in apps/web/src/lib/download.ts:12.
Value: introduced-by-diff=no in-scope=no merge-decision=no floor=fail -> proposed: report-only(pre-existing)
## F5 - LOW - nit
Something about apps/web/src/lib/other.ts:3.
Value: introduced-by-diff=yes in-scope=yes merge-decision=no floor=fail -> proposed: report-only(LOW-not-merge-changing)
## F6 - LOW - ungated
No Value line here at all.
EOF

out=$("$tool" "$tmp/findings.md" "$tmp/pr.diff")

verdict() { printf '%s\n' "$out" | awk -F'\t' -v id="$1" '$1==id{print $3; exit}'; }

case "$(verdict F1)" in consistent) : ;; *) echo "FAIL: F1 cites a diff-touched file, expected consistent (got: $(verdict F1))"; exit 1 ;; esac
case "$(verdict F2)" in SUSPECT*) : ;; *) echo "FAIL: F2 claims introduced-by-diff=yes but cites only an untouched file, expected SUSPECT (got: $(verdict F2))"; exit 1 ;; esac
case "$(verdict F3)" in SUSPECT*) : ;; *) echo "FAIL: F3 claims floor=pass with no file cited, expected SUSPECT (got: $(verdict F3))"; exit 1 ;; esac
case "$(verdict F4)" in "exempt(introduced-by-diff=no)") : ;; *) echo "FAIL: F4 is introduced-by-diff=no, expected exempt (got: $(verdict F4))"; exit 1 ;; esac
case "$(verdict F5)" in "exempt(floor=fail)") : ;; *) echo "FAIL: F5 is floor=fail, expected exempt (got: $(verdict F5))"; exit 1 ;; esac
case "$(verdict F6)" in SUSPECT*) : ;; *) echo "FAIL: F6 has no Value line, expected SUSPECT (got: $(verdict F6))"; exit 1 ;; esac

# Path matching is suffix-tolerant: a finding citing a repo-absolute path still matches.
cat > "$tmp/findings2.md" <<'EOF'
## F1 - HIGH - correctness
Broken at web/src/pages/balance/index.page.tsx:2.
Value: introduced-by-diff=yes in-scope=yes merge-decision=yes floor=pass -> proposed: inline
EOF
out=$("$tool" "$tmp/findings2.md" "$tmp/pr.diff")
case "$(verdict F1)" in consistent) : ;; *) echo "FAIL: suffix path match expected consistent (got: $(verdict F1))"; exit 1 ;; esac

echo "ok: check-value-claims (grounded/ungrounded/exempt verdicts)"
