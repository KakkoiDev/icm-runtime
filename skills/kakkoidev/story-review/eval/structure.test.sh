#!/bin/sh
# Smoke eval for story-review: structural checks only, no run. Exit 0 = pass.
set -eu

test -f SKILL.md || { echo "FAIL: SKILL.md missing"; exit 1; }
grep -q '^name: story-review$' SKILL.md || { echo "FAIL: SKILL.md name frontmatter"; exit 1; }

for s in 01-gather 02-blind-review 03-score 04-handoff; do
    test -f "stages/$s.md" || { echo "FAIL: stages/$s.md missing"; exit 1; }
done

for t in tools/gather-schema-facts tools/gather-impl-facts tools/score-coverage tools/grounding-audit tools/check-prior-runs; do
    test -x "$t" || { echo "FAIL: $t missing or not executable"; exit 1; }
done

for h in eval-heldout/coverage-contract.test.sh eval-heldout/sibling-coverage.test.sh eval-heldout/independence-line.test.sh eval-heldout/self-audit-contract.test.sh eval-heldout/handoff-contract.test.sh; do
    test -f "$h" || { echo "FAIL: $h missing"; exit 1; }
done

for e in eval/score-coverage-block-split.test.sh eval/score-coverage-target-guard.test.sh eval/grounding-audit.test.sh; do
    test -x "$e" || { echo "FAIL: $e missing or not executable"; exit 1; }
done

for c in checks/gathered.sh checks/reviewed.sh; do
    test -x "$c" || { echo "FAIL: $c not executable"; exit 1; }
done
grep -q 'ICM-GATE' stages/02-blind-review.md || { echo "FAIL: stage 02 missing ICM-GATE"; exit 1; }
grep -q 'ICM-GATE' stages/04-handoff.md || { echo "FAIL: stage 04 missing ICM-GATE"; exit 1; }

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

# No stage may contain an ICM-CALL comment: this skill makes no execution-spec
# call, so any (even an example) would force a permanent audit deviation.
for s in stages/*.md; do
    if grep -q '<!-- ICM-CALL' "$s"; then
        echo "FAIL: $s contains an ICM-CALL comment"; exit 1
    fi
done

echo ok
