#!/bin/sh
# Freezes the deployed-presence section of tools/gather-runtime-evidence.
#
# Born from reviewed PRs where the code was right and never ran where it mattered: a new
# env var read that no env registry or SSM manifest carried (always unset when deployed),
# and a new spec that no CI job picked up. Both pass review and CI on the diff alone.
#
# Offline: a stub `gh` that always fails stands in for the network, so every gh-backed
# fact degrades to its recorded "unavailable" line. The reviewed checkout is a frozen
# temp tree. Cases: an env var with a registry entry outside the diff is found there; an
# env var only the diff mentions is NOT FOUND; a new test file under a path a workflow
# names lists that workflow; one under a path no workflow names says NONE; the workflow's
# test invocation is listed; without a checkout the section says NOT RUN, never clear.
# Runs from anywhere - it locates itself. Exit 0 = pass.
set -eu

HERE=$(cd "$(dirname "$0")/.." && pwd)
cd "$HERE"

TOOL=tools/gather-runtime-evidence
test -x "$TOOL" || { echo "FAIL: $TOOL missing or not executable"; exit 1; }

tmp=$(mktemp -d); trap 'rm -rf "$tmp"' EXIT
mkdir -p "$tmp/bin" "$tmp/repo/.github/workflows" "$tmp/repo/apps/server/src" "$tmp/repo/apps/web/src"
printf '#!/bin/sh\nexit 1\n' > "$tmp/bin/gh"; chmod +x "$tmp/bin/gh"

printf 'KNOWN_VAR=\n' > "$tmp/repo/.env.example"
cat > "$tmp/repo/.github/workflows/ci.yml" <<'EOF'
name: ci
jobs:
  server:
    steps:
      - run: pnpm --filter server test
        working-directory: apps/server
EOF
printf 'export const a = process.env.KNOWN_VAR\nexport const b = process.env["MISSING_VAR"]\n' > "$tmp/repo/apps/server/src/config.ts"

cat > "$tmp/pr.diff" <<'EOF'
diff --git a/apps/server/src/config.ts b/apps/server/src/config.ts
--- a/apps/server/src/config.ts
+++ b/apps/server/src/config.ts
@@ -0,0 +1,2 @@
+export const a = process.env.KNOWN_VAR
+export const b = process.env["MISSING_VAR"]
diff --git a/apps/server/src/a.spec.ts b/apps/server/src/a.spec.ts
new file mode 100644
--- /dev/null
+++ b/apps/server/src/a.spec.ts
@@ -0,0 +1 @@
+it('works', () => {})
diff --git a/apps/web/src/b.test.tsx b/apps/web/src/b.test.tsx
new file mode 100644
--- /dev/null
+++ b/apps/web/src/b.test.tsx
@@ -0,0 +1 @@
+it('works', () => {})
EOF

PATH="$tmp/bin:$PATH" sh "$TOOL" o/r 1 "$tmp/out" "$tmp/pr.diff" "$tmp/repo" >/dev/null 2>&1 \
    || { echo "FAIL: gather-runtime-evidence exited non-zero with a checkout"; exit 1; }
R="$tmp/out/runtime-evidence.md"

grep -q '^## Deployed presence' "$R" || { echo "FAIL(D0): no Deployed presence section"; exit 1; }
grep -q '^- KNOWN_VAR: found outside the diff in: \.env\.example' "$R" \
    || { echo "FAIL(D1): KNOWN_VAR registry entry not found"; exit 1; }
grep -q '^- MISSING_VAR: NOT FOUND outside the diff' "$R" \
    || { echo "FAIL(D2): MISSING_VAR not reported NOT FOUND - an env var only the diff mentions reads as configured"; exit 1; }
grep -q '^- workflow test invocation: \.github/workflows/ci\.yml:5:' "$R" \
    || { echo "FAIL(D3): the workflow test invocation was not listed"; exit 1; }
grep -q '^- apps/server/src/a\.spec\.ts: workflows naming apps/server: \.github/workflows/ci\.yml' "$R" \
    || { echo "FAIL(D4): new spec under a workflow-named path did not list the workflow"; exit 1; }
grep -q '^- apps/web/src/b\.test\.tsx: workflows naming apps/web: NONE' "$R" \
    || { echo "FAIL(D5): new test under an unnamed path did not say NONE"; exit 1; }
grep -q '^- required status checks: unavailable' "$R" \
    || { echo "FAIL(D6): required-check lookup failure was not recorded"; exit 1; }

PATH="$tmp/bin:$PATH" sh "$TOOL" o/r 1 "$tmp/out2" "$tmp/pr.diff" >/dev/null 2>&1 \
    || { echo "FAIL: gather-runtime-evidence exited non-zero without a checkout"; exit 1; }
grep -q '^- NOT RUN: no reviewed checkout' "$tmp/out2/runtime-evidence.md" \
    || { echo "FAIL(D7): no checkout must record NOT RUN, never a silent clear"; exit 1; }

echo "PASS: deployed presence - env registry hit and miss, workflow test invocation, new-test CI naming hit and miss, required checks unavailable, NOT RUN without a checkout"
