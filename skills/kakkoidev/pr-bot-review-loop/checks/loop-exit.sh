#!/bin/sh
# Gate for stage 03's Write (the close output). Executed by icm.sh check_run with
# cwd = the 03-close stage dir, so paths are relative to it.
#
# Passes only when the loop has actually converged: `ledger-audit --mode converged` -
# every round fired (R1), the last round was quiet (R2), every finding has a disposition
# and every refusal reached the PR body (R3/R6), every fix is revert-proven (R4), the
# last round reviewed the current head (R7/R9), nothing was pushed after it (R9), and no
# thread is left open or unanswered (R10).
#
# R11 (collapsing superseded bot reports) is deliberately NOT gated here: cleanup is the
# closing step, performed inside 03 once the loop has converged, so it cannot be a
# precondition for entering 03. `ledger-audit --mode closed` checks it at the end of the
# stage instead.
#
# Hermetic: no network, no gh. Freshness of the head comparison comes from
# `gather-round --head-only`, which wrote exit-head.tsv with an observed_at stamp - a gate
# that shells out to gh would cost an approval click on every Write and can wedge on a
# network blip.
#
# Deterministic, fail-closed, no deps beyond POSIX sh + awk.
set -eu

out=../02-round/output
tool=${LOOP_TOOLS:-$HOME/.agents/skills/kakkoidev/pr-bot-review-loop/tools}/ledger-audit

for f in rounds.tsv ledger.tsv pr-body.md exit-head.tsv; do
    [ -s "$out/$f" ] || { echo "loop not closable: $out/$f is missing or empty (stage 02 not finished)"; exit 1; }
done
[ -x "$tool" ] || { echo "loop-exit: ledger-audit not found at $tool (set LOOP_TOOLS)"; exit 1; }

if "$tool" --rounds "$out/rounds.tsv" --ledger "$out/ledger.tsv" --pr-body "$out/pr-body.md" \
        --exit-head "$out/exit-head.tsv" --mode converged; then
    echo "ok: loop converged"
else
    echo "loop has NOT converged - the FAIL rows above name the rule; run another round"
    exit 1
fi
