#!/bin/sh
# Eval: tools/run-report deterministically captures stage-01's run facts against a
# freshly-init'd run. No model, no network. Runs from the skill dir; exit 0 = pass.
set -u

# Writable base for the synthetic run: prefer $TMPDIR, else a repo-local dir we remove.
base="${TMPDIR:-/tmp}"
if ( : > "$base/.icmdemo_wtest.$$" ) 2>/dev/null; then rm -f "$base/.icmdemo_wtest.$$"; else base="$PWD/.eval-tmp"; fi
mkdir -p "$base"
trap 'rm -rf "$PWD/.eval-tmp"' EXIT INT TERM

ICM="${ICM_SH:-$(cd ../../icm/runtime 2>/dev/null && pwd)/icm.sh}"
[ -f "$ICM" ] || { echo "FAIL: cannot find icm.sh at $ICM"; exit 1; }
TOOL="$PWD/tools/run-report"

sb=$(mktemp -d "$base/icm-rr.XXXXXX") || { echo "FAIL: mktemp under $base"; exit 1; }
out=$(
    HOME="$sb"; export HOME
    cd "$sb" || exit 3
    "$ICM" init kakkoidev/icm-demo >/dev/null 2>&1 || exit 4
    ICM_SH="$ICM" "$TOOL" 2>&1
)
rc=$?
rm -rf "$sb"
[ "$rc" -eq 0 ] || { echo "FAIL: run-report exited $rc"; printf '%s\n' "$out"; exit 1; }

need() { printf '%s\n' "$out" | grep -Eq -- "$2" || { echo "FAIL: missing $1 (/$2/)"; printf '%s\n' "$out"; exit 1; }; }
need "stage order"         '^01-lifecycle$'
need "next empty stage"    'NEXT EMPTY STAGE'
need "run header json"     '"workspace": "kakkoidev/icm-demo"'
need "enforcement posture" 'ENFORCEMENT POSTURE'
need "five artifacts"      'THE FIVE THINGS THAT TRACK THIS RUN'
need "seal not yet"        '\[not yet\] .*\.icm-seals\.log'
need "completed"           'run-report complete'
echo "ok"
