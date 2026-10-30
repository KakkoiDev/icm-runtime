#!/bin/sh
# Structural eval for draft-report. This is a model-mediated skill (no tools/
# scripts), so this eval does NOT assert report content - it guards the
# scaffolding: a rename, a deleted stage, or a stripped contract line all fail
# here. Runs from the skill dir (icm.sh eval cwd's here). Exit 0 = pass.
set -eu

test -f SKILL.md || { echo "FAIL: SKILL.md missing"; exit 1; }
grep -q '^name: draft-report$' SKILL.md || { echo "FAIL: SKILL.md name frontmatter"; exit 1; }
grep -q 'kakkoidev/draft-report' SKILL.md || { echo "FAIL: SKILL.md namespace ref (expected kakkoidev/draft-report)"; exit 1; }

for s in 01-frame 02-draft 03-tighten; do
    test -s "stages/$s.md" || { echo "FAIL: stages/$s.md missing or empty"; exit 1; }
    grep -q 'ICM-TOOLS expect=' "stages/$s.md" || { echo "FAIL: stages/$s.md missing ICM-TOOLS contract"; exit 1; }
done

echo ok
