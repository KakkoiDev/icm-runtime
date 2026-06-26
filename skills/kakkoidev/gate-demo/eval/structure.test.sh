#!/bin/sh
# Structural eval for gate-demo: the one stage, its gate, and the checker exist.
# Gate DENY/ALLOW mechanics themselves are covered by tests/gate.test.sh.
# Runs from the skill dir. Exit 0 = pass.
set -eu

test -f SKILL.md || { echo "FAIL: SKILL.md missing"; exit 1; }
grep -q '^name: gate-demo$' SKILL.md || { echo "FAIL: SKILL.md name frontmatter"; exit 1; }
test -s stages/01-publish.md || { echo "FAIL: stages/01-publish.md missing or empty"; exit 1; }
grep -q 'ICM-GATE tools="publish"' stages/01-publish.md || { echo "FAIL: stage 01 missing the publish gate"; exit 1; }
test -x checks/receipt.sh || { echo "FAIL: checks/receipt.sh missing or not executable"; exit 1; }

echo ok
