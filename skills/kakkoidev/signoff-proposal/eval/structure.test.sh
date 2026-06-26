#!/bin/sh
# Structural eval for signoff-proposal. Model-mediated skill (no tools/ scripts),
# so this eval does NOT assert proposal content - it guards the scaffolding:
# SKILL.md, stage contracts, the publish gate, and namespace references.
# Runs from the skill dir (icm.sh eval cwd's here). Exit 0 = pass.
set -eu

test -f SKILL.md || { echo "FAIL: SKILL.md missing"; exit 1; }
grep -q '^name: signoff-proposal$' SKILL.md || { echo "FAIL: SKILL.md name frontmatter"; exit 1; }
grep -q 'kakkoidev/signoff-proposal' SKILL.md || { echo "FAIL: SKILL.md namespace ref"; exit 1; }

for s in 01-gather 02-compose 03-publish; do
    test -s "stages/$s.md" || { echo "FAIL: stages/$s.md missing or empty"; exit 1; }
    grep -q 'ICM-TOOLS expect=' "stages/$s.md" || { echo "FAIL: stages/$s.md missing ICM-TOOLS contract"; exit 1; }
done

# The publish stage must keep its pre-publish gate: proposal.md must exist before
# any notion create/update. Stripping it would let an empty publish through.
grep -q 'ICM-GATE' stages/03-publish.md || { echo "FAIL: stage 03 missing ICM-GATE publish guard"; exit 1; }

echo ok
