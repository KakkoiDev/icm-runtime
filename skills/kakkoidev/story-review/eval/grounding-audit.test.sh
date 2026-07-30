#!/bin/sh
# Unit test for tools/grounding-audit. Exit 0 = pass.
#
# The two properties that matter:
#   * a `## R<n>` refuted block must NEVER be counted as a surviving finding
#     (it must land in Refuted and in the survival rate denominator only) - if it
#     leaked into the numerator, killing a weak candidate would raise the score,
#     inverting the whole point of the refutation pass;
#   * a finding missing any of quote / Confidence / Evidence must read UNGROUNDED
#     and be named, so the number can never be inflated by silence.
set -eu

workdir=$(mktemp -d)
trap 'rm -rf "$workdir"' EXIT

script_dir=$(cd "$(dirname "$0")/.." && pwd)

cat > "$workdir/findings.md" <<'EOF'
Independence: fresh (no prior run on this target)

## F1 - L5 - high
> Changing an eligible estimate's status to `Ordered` creates one order
Confidence: Confirmed
Evidence: impl-facts.md - no stored status field; derived in extractTriggerData.ts
The trigger names a status the schema does not store.

## F2 - L1 - medium
No quote, no confidence, no evidence - this one must read UNGROUNDED.

## F3 - L4 - low
> a new order can be created if only archived orders exist
Confidence: Plausible
The evidence line is missing, so this is UNGROUNDED too.

## R1 - L4 - refuted
> automation can change phase without a UI
Confidence: Partly refuted
Evidence: automation-queues.service.ts blocks Inquiry -> non-Inquiry
Killed: the automation path already rejects this transition.
EOF

out=$("$script_dir/tools/grounding-audit" "$workdir/findings.md")

printf '%s\n' "$out" | grep -q '^Grounded: 1/3$' || {
    echo "FAIL: expected 'Grounded: 1/3' (F1 only), got:"; printf '%s\n' "$out"; exit 1; }
printf '%s\n' "$out" | grep -q '^Refuted: 1$' || {
    echo "FAIL: expected 'Refuted: 1', got:"; printf '%s\n' "$out"; exit 1; }
printf '%s\n' "$out" | grep -q '^Survival rate: 3/4$' || {
    echo "FAIL: expected 'Survival rate: 3/4' (R1 in the denominator only), got:"
    printf '%s\n' "$out"; exit 1; }

# R1 must not appear as a surviving finding row
printf '%s\n' "$out" | grep -qE '^\| R1 ' && {
    echo "FAIL: refuted block R1 was counted as a surviving finding"; exit 1; }

for fid in F2 F3; do
    printf '%s\n' "$out" | grep -qE "^- ${fid}:" || {
        echo "FAIL: $fid should be named under '## Ungrounded findings'"; exit 1; }
done
printf '%s\n' "$out" | grep -qE '^- F1:' && {
    echo "FAIL: F1 is fully grounded and must not be listed as ungrounded"; exit 1; }

# an invented confidence label must not be accepted
cat > "$workdir/bad-label.md" <<'EOF'
## F1 - L1 - low
> quoted text
Confidence: Definitely True
Evidence: something
EOF
out2=$("$script_dir/tools/grounding-audit" "$workdir/bad-label.md")
printf '%s\n' "$out2" | grep -q '^Grounded: 0/1$' || {
    echo "FAIL: an off-vocabulary Confidence label must not count as grounded, got:"
    printf '%s\n' "$out2"; exit 1; }

# empty input must be reported, not crash into a fake perfect score
: > "$workdir/empty.md"
out3=$("$script_dir/tools/grounding-audit" "$workdir/empty.md")
printf '%s\n' "$out3" | grep -q '^Grounded: 0/0$' || {
    echo "FAIL: empty findings.md should report 'Grounded: 0/0', got:"
    printf '%s\n' "$out3"; exit 1; }
printf '%s\n' "$out3" | grep -qF 'Survival rate: n/a' || {
    echo "FAIL: empty findings.md should report an n/a survival rate"; exit 1; }

echo "ok: grounding-audit counts survivors and refutations separately and names every ungrounded finding"
