#!/bin/sh
# Structural eval for pr-bot-review-loop: the three stages and their gates, the
# deterministic tools, and - the part that matters - that all twelve rules are still
# present WITH their reasons and their source PRs. The rules are the skill; a rule quietly
# trimmed to "keep it tight" is the whole failure recurring. Runs from the skill dir.
set -eu

test -f SKILL.md || { echo "FAIL: SKILL.md missing"; exit 1; }
grep -q '^name: pr-bot-review-loop$' SKILL.md || { echo "FAIL: SKILL.md name frontmatter"; exit 1; }

STAGES="01-preflight 02-round 03-close"
for s in $STAGES; do
    f="stages/$s.md"
    test -s "$f" || { echo "FAIL: $f missing or empty"; exit 1; }
    grep -q '<!-- ICM-TOOLS expect=' "$f" || { echo "FAIL: $f missing ICM-TOOLS"; exit 1; }
    grep -q '^## Outputs' "$f" || { echo "FAIL: $f missing ## Outputs"; exit 1; }
    grep -q "stage-done kakkoidev/pr-bot-review-loop --stage $s" "$f" \
        || { echo "FAIL: $f missing its stage-done marker"; exit 1; }
done

# Ordering gates: 02 needs preflight; 03 is gated on convergence itself.
grep -q 'ICM-GATE .*run="test -s ../01-preflight/output/preflight.md"' stages/02-round.md \
    || { echo "FAIL: 02 must gate on 01's preflight"; exit 1; }
grep -q 'ICM-GATE .*run="checks/loop-exit.sh"' stages/03-close.md \
    || { echo "FAIL: 03 must gate on checks/loop-exit.sh (the convergence gate)"; exit 1; }
test -x checks/loop-exit.sh || { echo "FAIL: checks/loop-exit.sh missing or not executable"; exit 1; }

for t in tools/verify-request-fired tools/gather-round tools/gather-ci \
         tools/check-revert-proof tools/ledger-audit tools/mark-superseded \
         tools/gather-requests; do
    test -x "$t" || { echo "FAIL: $t missing or not executable"; exit 1; }
done

# The captain's diagram is reproduced in the skill, not paraphrased.
grep -q '```mermaid' SKILL.md || { echo "FAIL: SKILL.md must carry the process diagram"; exit 1; }
for node in '人間がAIに機能を依頼' '自前のAIレビュー' 'リモートのClaude自動レビュー' \
            'ローカルAIが監視' '人間がAIのコードをレビュー'; do
    grep -q "$node" SKILL.md || { echo "FAIL: the diagram is missing the node '$node'"; exit 1; }
done

# ---- the twelve rules, each with its reason ----
rules="references/loop-rules.md"
test -s "$rules" || { echo "FAIL: $rules missing"; exit 1; }
n=1
while [ "$n" -le 12 ]; do
    grep -q "^## R$n - " "$rules" || { echo "FAIL: rule R$n missing from $rules"; exit 1; }
    n=$((n + 1))
done
# 12 rules, 12 reasons: a rule without its reason gets deleted by the next reader.
whys=$(grep -c '^\*\*Why:\*\*' "$rules")
[ "$whys" -ge 12 ] || { echo "FAIL: only $whys rules carry a **Why:** - every rule needs its reason"; exit 1; }
# The incidents the rules came from, by number, so they cannot decay into folklore.
for pr in 26203 26204 26205 26269; do
    grep -q "$pr" "$rules" || { echo "FAIL: $rules no longer cites PR $pr"; exit 1; }
done

# ---- the specific rules that are easiest to lose ----
grep -qi 'no round cap' "$rules" || { echo "FAIL: R2's no-round-cap must survive verbatim"; exit 1; }
grep -q '@claude' "$rules" || { echo "FAIL: R1 must name the literal @claude mention"; exit 1; }
grep -q 'toHaveBeenCalledWith' "$rules" || { echo "FAIL: R4 must keep the toHaveBeenCalledWith trap"; exit 1; }
grep -q 'toStrictEqual' "$rules" || { echo "FAIL: R4 must keep the toStrictEqual fix"; exit 1; }
grep -qi 'declaring the loop done is a defect' "$rules" || { echo "FAIL: R9 must keep the push-then-review rule"; exit 1; }
grep -qi 'minimizeComment' "$rules" || { echo "FAIL: R11 must name the minimizeComment mechanism"; exit 1; }
grep -qi 'OUTDATED' "$rules" || { echo "FAIL: R11 must name the OUTDATED classifier"; exit 1; }
grep -qi 'gh-axi' "$rules" || { echo "FAIL: R11/R12 must name the approved wrapper route"; exit 1; }
grep -qi 'aliases' "$rules" || { echo "FAIL: R11 must keep the one-call batching (one approval)"; exit 1; }
grep -qi 'pending draft' "$rules" || { echo "FAIL: R11 must keep the never-touch-a-human-draft guardrail"; exit 1; }
grep -qi 'after the loop converges' "$rules" || { echo "FAIL: R11's ordering (cleanup only after convergence) must survive"; exit 1; }
grep -qi 'request comment' "$rules" || { echo "FAIL: R11 must cover request-comment collapsing"; exit 1; }
grep -qi 'including the last' "$rules" || { echo "FAIL: R11 must state request comments are collapsed including the last one"; exit 1; }
grep -qi 'gather-requests' "$rules" || { echo "FAIL: R11 must name tools/gather-requests"; exit 1; }

# The scope-refusal procedure: five steps, the ticket-creator skill, no hand-made tickets.
grep -q '^## Scope-refusal procedure' "$rules" || { echo "FAIL: the scope-refusal procedure is missing"; exit 1; }
i=1
while [ "$i" -le 5 ]; do
    grep -q "^$i\. " "$rules" || { echo "FAIL: scope-refusal step $i missing"; exit 1; }
    i=$((i + 1))
done
grep -qi 'ticket-creator skill' "$rules" || { echo "FAIL: the scope-refusal procedure must name the ticket-creator skill"; exit 1; }
grep -qi 'AILAB-379' "$rules" || { echo "FAIL: the scope-refusal procedure must name AILAB-379"; exit 1; }
grep -qi 'Do not hand-create tickets' "$rules" || { echo "FAIL: the no-hand-created-tickets rule must survive"; exit 1; }

# The stages must actually route through the rules, not just co-exist with them.
grep -q 'loop-rules.md' stages/01-preflight.md || { echo "FAIL: 01 must send the reader to the rules"; exit 1; }
for r in R1 R2 R3 R4 R5 R6 R7 R8 R9 R10; do
    grep -q "($r)" stages/02-round.md || { echo "FAIL: stage 02 does not cite $r"; exit 1; }
done
grep -q 'R11' stages/03-close.md || { echo "FAIL: stage 03 must carry the R11 cleanup"; exit 1; }
grep -q 'R12' stages/02-round.md || { echo "FAIL: stage 02 must carry R12 before declaring a blocker"; exit 1; }

# The loop lives inside stage 02 and must not be closed between rounds.
grep -qi 'Do not close this stage between rounds' stages/02-round.md \
    || { echo "FAIL: 02 must warn against closing the stage between rounds"; exit 1; }

# The deterministic freezes.
for e in eval/ledger-audit.test.sh eval/request-fired.test.sh eval/gather-ci.test.sh \
         eval/revert-proof.test.sh eval/mark-superseded.test.sh eval/loop-exit.test.sh \
         eval/gather-requests.test.sh; do
    test -x "$e" || { echo "FAIL: $e missing or not executable"; exit 1; }
done

# No ICM-CALL: this skill's tool calls are not arg-verified, and a scraped ICM-CALL with
# no matching real call is a permanent audit deviation.
if grep -rq '<!-- ICM-CALL' stages/; then echo "FAIL: unexpected ICM-CALL"; exit 1; fi

echo ok
