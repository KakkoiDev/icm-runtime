#!/bin/sh
# Eval: tools/show-telemetry reifies and displays the four-field per-stage token
# accounting against a synthetic run (stages 01-02 closed). No model, no network.
# Runs from the skill dir; exit 0 = pass.
set -u

base="${TMPDIR:-/tmp}"
if ( : > "$base/.icmdemo_wtest.$$" ) 2>/dev/null; then rm -f "$base/.icmdemo_wtest.$$"; else base="$PWD/.eval-tmp"; fi
mkdir -p "$base"
trap 'rm -rf "$PWD/.eval-tmp"' EXIT INT TERM

ICM="${ICM_SH:-$(cd ../../icm/runtime 2>/dev/null && pwd)/icm.sh}"
[ -f "$ICM" ] || { echo "FAIL: cannot find icm.sh at $ICM"; exit 1; }
TOOL="$PWD/tools/show-telemetry"

sb=$(mktemp -d "$base/icm-st.XXXXXX") || { echo "FAIL: mktemp under $base"; exit 1; }
out=$(
    HOME="$sb"; export HOME
    cd "$sb" || exit 3
    run=$("$ICM" init kakkoidev/icm-demo 2>/dev/null) || exit 4
    printf x > "$run/01-lifecycle/output/o.md"
    printf x > "$run/02-enforcement/output/o.md"
    "$ICM" stage-done kakkoidev/icm-demo --stage 01-lifecycle >/dev/null 2>&1 || exit 5
    "$ICM" stage-done kakkoidev/icm-demo --stage 02-enforcement >/dev/null 2>&1 || exit 5
    ICM_SH="$ICM" "$TOOL" 2>&1
)
rc=$?
rm -rf "$sb"
[ "$rc" -eq 0 ] || { echo "FAIL: show-telemetry exited $rc"; printf '%s\n' "$out"; exit 1; }

need() { printf '%s\n' "$out" | grep -Eq -- "$2" || { echo "FAIL: missing $1 (/$2/)"; printf '%s\n' "$out"; exit 1; }; }
need "reify section"          'REIFY TELEMETRY'
need "per-stage events"       'PER-STAGE TELEMETRY EVENTS'
need "stage_done event shown" '"type":"stage_done","stage":"01-lifecycle"'
need "four token fields"      'tokens_in.*cache_creation.*cache_read.*tokens_out'
need "completed"              'show-telemetry complete'
echo "ok"
