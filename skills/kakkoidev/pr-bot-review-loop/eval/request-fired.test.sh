#!/bin/sh
# Freezes tools/verify-request-fired: R1, the rule that cost PR 26205 its round 9 and PR
# 26204 the same way - a request comment with no @claude mention never fires, and a posted
# comment is not a triggered review. The GitHub CLI is stubbed, so the check is offline and
# deterministic. Runs from the skill dir. Exit 0 = pass.
set -eu

tool="tools/verify-request-fired"
test -x "$tool" || { echo "FAIL: $tool missing or not executable"; exit 1; }
command -v jq >/dev/null 2>&1 || { echo "SKIP: jq not installed"; exit 0; }

tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT
mkdir -p "$tmp/fx" "$tmp/out"

# A stub standing in for gh-axi: serves the fixture files, nothing else.
cat > "$tmp/ghstub" <<'STUB'
#!/bin/sh
FX=${FX:?}
case "$*" in
    *"/issues/7/comments"*) cat "$FX/comments.json" ;;
    *"/pulls/7/reviews"*)   cat "$FX/reviews.json" ;;
    *"/pulls/7"*)           printf 'feat/branch\n' ;;
    *"actions/runs"*)       cat "$FX/runs.json" ;;
    *) echo '[]' ;;
esac
STUB
chmod +x "$tmp/ghstub"
export FX="$tmp/fx"
echo '{"workflow_runs":[]}' > "$tmp/fx/runs.json"

verdict() { awk -F'\t' '$1=="verdict"{print $2; exit}' "$tmp/out/request-$1.tsv"; }
field()   { awk -F'\t' -v k="$2" '$1==k{print $2; exit}' "$tmp/out/request-$1.tsv"; }

# ---- 1. the failure that started the rule: a request with no mention ----
cat > "$tmp/fx/comments.json" <<'EOF'
[{"id":1,"created_at":"2026-09-01T10:00:00Z","user":{"login":"cyril"},
  "body":"please review the latest push"}]
EOF
echo '[]' > "$tmp/fx/reviews.json"
GHBIN="$tmp/ghstub" sh "$tool" o/r 7 1 "$tmp/out" claude >/dev/null
[ "$(verdict 1)" = "UNFIRED(no-mention)" ] \
    || { echo "FAIL: a mention-less request must be UNFIRED(no-mention), got $(verdict 1)"; exit 1; }
[ "$(field 1 mention)" = no ] || { echo "FAIL: mention should be no"; exit 1; }

# ---- 2. mentioned, but nothing came back yet: NOT a pass ----
cat > "$tmp/fx/comments.json" <<'EOF'
[{"id":2,"created_at":"2026-09-01T10:00:00Z","user":{"login":"cyril"},
  "body":"@claude please review round 2"}]
EOF
GHBIN="$tmp/ghstub" sh "$tool" o/r 7 2 "$tmp/out" claude >/dev/null
[ "$(verdict 2)" = "UNCONFIRMED(no-activity)" ] \
    || { echo "FAIL: a mentioned request with no bot activity must be UNCONFIRMED, got $(verdict 2)"; exit 1; }
[ "$(field 2 run_started)" = no ] || { echo "FAIL: run_started should be no"; exit 1; }

# ---- 3. a bot review after the request: FIRED ----
cat > "$tmp/fx/reviews.json" <<'EOF'
[{"id":90,"submitted_at":"2026-09-01T10:05:00Z","user":{"login":"claude[bot]"},
  "commit_id":"abc123","body":"looks fine"}]
EOF
GHBIN="$tmp/ghstub" sh "$tool" o/r 7 3 "$tmp/out" claude >/dev/null
[ "$(verdict 3)" = "FIRED" ] || { echo "FAIL: a bot review after the request must be FIRED, got $(verdict 3)"; exit 1; }

# ---- 3b. a bot review BEFORE the request is not evidence that this round fired ----
cat > "$tmp/fx/reviews.json" <<'EOF'
[{"id":90,"submitted_at":"2026-09-01T09:00:00Z","user":{"login":"claude[bot]"},
  "commit_id":"abc123","body":"an earlier round"}]
EOF
GHBIN="$tmp/ghstub" sh "$tool" o/r 7 4 "$tmp/out" claude >/dev/null
[ "$(verdict 4)" = "UNCONFIRMED(no-activity)" ] \
    || { echo "FAIL: bot activity predating the request must not count as fired, got $(verdict 4)"; exit 1; }

# ---- 4. no request comment at all ----
echo '[]' > "$tmp/fx/comments.json"
echo '[]' > "$tmp/fx/reviews.json"
GHBIN="$tmp/ghstub" sh "$tool" o/r 7 5 "$tmp/out" claude >/dev/null
[ "$(verdict 5)" = "UNFIRED(no-request)" ] \
    || { echo "FAIL: no request comment must be UNFIRED(no-request), got $(verdict 5)"; exit 1; }

# ---- 5. the bot's own comment is never mistaken for our request ----
cat > "$tmp/fx/comments.json" <<'EOF'
[{"id":3,"created_at":"2026-09-01T10:00:00Z","user":{"login":"cyril"},
  "body":"@claude review please"},
 {"id":4,"created_at":"2026-09-01T10:05:00Z","user":{"login":"claude[bot]"},
  "body":"here is my review"}]
EOF
echo '[]' > "$tmp/fx/reviews.json"
GHBIN="$tmp/ghstub" sh "$tool" o/r 7 6 "$tmp/out" claude >/dev/null
[ "$(field 6 request_comment_id)" = 3 ] \
    || { echo "FAIL: the request must be the human comment, got id $(field 6 request_comment_id)"; exit 1; }
[ "$(verdict 6)" = "FIRED" ] \
    || { echo "FAIL: a bot comment after the request counts as fired, got $(verdict 6)"; exit 1; }

echo ok
