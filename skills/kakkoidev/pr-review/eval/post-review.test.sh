#!/bin/sh
# Deterministic eval: tools/post-review against a stubbed `gh`.
# The captain gates publication: post-review creates exactly ONE pending review (no
# `event`), prints its URL, and STOPS when the user already has a pending review on the
# PR instead of appending to it. Runs from the skill dir.
set -eu
SKILL=$(cd "$(dirname "$0")/.." && pwd)
T=$(mktemp -d)
trap 'rm -f "$T"/bin/gh "$T"/*.log "$T"/*.json "$T"/req; rmdir "$T"/bin "$T" 2>/dev/null || true' EXIT
mkdir "$T/bin"

# Stub gh: logs every call; answers from $STUB_REVIEWS for the reviews listing.
cat > "$T/bin/gh" <<'EOF'
#!/bin/sh
echo "$*" >> "$STUB_LOG"
case "$*" in
  "api user"*) echo me ;;
  *"--method POST"*)
    while [ $# -gt 0 ]; do [ "$1" = --input ] && cp "$2" "$STUB_REQ"; shift; done
    echo "https://github.com/o/r/pull/7#pullrequestreview-99" ;;
  *"pulls/7/reviews"*) cat "$STUB_REVIEWS" ;;
  *"pulls/7 "*|*"pulls/7") echo deadbeef ;;
  *) echo "stub: unexpected gh $*" >&2; exit 9 ;;
esac
EOF
chmod +x "$T/bin/gh"
export PATH="$T/bin:$PATH" STUB_LOG="$T/gh.log" STUB_REQ="$T/req" STUB_REVIEWS="$T/reviews.json"

printf '[{"path":"a.ts","line":3,"side":"RIGHT","body":"**F1 - HIGH - correctness.** EN line.\\nJP line."}]' > "$T/payload.json"

# A - the user already has a PENDING review: stop, non-zero, write nothing.
printf '[{"id":5,"node_id":"N5","state":"PENDING","user":{"login":"me"}}]' > "$STUB_REVIEWS"
: > "$STUB_LOG"; rm -f "$STUB_REQ"
if sh "$SKILL/tools/post-review" o/r 7 "$T/payload.json" > "$T/out.log" 2> "$T/err.log"; then
  echo "FAIL A: existing pending review by the user must stop post-review with non-zero exit"; exit 1
fi
grep -qiE 'pending review' "$T/err.log" || { echo "FAIL A: stop must report the existing pending review"; cat "$T/err.log"; exit 1; }
if grep -qE 'POST|graphql' "$STUB_LOG"; then echo "FAIL A: must not create or append when a pending review exists"; cat "$STUB_LOG"; exit 1; fi

# B - a pending review by SOMEONE ELSE does not block: create ours.
printf '[{"id":6,"node_id":"N6","state":"PENDING","user":{"login":"other"}},{"id":4,"state":"COMMENTED","user":{"login":"me"}}]' > "$STUB_REVIEWS"
: > "$STUB_LOG"; rm -f "$STUB_REQ"
sh "$SKILL/tools/post-review" o/r 7 "$T/payload.json" > "$T/out.log" 2> "$T/err.log" \
  || { echo "FAIL B: another user's pending review must not block"; cat "$T/err.log"; exit 1; }
test -s "$STUB_REQ" || { echo "FAIL B: no create request sent"; exit 1; }

# C - the create request carries NO event (never submitted), all comments, and stdout is the URL.
jq -e 'has("event") | not' "$STUB_REQ" >/dev/null || { echo "FAIL C: create request must carry no event"; exit 1; }
jq -e '.comments | length == 1' "$STUB_REQ" >/dev/null || { echo "FAIL C: create request must carry every comment"; exit 1; }
[ "$(cat "$T/out.log")" = "https://github.com/o/r/pull/7#pullrequestreview-99" ] \
  || { echo "FAIL C: stdout must be exactly the pending review URL, got: $(cat "$T/out.log")"; exit 1; }
if grep -q graphql "$STUB_LOG"; then echo "FAIL C: must not use the append (graphql) path"; exit 1; fi

echo "PASS: post-review creates one pending review, prints its URL, stops on an existing one"
