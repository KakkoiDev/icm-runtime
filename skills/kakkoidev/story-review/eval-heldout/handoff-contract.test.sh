#!/bin/sh
# Output-contract regression check, held out from the LLM grader.
#
# Failures this encodes, all real:
#   1. Per-story deliverables were written to a scratchpad OUTSIDE the sealed run and
#      were gone by the time anyone looked (2026-07-29, three of five stories).
#   2. A flat 30-item list buried four project-threatening problems among settled
#      questions, so the handoff must be tiered with a capped tier 1.
#   3. 12 of 30 findings had already been answered, three decided the other way, so
#      every finding must carry a disposition and the answered ones must be recorded.
#   4. A human had to hunt for each acceptance criterion before commenting, so tier 1
#      must carry a block link and paste-ready text.
#   5. Comments were to be posted untagged first, then tagged after a re-read, so a
#      drafted comment must never contain a mention.
#
# Checks completeness and shape, never the quality of the questions or the tiering
# judgment. Reads the produced run output via $ICM_RUN_DIR. Exit 0 = pass.
set -eu

[ -n "${ICM_RUN_DIR:-}" ] || { echo "FAIL: ICM_RUN_DIR not set (run via icm-improve held-out)"; exit 1; }

handoff="$ICM_RUN_DIR/04-handoff/output/handoff.md"
findings="$ICM_RUN_DIR/02-blind-review/output/findings.md"

[ -f "$handoff" ] || { echo "FAIL: handoff.md not found at $handoff - stage 04 produced no deliverable"; exit 1; }
[ -f "$findings" ] || { echo "FAIL: findings.md not found at $findings"; exit 1; }

# --- 1. tiered, in order, with the supporting sections ------------------------
for section in \
    "## Tier 1 - disaster if it ships unresolved" \
    "### Tier 1 comments, ready to post" \
    "## Tier 2 - must share" \
    "## Tier 3 - everything else, in priority order" \
    "## Land in the body" \
    "## Already answered" \
    "## Refuted" \
    "## Limits"
do
    grep -qF "$section" "$handoff" || { echo "FAIL: missing section '$section' in $handoff"; exit 1; }
done

t1=$(grep -nF "## Tier 1 - disaster if it ships unresolved" "$handoff" | head -1 | cut -d: -f1)
t2=$(grep -nF "## Tier 2 - must share" "$handoff" | head -1 | cut -d: -f1)
t3=$(grep -nF "## Tier 3 - everything else, in priority order" "$handoff" | head -1 | cut -d: -f1)
[ "$t1" -lt "$t2" ] && [ "$t2" -lt "$t3" ] || {
    echo "FAIL: tiers are out of order (tier 1 must come first): T1@$t1 T2@$t2 T3@$t3"; exit 1; }

# --- 2. tier 1 is capped at 5 -------------------------------------------------
# Count the ready-to-post items, which is the countable form of tier 1 membership.
ready=$(awk '/^### Tier 1 comments, ready to post$/{p=1; next} /^## /{p=0} p' "$handoff" \
    | grep -cE '^\*\*[0-9]+\.' || true)
[ "$ready" -ge 1 ] || { echo "FAIL: no ready-to-post tier-1 items found (expected '**<n>. ...**' entries)"; exit 1; }
[ "$ready" -le 5 ] || { echo "FAIL: tier 1 has $ready items, cap is 5 - rank and push the rest to tier 2"; exit 1; }

# --- 3. every tier-1 item has a Block: line, and each is a link or an honest none
blocklines=$(awk '/^### Tier 1 comments, ready to post$/{p=1; next} /^## /{p=0} p' "$handoff" \
    | grep -c '^Block:' || true)
[ "$blocklines" -eq "$ready" ] || {
    echo "FAIL: $ready tier-1 items but $blocklines 'Block:' lines - every item needs one"; exit 1; }

bad=$(awk '/^### Tier 1 comments, ready to post$/{p=1; next} /^## /{p=0} p' "$handoff" \
    | grep '^Block:' \
    | grep -vE '\]\(https://app\.notion\.com/p/[0-9a-f]{32}#[0-9a-f]{32}\)' \
    | grep -viF 'no link available' || true)
[ -z "$bad" ] || {
    echo "FAIL: Block: line(s) neither a well-formed markdown block anchor nor an explicit 'no link available':"
    printf '%s\n' "$bad"; exit 1; }

# A bare block URL means Notion will strip the fragment (observed 2026-07-30).
bare=$(awk '/^### Tier 1 comments, ready to post$/{p=1; next} /^## /{p=0} p' "$handoff" \
    | grep '^Block: https://' || true)
[ -z "$bare" ] || {
    echo "FAIL: bare block URL(s) - must be a markdown link, Notion strips the #fragment otherwise:"
    printf '%s\n' "$bare"; exit 1; }

# --- 3b. every tier-1 item says whether it is a new thread or a reply ---------
# "Post this" and "reply to this" are different actions, and opening a second thread
# on a question that already has one splits the answer across two places. Observed:
# a page where the owner's restructured spec lived in one thread while three
# reviewers asked for it in three others.
threadlines=$(awk '/^### Tier 1 comments, ready to post$/{p=1; next} /^## /{p=0} p' "$handoff" \
    | grep -c '^Thread:' || true)
[ "$threadlines" -eq "$ready" ] || {
    echo "FAIL: $ready tier-1 items but $threadlines 'Thread:' lines - every item must say"
    echo "whether it is a new top-level comment or a reply inside an existing thread"; exit 1; }

badthread=$(awk '/^### Tier 1 comments, ready to post$/{p=1; next} /^## /{p=0} p' "$handoff" \
    | grep '^Thread:' \
    | grep -vE '^Thread: (new thread|discussion://[0-9a-fA-F-]{36}/[0-9a-fA-F-]{36}/[0-9a-fA-F-]{36})[[:space:]]*$' || true)
[ -z "$badthread" ] || {
    echo "FAIL: Thread: line(s) are neither 'new thread' nor a well-formed discussion:// id:"
    printf '%s\n' "$badthread"; exit 1; }

# --- 4. every tier-1 item has paste-ready comment text -----------------------
quotes=$(awk '/^### Tier 1 comments, ready to post$/{p=1; next} /^## /{p=0} p' "$handoff" \
    | grep -cE '^> .' || true)
[ "$quotes" -ge "$ready" ] || {
    echo "FAIL: $ready tier-1 items but only $quotes quoted comment draft(s)"; exit 1; }

# --- 5. no mentions anywhere in the handoff ----------------------------------
if grep -qE '<mention-user|@[A-Za-z][A-Za-z0-9._-]{2,}' "$handoff"; then
    if grep -qE '<mention-user' "$handoff" || grep -E '@[A-Za-z][A-Za-z0-9._-]{2,}' "$handoff" | grep -qvF '@mention'; then
        echo "FAIL: handoff contains a mention - comments are posted untagged first, then tagged after a re-read"
        grep -nE '<mention-user|@[A-Za-z][A-Za-z0-9._-]{2,}' "$handoff" | grep -vF '@mention' || true
        exit 1
    fi
fi

# --- 6. every finding is disposed of somewhere -------------------------------
missing=""
for fid in $(grep -oE '^## F[0-9]+' "$findings" | grep -oE 'F[0-9]+' | sort -u); do
    grep -qE "(^|[^A-Za-z0-9])${fid}([^0-9]|$)" "$handoff" || missing="$missing $fid"
done
[ -z "$missing" ] || { echo "FAIL: findings absent from handoff.md (silently dropped):$missing"; exit 1; }

missing_r=""
for rid in $(grep -oE '^## R[0-9]+' "$findings" | grep -oE 'R[0-9]+' | sort -u); do
    grep -qE "(^|[^A-Za-z0-9])${rid}([^0-9]|$)" "$handoff" || missing_r="$missing_r $rid"
done
[ -z "$missing_r" ] || { echo "FAIL: refuted candidates absent from handoff.md:$missing_r"; exit 1; }

# --- 7. the audit numbers and confidence labels survived ---------------------
grep -qE '^Grounded: [0-9]+/[0-9]+' "$handoff" || {
    echo "FAIL: handoff.md does not carry a 'Grounded: N/M' line from the grounding audit"; exit 1; }
grep -qE '(Confirmed|Strongly supported|Supported|Plausible|Partly refuted)' "$handoff" || {
    echo "FAIL: handoff.md carries no confidence label from findings.md"; exit 1; }

nf=$(grep -cE '^## F[0-9]+' "$findings" || true)
echo "ok: handoff tiered (tier 1 = $ready items, capped), every item linked or honestly unlinked, $nf finding(s) disposed of, no mentions"
