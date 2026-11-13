#!/bin/sh
# Freezes the gate, body-claim and PR-text outputs of tools/gather-pr.
#
# Born from merged PRs whose blockers were process, not code: a QA ticket the template
# required, a path owned by another team whose review was required, an owner-approval
# merge policy; from PR bodies whose claims the code contradicted; and from internal links
# in the body of a PR on a public repo.
#
# Offline: a stub `gh` serves a frozen PR, template, CODEOWNERS and branch protection.
# Cases: body-claims.tsv carries the body's claim lines; gates.tsv records visibility,
# the author, the last-matching CODEOWNERS rule per touched path (and "no matching rule"),
# the review policy from branch protection, and the template's QA lines; pr-text.diff
# carries the body and commit messages as added lines the leakage tool can scan; a repo
# with no CODEOWNERS and no protection says NONE / unavailable, never silence.
# Runs from anywhere - it locates itself. Exit 0 = pass.
set -eu

HERE=$(cd "$(dirname "$0")/.." && pwd)
cd "$HERE"

TOOL=tools/gather-pr
test -x "$TOOL" || { echo "FAIL: $TOOL missing or not executable"; exit 1; }

tmp=$(mktemp -d); trap 'rm -rf "$tmp"' EXIT
mkdir -p "$tmp/bin" "$tmp/fix"
F=$tmp/fix

cat > "$F/pr.json" <<'EOF'
{"number":7,"title":"Fix submit","state":"OPEN","isDraft":false,"author":{"login":"alice"},
 "createdAt":"2026-11-01T00:00:00Z","updatedAt":"2026-11-02T00:00:00Z",
 "body":"## Summary\nSubmit now fails once and shows the error.\nSee /Users/alice/notes for context.\n- [ ] QA ticket linked",
 "labels":[],"files":[{"path":"apps/server/src/a.ts"},{"path":"apps/web/src/b.tsx"},{"path":"README.md"}],
 "additions":3,"deletions":1,
 "commits":[{"messageHeadline":"fix submit","messageBody":"round 2 per review"}],
 "reviews":[],"comments":[],"closingIssuesReferences":[],"headRefOid":"abc","baseRefName":"main"}
EOF
printf '## Checklist\n- [ ] QA ticket linked\n- [ ] Tests added\n' > "$F/template.md"
printf '# owners\n* @org/everyone\n/apps/server/ @org/backend\n*.tsx @org/frontend\n' > "$F/CODEOWNERS"
printf '{"required_pull_request_reviews":{"required_approving_review_count":2,"require_code_owner_reviews":true}}\n' > "$F/protection.json"
printf 'diff --git a/apps/server/src/a.ts b/apps/server/src/a.ts\n--- a/apps/server/src/a.ts\n+++ b/apps/server/src/a.ts\n@@ -1 +1 @@\n-x\n+y\n' > "$F/pr.diff"

cat > "$tmp/bin/gh" <<'EOF'
#!/bin/sh
F=$GH_FIX
case "$1 $2" in
  "pr view") cat "$F/pr.json" ;;
  "pr diff") cat "$F/pr.diff" ;;
  "repo view") printf '{"visibility":"PUBLIC"}\n' ;;
  api*)
    case "$*" in
      *timeline*) echo '[]' ;;
      *contents/.github/pull_request_template.md*) cat "$F/template.md" ;;
      *contents/.github/CODEOWNERS*) [ -f "$F/CODEOWNERS" ] && cat "$F/CODEOWNERS" || exit 1 ;;
      *branches/main/protection*) [ -f "$F/protection.json" ] && cat "$F/protection.json" || exit 1 ;;
      *) exit 1 ;;
    esac ;;
  *) exit 1 ;;
esac
EOF
chmod +x "$tmp/bin/gh"

( cd "$tmp" && GH_FIX="$F" PATH="$tmp/bin:$PATH" sh "$HERE/$TOOL" o/r 7 out >/dev/null 2>&1 ) \
    || { echo "FAIL: gather-pr exited non-zero on the stubbed PR"; exit 1; }
O=$tmp/out

# E11 - the body's claims are extracted for 04 to verify against the diff.
grep -q '^2	[^	]*now[^	]*	Submit now fails once' "$O/body-claims.tsv" \
    || { echo "FAIL(G1): body-claims.tsv missing the 'now ... once' claim"; exit 1; }

# E13 - gates.
G=$O/gates.tsv
grep -q '^visibility	-	PUBLIC$' "$G" || { echo "FAIL(G2): visibility not recorded"; exit 1; }
grep -q '^author	-	alice$' "$G" || { echo "FAIL(G3): author not recorded"; exit 1; }
grep -q '^codeowners	apps/server/src/a\.ts	@org/backend$' "$G" \
    || { echo "FAIL(G4): last-matching anchored dir rule not applied to apps/server/src/a.ts"; exit 1; }
grep -q '^codeowners	apps/web/src/b\.tsx	@org/frontend$' "$G" \
    || { echo "FAIL(G5): unanchored glob rule not applied to apps/web/src/b.tsx"; exit 1; }
grep -q '^codeowners	README\.md	@org/everyone$' "$G" \
    || { echo "FAIL(G6): catch-all rule not applied to README.md"; exit 1; }
grep -q '^review-policy	main	required_approving_review_count=2 require_code_owner_reviews=true$' "$G" \
    || { echo "FAIL(G7): branch-protection review policy not recorded"; exit 1; }
grep -q '^qa	pr-template\.md:2	' "$G" \
    || { echo "FAIL(G8): the template's QA line was not recorded as a gate"; exit 1; }

# E12 - the body and commit messages are a scannable diff.
grep -q '^+See /Users/alice/notes for context\.$' "$O/pr-text.diff" \
    || { echo "FAIL(G9): pr-text.diff does not carry the body as added lines"; exit 1; }
grep -q '^+round 2 per review$' "$O/pr-text.diff" \
    || { echo "FAIL(G10): pr-text.diff does not carry commit messages"; exit 1; }
sh tools/gather-local-leakage "$O/pr-text.diff" "$tmp/leak" "$tmp/novocab" >/dev/null 2>&1 \
    || { echo "FAIL(G11): gather-local-leakage could not scan pr-text.diff"; exit 1; }
grep -q '^home-path	pr-body\.md	' "$tmp/leak/local-leakage.tsv" \
    || { echo "FAIL(G11): the home path in the PR body was not found by the leakage scan"; exit 1; }

# No CODEOWNERS, no protection: stated, never silent.
rm "$F/CODEOWNERS" "$F/protection.json"
( cd "$tmp" && GH_FIX="$F" PATH="$tmp/bin:$PATH" sh "$HERE/$TOOL" o/r 7 out2 >/dev/null 2>&1 ) \
    || { echo "FAIL: gather-pr exited non-zero without CODEOWNERS"; exit 1; }
grep -q '^codeowners	-	NONE: no CODEOWNERS' "$tmp/out2/gates.tsv" \
    || { echo "FAIL(G12): a missing CODEOWNERS must say NONE"; exit 1; }
grep -q '^review-policy	main	unavailable' "$tmp/out2/gates.tsv" \
    || { echo "FAIL(G13): unreadable branch protection must say unavailable"; exit 1; }

echo "PASS: gather-pr - body claims, visibility, author, CODEOWNERS last-match per path, review policy, QA template line, scannable PR text; NONE/unavailable when absent"
