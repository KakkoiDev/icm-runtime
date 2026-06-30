#!/bin/sh
# Structural eval for pr-review: the 5 stages, their ICM-TOOLS declarations, the
# ordering gates, the deterministic tools, the frozen scars lens, and a ## Outputs
# table per stage (so icm-improve has expectations to grade). Runs from the skill
# dir. Exit 0 = pass.
set -eu

test -f SKILL.md || { echo "FAIL: SKILL.md missing"; exit 1; }
grep -q '^name: pr-review$' SKILL.md || { echo "FAIL: SKILL.md name frontmatter"; exit 1; }

STAGES="01-context 02-links 03-runtime-evidence 04-review 05-verify 06-report"
for s in $STAGES; do
    f="stages/$s.md"
    test -s "$f" || { echo "FAIL: $f missing or empty"; exit 1; }
    grep -q '<!-- ICM-TOOLS expect=' "$f" || { echo "FAIL: $f missing ICM-TOOLS"; exit 1; }
    grep -q '^## Outputs' "$f" || { echo "FAIL: $f missing ## Outputs"; exit 1; }
    grep -q "stage-done kakkoidev/pr-review --stage $s" "$f" || { echo "FAIL: $f missing its stage-done marker"; exit 1; }
done

# Ordering gates: each stage after 01 gates on the PRIOR stage's output existing.
# Grounding (03) precedes review (04): review gates on runtime-evidence, not the diff alone.
grep -q 'ICM-GATE .*run="test -s ../01-context/output/links.tsv"' stages/02-links.md || { echo "FAIL: 02 gate must require 01 links.tsv"; exit 1; }
grep -q 'ICM-GATE .*run="test -s ../02-links/output/link-graph.md"' stages/03-runtime-evidence.md || { echo "FAIL: 03 gate must require 02 link-graph.md"; exit 1; }
grep -q 'ICM-GATE .*run="test -s ../03-runtime-evidence/output/runtime-evidence.md"' stages/04-review.md || { echo "FAIL: 04 gate must require 03 runtime-evidence.md"; exit 1; }
grep -q 'ICM-GATE .*run="test -s ../04-review/output/findings.md"' stages/05-verify.md || { echo "FAIL: 05 gate must require 04 findings.md"; exit 1; }
grep -q 'ICM-GATE .*run="test -s ../05-verify/output/verification.md"' stages/06-report.md || { echo "FAIL: 06 gate must require 05 verification.md"; exit 1; }

# C1: the runtime-evidence stage runs the deterministic grounding tool.
grep -q 'gather-runtime-evidence' stages/03-runtime-evidence.md || { echo "FAIL: 03-runtime-evidence must invoke gather-runtime-evidence (C1)"; exit 1; }

# Deterministic tools present and executable.
for t in tools/gather-pr tools/fetch-web tools/gather-runtime-evidence; do
    test -x "$t" || { echo "FAIL: $t missing or not executable"; exit 1; }
done

# C0: gather-pr seals the diff (reproducible review artifact, not an ad-hoc re-fetch).
grep -q 'pr.diff' tools/gather-pr || { echo "FAIL: gather-pr must write output/pr.diff (C0)"; exit 1; }

# Scars lens frozen into the skill.
test -s references/scars.md || { echo "FAIL: references/scars.md missing"; exit 1; }

# No ICM-CALL: this skill's tool calls are not arg-verified, and a scraped
# ICM-CALL with no matching real call is a permanent audit deviation.
if grep -rq '<!-- ICM-CALL' stages/; then echo "FAIL: unexpected ICM-CALL (no arg-verified call in this skill)"; exit 1; fi

echo ok
