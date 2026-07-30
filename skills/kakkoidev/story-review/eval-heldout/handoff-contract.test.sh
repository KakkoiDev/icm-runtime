#!/bin/sh
# Output-contract regression check, held out from the LLM grader.
#
# The failure this encodes is real and cost three stories' worth of work: on the
# 2026-07-29 run, the per-story deliverables for US-03/US-05/US-06 were written to
# a scratchpad OUTSIDE the sealed run. They were absent from the archive by the
# time anyone looked, so those stories could not be audited at all. Stage 04 makes
# the deliverable a sealed stage output; this check proves it is there, complete,
# and that every surviving finding got a disposition rather than being quietly
# dropped on the way from findings.md to the handoff.
#
# It checks completeness and shape, never the quality of the questions.
# Reads the produced run output via $ICM_RUN_DIR. Exit 0 = pass.
set -eu

[ -n "${ICM_RUN_DIR:-}" ] || { echo "FAIL: ICM_RUN_DIR not set (run via icm-improve held-out)"; exit 1; }

handoff="$ICM_RUN_DIR/04-handoff/output/handoff.md"
findings="$ICM_RUN_DIR/02-blind-review/output/findings.md"

[ -f "$handoff" ] || { echo "FAIL: handoff.md not found at $handoff - stage 04 produced no deliverable"; exit 1; }
[ -f "$findings" ] || { echo "FAIL: findings.md not found at $findings"; exit 1; }

for section in "## Must raise" "## Should raise" "## Optional" "## Refuted" "## Limits"; do
    grep -qF "$section" "$handoff" || { echo "FAIL: missing section '$section' in $handoff"; exit 1; }
done

# Every surviving finding must be accounted for - a finding that exists in
# findings.md but not in the handoff is silently dropped scope, which is the exact
# class of loss this stage was added to stop.
missing=""
for fid in $(grep -oE '^## F[0-9]+' "$findings" | grep -oE 'F[0-9]+' | sort -u); do
    grep -qE "(^|[^A-Za-z0-9])${fid}([^0-9]|$)" "$handoff" || missing="$missing $fid"
done
[ -z "$missing" ] || { echo "FAIL: findings absent from handoff.md (silently dropped):$missing"; exit 1; }

# Same for refuted candidates: they are the evidence a precision pass happened.
missing_r=""
for rid in $(grep -oE '^## R[0-9]+' "$findings" | grep -oE 'R[0-9]+' | sort -u); do
    grep -qE "(^|[^A-Za-z0-9])${rid}([^0-9]|$)" "$handoff" || missing_r="$missing_r $rid"
done
[ -z "$missing_r" ] || { echo "FAIL: refuted candidates absent from handoff.md:$missing_r"; exit 1; }

# The grounding number must be carried into the deliverable, not left in telemetry:
# a reader deciding how much to trust the file needs it in the file.
grep -qE '^Grounded: [0-9]+/[0-9]+' "$handoff" || {
    echo "FAIL: handoff.md does not carry a 'Grounded: N/M' line from the grounding audit"
    exit 1
}

# Confidence labels must survive verbatim, not be collapsed into severity.
grep -qE '(Confirmed|Strongly supported|Supported|Plausible|Partly refuted)' "$handoff" || {
    echo "FAIL: handoff.md carries no confidence label from findings.md"
    exit 1
}

nf=$(grep -cE '^## F[0-9]+' "$findings" || true)
echo "ok: handoff.md present, all sections, all $nf finding(s) and every refuted candidate accounted for"
