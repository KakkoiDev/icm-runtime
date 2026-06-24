#!/bin/sh
# Smoke eval for icm-demo: structural checks only, no run. Exit 0 = pass.
set -eu
test -f SKILL.md || { echo "FAIL: SKILL.md missing"; exit 1; }
grep -q '^name: icm-demo$' SKILL.md || { echo "FAIL: SKILL.md name frontmatter"; exit 1; }
for s in 01-lifecycle 02-enforcement 03-telemetry-seal; do
    test -f "stages/$s.md" || { echo "FAIL: stages/$s.md missing"; exit 1; }
done
test -x tools/sandbox-tour || { echo "FAIL: tools/sandbox-tour not executable"; exit 1; }
test -x checks/ready.sh    || { echo "FAIL: checks/ready.sh not executable"; exit 1; }
# The enforcement stage must declare a real gate (the showcase's centrepiece).
grep -q 'ICM-GATE' stages/02-enforcement.md || { echo "FAIL: stage 02 missing ICM-GATE"; exit 1; }
# No stage may contain an ICM-CALL comment: audit scrapes `<!-- ICM-CALL ... -->`
# from the frozen contract, and this offline demo never makes the real call a spec
# would require, so any (even an example) forces a permanent audit deviation.
for s in stages/*.md; do
    if grep -q '<!-- ICM-CALL' "$s"; then
        echo "FAIL: $s contains an ICM-CALL comment (audit scrapes it -> permanent deviation)"; exit 1
    fi
done
echo ok
