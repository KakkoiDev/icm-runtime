#!/bin/sh
# Smoke eval for story-review: structural checks only, no run. Exit 0 = pass.
set -eu

test -f SKILL.md || { echo "FAIL: SKILL.md missing"; exit 1; }
grep -q '^name: story-review$' SKILL.md || { echo "FAIL: SKILL.md name frontmatter"; exit 1; }

for s in 01-gather 02-blind-review 02b-comment-pass 03-score 04-handoff; do
    test -f "stages/$s.md" || { echo "FAIL: stages/$s.md missing"; exit 1; }
done

# The comment pass MUST sort between the blind review and the score, or a handoff
# could be built before anything was reconciled. Stages are discovered by a sorted
# glob, so this is a real ordering guarantee, not a naming preference.
order=$(ls stages/*.md | sed 's|stages/||; s|\.md$||' | tr '\n' ' ')
case "$order" in
    "01-gather 02-blind-review 02b-comment-pass 03-score 04-handoff "*) : ;;
    *) echo "FAIL: stage sort order is wrong: $order"; exit 1 ;;
esac

for t in tools/gather-schema-facts tools/gather-impl-facts tools/score-coverage \
         tools/grounding-audit tools/check-prior-runs tools/fetch-block-ids \
         tools/discussion-coverage tools/commitment-scan tools/thread-state; do
    test -x "$t" || { echo "FAIL: $t missing or not executable"; exit 1; }
done

# fetch-block-ids must refuse to run without a token rather than emitting a partial
# anchor list, and must never learn the token by reading a file off disk.
if ( unset NOTION_TOKEN; ./tools/fetch-block-ids 3a01ff99692281a09580f3afa460bad7 >/dev/null 2>&1 ); then
    echo "FAIL: tools/fetch-block-ids succeeded with no NOTION_TOKEN set"; exit 1
fi
# Inspect CODE, not the header comment (which legitimately explains why it does not
# read a .env). Strip full-line comments before looking for an actual file read.
if sed 's/^[[:space:]]*#.*//' tools/fetch-block-ids | grep -qE '(cat|source|\.|grep|awk|sed|read)[^|]*\.env'; then
    echo "FAIL: tools/fetch-block-ids reads a .env file - the token must come from the environment at run time"; exit 1
fi

for h in eval-heldout/coverage-contract.test.sh eval-heldout/sibling-coverage.test.sh eval-heldout/independence-line.test.sh eval-heldout/self-audit-contract.test.sh eval-heldout/handoff-contract.test.sh eval-heldout/drift-contract.test.sh; do
    test -f "$h" || { echo "FAIL: $h missing"; exit 1; }
done

for e in eval/score-coverage-block-split.test.sh eval/score-coverage-target-guard.test.sh eval/grounding-audit.test.sh eval/discussion-coverage.test.sh eval/commitment-scan.test.sh; do
    test -x "$e" || { echo "FAIL: $e missing or not executable"; exit 1; }
done

for c in checks/gathered.sh checks/blind-done.sh checks/reviewed.sh; do
    test -x "$c" || { echo "FAIL: $c not executable"; exit 1; }
done
grep -q 'ICM-GATE' stages/02-blind-review.md || { echo "FAIL: stage 02 missing ICM-GATE"; exit 1; }
grep -q 'ICM-GATE' stages/02b-comment-pass.md || { echo "FAIL: stage 02b missing ICM-GATE"; exit 1; }
grep -q 'ICM-GATE' stages/04-handoff.md || { echo "FAIL: stage 04 missing ICM-GATE"; exit 1; }

# Stage 02b must be gated on the BLIND findings only. Gating it on stage 03's
# grounding audit would deadlock (03 runs after it) and gating it on nothing would
# let a finding be born while reading the owner's answers.
grep -q 'run="checks/blind-done.sh"' stages/02b-comment-pass.md || { echo "FAIL: stage 02b is not gated on checks/blind-done.sh"; exit 1; }
if grep -q '03-score' checks/blind-done.sh; then
    echo "FAIL: checks/blind-done.sh references stage 03's output dir - stage 03 runs AFTER 02b, so gating on it deadlocks the pipeline"; exit 1
fi

# Stage 04's gate must refuse a partial comment harvest. This is the check that the
# 8-of-24 truncation incident turned into a mechanical rule.
grep -q 'ok: harvest complete' checks/reviewed.sh || { echo "FAIL: checks/reviewed.sh does not require a passing coverage proof from 02b"; exit 1; }
grep -q 'dispositions.md' checks/reviewed.sh || { echo "FAIL: checks/reviewed.sh does not require 02b's dispositions"; exit 1; }

test -f references/answer-key.tsv || { echo "FAIL: references/answer-key.tsv missing"; exit 1; }
rows=$(($(wc -l < references/answer-key.tsv) - 1))
[ "$rows" -ge 8 ] || { echo "FAIL: answer-key.tsv has too few rows ($rows)"; exit 1; }

# The key is target-bound; score-coverage's guard cannot fire without exactly one
# non-comment id line in this file.
test -f references/answer-key-target.txt || { echo "FAIL: references/answer-key-target.txt missing (target guard cannot fire without it)"; exit 1; }
ids=$(grep -cvE '^[[:space:]]*(#|$)' references/answer-key-target.txt || true)
[ "$ids" -eq 1 ] || { echo "FAIL: answer-key-target.txt must hold exactly one id line, found $ids"; exit 1; }

# Stage 03 must pass BOTH id files to the scorer - dropping them silently disables
# the guard and returns the skill to scoring any story against one story's key.
grep -q 'answer-key-target.txt' stages/03-score.md || { echo "FAIL: stage 03 does not pass answer-key-target.txt to score-coverage (target guard disabled)"; exit 1; }
grep -q 'grounding-audit' stages/03-score.md || { echo "FAIL: stage 03 does not run tools/grounding-audit"; exit 1; }
grep -q 'gather-impl-facts' stages/01-gather.md || { echo "FAIL: stage 01 does not run tools/gather-impl-facts"; exit 1; }

# The two added lenses and the refutation pass are stage 02's contract.
for lens in L9 L10; do
    grep -q "\*\*$lens - " stages/02-blind-review.md || { echo "FAIL: stage 02 is missing lens $lens"; exit 1; }
done
grep -q 'Refutation pass (MANDATORY' stages/02-blind-review.md || { echo "FAIL: stage 02 is missing the mandatory refutation pass"; exit 1; }

# Stage 02b's contract: a gated-complete comment harvest, the promise ledger, the
# thread-state pass, and the eight verdicts including the two the truncation and
# supersession incidents added.
for needle in \
    'tools/discussion-coverage' \
    'tools/commitment-scan' \
    'tools/thread-state' \
    'Declared: N' \
    'A truncated read is not a reconciliation' \
    'ANSWERED IN COMMENT ONLY' \
    'NON-ANSWER' \
    'STALE ANSWER' \
    'DECIDED AGAINST' \
    'VOID (SUPERSEDED TEXT)' \
    'REPLY: NUDGE' \
    'REPLY: RE-ASK' \
    'REPLY: FLAG STALE' \
    'REPLY: LAND IN BODY' \
    'LAST comment, never its first'
do
    grep -qF "$needle" stages/02b-comment-pass.md || { echo "FAIL: stage 02b is missing its contract clause: $needle"; exit 1; }
done

# Stage 04's contract: consequence tiers with a capped tier 1, exact block anchors,
# reply-vs-new-thread routing, the single drift ask, and untagged drafts.
for needle in \
    'Tier 1 - disaster if it ships unresolved' \
    'Tier 1 is capped at 5 items' \
    'Tier 2 - must share' \
    'Tier 3 - everything else, in priority order' \
    'DECIDED AGAINST' \
    'VOID (SUPERSEDED TEXT)' \
    'fetch-block-ids' \
    'Never invent, guess, or approximate an anchor' \
    'open a second thread' \
    'Land in the body' \
    'Thread: new thread' \
    'No @mention of anyone' \
    'strips the `#block`'
do
    grep -qF "$needle" stages/04-handoff.md || { echo "FAIL: stage 04 is missing its contract clause: $needle"; exit 1; }
done

# Stage 04 must consume 02b's verdicts rather than re-deriving them. Re-deriving
# would put reconciliation behind no completeness gate again.
grep -q '02b-comment-pass/output/dispositions.md' stages/04-handoff.md || { echo "FAIL: stage 04 does not consume 02b's dispositions"; exit 1; }
grep -q '02b-comment-pass/output/drift-ledger.md' stages/04-handoff.md || { echo "FAIL: stage 04 does not consume 02b's drift ledger"; exit 1; }

# Comments are readable in 02b and 04 only. Stages 01 and 02 must not read them -
# that is what makes the blind review blind by construction rather than by promise.
for s in stages/01-gather.md stages/02-blind-review.md; do
    if grep -qE 'notion-get-comments|include_discussions: true' "$s"; then
        grep -qE 'never|not|Do \*\*not\*\*|must never' "$s" || {
            echo "FAIL: $s references comment-reading without forbidding it"; exit 1; }
    fi
done
grep -q 'notion-get-comments' stages/02b-comment-pass.md || { echo "FAIL: stage 02b does not read the live comments"; exit 1; }

# No stage may contain an ICM-CALL comment: this skill makes no execution-spec
# call, so any (even an example) would force a permanent audit deviation.
for s in stages/*.md; do
    if grep -q '<!-- ICM-CALL' "$s"; then
        echo "FAIL: $s contains an ICM-CALL comment"; exit 1
    fi
done

echo ok
