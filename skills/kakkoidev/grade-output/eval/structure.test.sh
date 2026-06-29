#!/bin/sh
# Structural eval for grade-output: the single grading stage, its ICM-TOOLS
# declaration, the declared grading.json output, and the deliberate absence of a
# blocking gate (grading is an LLM judgment - a deterministic gate would be
# theater). Runs from the skill dir. Exit 0 = pass.
set -eu

test -f SKILL.md || { echo "FAIL: SKILL.md missing"; exit 1; }
grep -q '^name: grade-output$' SKILL.md || { echo "FAIL: SKILL.md name frontmatter"; exit 1; }

STAGE=stages/01-grade.md
test -s "$STAGE" || { echo "FAIL: $STAGE missing or empty"; exit 1; }

grep -q '<!-- ICM-TOOLS expect="(Read|Write)" -->' "$STAGE" \
    || { echo "FAIL: stage missing ICM-TOOLS expect=\"(Read|Write)\""; exit 1; }

# Gateless by design: no ICM-GATE line anywhere in the skill's stages.
if grep -rq '<!-- ICM-GATE' stages/; then
    echo "FAIL: grade-output declares an ICM-GATE; grading has no deterministic gate by design"; exit 1
fi

grep -q 'output/grading.json' "$STAGE" || { echo "FAIL: stage does not declare output/grading.json"; exit 1; }
grep -q 'pass_rate' "$STAGE" || { echo "FAIL: grading.json schema missing summary.pass_rate"; exit 1; }

# The grading procedure must instruct writing the verdict to output/.
grep -q 'stage-done kakkoidev/grade-output' "$STAGE" || { echo "FAIL: stage missing the mandatory stage-done command"; exit 1; }

echo ok
