#!/bin/sh
# Smoke eval for story-review: structural checks only, no run. Exit 0 = pass.
set -eu

test -f SKILL.md || { echo "FAIL: SKILL.md missing"; exit 1; }
grep -q '^name: story-review$' SKILL.md || { echo "FAIL: SKILL.md name frontmatter"; exit 1; }

for s in 01-gather 02-blind-review 03-score; do
    test -f "stages/$s.md" || { echo "FAIL: stages/$s.md missing"; exit 1; }
done

for t in tools/gather-schema-facts tools/score-coverage tools/check-prior-runs; do
    test -x "$t" || { echo "FAIL: $t missing or not executable"; exit 1; }
done

for h in eval-heldout/coverage-contract.test.sh eval-heldout/sibling-coverage.test.sh eval-heldout/independence-line.test.sh eval-heldout/self-audit-contract.test.sh; do
    test -f "$h" || { echo "FAIL: $h missing"; exit 1; }
done

test -x eval/score-coverage-block-split.test.sh || { echo "FAIL: eval/score-coverage-block-split.test.sh missing or not executable"; exit 1; }

test -x checks/gathered.sh || { echo "FAIL: checks/gathered.sh not executable"; exit 1; }
grep -q 'ICM-GATE' stages/02-blind-review.md || { echo "FAIL: stage 02 missing ICM-GATE"; exit 1; }

test -f references/answer-key.tsv || { echo "FAIL: references/answer-key.tsv missing"; exit 1; }
rows=$(($(wc -l < references/answer-key.tsv) - 1))
[ "$rows" -ge 8 ] || { echo "FAIL: answer-key.tsv has too few rows ($rows)"; exit 1; }

# No stage may contain an ICM-CALL comment: this skill makes no execution-spec
# call, so any (even an example) would force a permanent audit deviation.
for s in stages/*.md; do
    if grep -q '<!-- ICM-CALL' "$s"; then
        echo "FAIL: $s contains an ICM-CALL comment"; exit 1
    fi
done

echo ok
