#!/bin/sh
# Output-contract check for stage 02b, held out from the LLM grader.
#
# Failures this encodes, all real:
#   1. A comment read returned 8 of 24 threads and was treated as complete, so a
#      finding was published as "still unanswered" that the owner had answered in the
#      same thread four hours below the comment that was read.
#   2. Findings were generated against acceptance criteria the owner had already
#      rewritten in a comment three days earlier, and nobody noticed the reviewed
#      text was dead. Hence the VOID (SUPERSEDED TEXT) verdict must exist and be used
#      rather than quietly dropped.
#   3. Across two stories the owner answered in comments and promised "I'll put it in
#      the AC" repeatedly; the document was never edited, and three reviewers each
#      independently asked where the spec went. Hence every promise must be
#      dispositioned, not sampled.
#   4. A verdict of ANSWERED paired with an action that still sends the question is
#      how a settled question leaks into a tier and costs credibility on the rest.
#
# Checks completeness, vocabulary, and internal consistency. Never the quality of a
# verdict. Reads the produced run output via $ICM_RUN_DIR. Exit 0 = pass.
set -eu

[ -n "${ICM_RUN_DIR:-}" ] || { echo "FAIL: ICM_RUN_DIR not set (run via icm-improve held-out)"; exit 1; }

r="$ICM_RUN_DIR/02b-comment-pass/output"
findings="$ICM_RUN_DIR/02-blind-review/output/findings.md"

for f in "$r/discussions.md" "$r/coverage.txt" "$r/thread-state.tsv" \
         "$r/commitments.tsv" "$r/drift-ledger.md" "$r/dispositions.md"; do
    [ -f "$f" ] || { echo "FAIL: $f not found - stage 02b did not produce it"; exit 1; }
done
[ -f "$findings" ] || { echo "FAIL: $findings not found"; exit 1; }

work=$(mktemp -d)
trap 'rm -rf "$work"' EXIT INT TERM

# --- 1. the harvest was proven complete, not asserted -------------------------
grep -qE '^Declared: [0-9]+$' "$r/discussions.md" || {
    echo "FAIL: $r/discussions.md has no 'Declared: <N>' first line - there is no"
    echo "independent count for the coverage tool to check the harvest against."; exit 1; }
grep -q '^ok: harvest complete' "$r/coverage.txt" || {
    echo "FAIL: $r/coverage.txt does not carry a passing 'ok: harvest complete' line."
    echo "A truncated comment read is not a reconciliation."; exit 1; }

# --- 2. every promise and every reversal got a disposition --------------------
awk '/^## Commitments/{p=1; next} /^## Self-corrections/{p=0} p' "$r/commitments.tsv" \
    | grep -v '^discussion_id	' | grep -v '^#' | grep -v '^[[:space:]]*$' \
    > "$work/promises.tsv" || true
promises=$(wc -l < "$work/promises.tsv" | tr -d ' ')

disposed=$(grep -cE '^(LANDED|NOT LANDED|NOT A PROMISE):' "$r/drift-ledger.md" || true)
: "${disposed:=0}"
if [ "$disposed" -lt "$promises" ]; then
    echo "FAIL: $promises promise(s) in commitments.tsv but only $disposed disposition"
    echo "line(s) in drift-ledger.md. Every row needs LANDED: / NOT LANDED: / NOT A"
    echo "PROMISE: - sampling the ledger is how undocumented spec stays undocumented."
    exit 1
fi

awk '/^## Self-corrections/{p=1; next} /^## Summary/{p=0} p' "$r/commitments.tsv" \
    | grep -v '^discussion_id	' | grep -v '^#' | grep -v '^[[:space:]]*$' \
    > "$work/reversals.tsv" || true
reversals=$(wc -l < "$work/reversals.tsv" | tr -d ' ')
reversed=$(grep -c '^REVERSED:' "$r/drift-ledger.md" || true)
: "${reversed:=0}"
if [ "$reversed" -lt "$reversals" ]; then
    echo "FAIL: $reversals self-correction(s) found but only $reversed 'REVERSED:' line(s)."
    echo "A withdrawn answer still sitting mid-thread is read as current by anyone scrolling."
    exit 1
fi

grep -q '^## Threshold' "$r/drift-ledger.md" || {
    echo "FAIL: drift-ledger.md has no '## Threshold' section stating this page's own"
    echo "observed owner reply lag. A hardcoded staleness cutoff is a number nobody can"
    echo "defend; it has to come from the page."; exit 1; }

# --- 3. every finding and every refuted candidate has exactly one verdict -----
VERDICTS="UNRAISED|ANSWERED|ANSWERED IN COMMENT ONLY|PARTLY ANSWERED|NON-ANSWER|STALE ANSWER|DECIDED AGAINST|VOID (SUPERSEDED TEXT)"
ACTIONS="NEW COMMENT|REPLY: NUDGE|REPLY: RE-ASK|REPLY: FLAG STALE|REPLY: LAND IN BODY|NO ACTION"

for id in $(grep -oE '^## [FR][0-9]+' "$findings" | grep -oE '[FR][0-9]+' | sort -u); do
    n=$(awk -F'|' -v want="$id" '
        { gsub(/^[ \t]+|[ \t]+$/, "", $1) }
        $1 == want { c++ }
        END { print c + 0 }
    ' "$r/dispositions.md")
    if [ "$n" -eq 0 ]; then
        echo "FAIL: $id has no row in dispositions.md - it reaches the handoff with no"
        echo "idea whether the team already answered it."; exit 1
    fi
    if [ "$n" -gt 1 ]; then
        echo "FAIL: $id has $n rows in dispositions.md - a finding with two verdicts has none."; exit 1
    fi
done

# --- 4. closed vocabulary, and verdict/action consistency ---------------------
awk -F'|' -v verdicts="$VERDICTS" -v actions="$ACTIONS" '
    function trim(s) { gsub(/^[ \t]+|[ \t]+$/, "", s); return s }
    function inlist(v, list,   i, n, a) {
        n = split(list, a, "|")
        for (i = 1; i <= n; i++) if (a[i] == v) return 1
        return 0
    }
    /^[ \t]*[FR][0-9]+[ \t]*\|/ {
        id = trim($1); verdict = trim($2); action = trim($3); thread = trim($4)
        if (!inlist(verdict, verdicts)) {
            printf "FAIL: %s has verdict \"%s\", which is not in the closed vocabulary\n", id, verdict
            bad = 1; next
        }
        if (!inlist(action, actions)) {
            printf "FAIL: %s has action \"%s\", which is not in the closed vocabulary\n", id, action
            bad = 1; next
        }
        settled = (verdict == "ANSWERED" || verdict == "DECIDED AGAINST" || verdict == "VOID (SUPERSEDED TEXT)")
        if (settled && action != "NO ACTION") {
            printf "FAIL: %s is %s but its action is \"%s\" - a settled question must not be queued to send\n", id, verdict, action
            bad = 1
        }
        if (verdict == "UNRAISED" && action != "NEW COMMENT") {
            printf "FAIL: %s is UNRAISED but its action is \"%s\" - an unraised question has no thread to reply in\n", id, action
            bad = 1
        }
        if (verdict == "ANSWERED IN COMMENT ONLY" && action != "REPLY: LAND IN BODY") {
            printf "FAIL: %s is ANSWERED IN COMMENT ONLY but its action is \"%s\"\n", id, action
            bad = 1
        }
        if (action ~ /^REPLY:/ && (thread == "" || thread == "none")) {
            printf "FAIL: %s plans \"%s\" but names no thread to reply in\n", id, action
            bad = 1
        }
        if (action == "NEW COMMENT" && thread != "none" && thread != "") {
            printf "FAIL: %s plans a NEW COMMENT but names thread %s - reply there instead of splitting the answer\n", id, thread
            bad = 1
        }
        rows++
    }
    END {
        if (rows == 0) { print "FAIL: dispositions.md has no parseable `<id> | <verdict> | <action> | <thread> | ...` rows"; exit 1 }
        if (bad) exit 1
        printf "rows: %d\n", rows > "/dev/stderr"
    }
' "$r/dispositions.md" || exit 1

nf=$(grep -cE '^## F[0-9]+' "$findings" || true)
echo "ok: harvest proven complete, $promises promise(s) and $reversals reversal(s) dispositioned, $nf finding(s) verdicted with a consistent action"
