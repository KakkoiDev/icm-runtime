#!/bin/sh
# Eval: tools/close-run deterministically closes a run - reify, audit, seal,
# verify-seal - and indexes the stage 01-02 evidence. It must verify the seal and
# annotate the expected no-hook advisory-only deviation. No model, no network.
# Runs from the skill dir; exit 0 = pass.
set -u

base="${TMPDIR:-/tmp}"
if ( : > "$base/.icmdemo_wtest.$$" ) 2>/dev/null; then rm -f "$base/.icmdemo_wtest.$$"; else base="$PWD/.eval-tmp"; fi
mkdir -p "$base"
trap 'rm -rf "$PWD/.eval-tmp"' EXIT INT TERM

ICM="${ICM_SH:-$(cd ../../icm/runtime 2>/dev/null && pwd)/icm.sh}"
[ -f "$ICM" ] || { echo "FAIL: cannot find icm.sh at $ICM"; exit 1; }
TOOL="$PWD/tools/close-run"

sb=$(mktemp -d "$base/icm-cr.XXXXXX") || { echo "FAIL: mktemp under $base"; exit 1; }
out=$(
    HOME="$sb"; export HOME
    cd "$sb" || exit 3
    run=$("$ICM" init kakkoidev/icm-demo 2>/dev/null) || exit 4
    # Seed stage 01-02 evidence and close every stage, so audit/seal have a real run.
    printf 'lifecycle evidence\n' > "$run/01-lifecycle/output/lifecycle.md"
    printf 'enforcement evidence\n' > "$run/02-enforcement/output/enforcement.md"
    printf 'telemetry evidence\n' > "$run/03-telemetry-seal/output/telemetry.md"
    for st in 01-lifecycle 02-enforcement 03-telemetry-seal; do
        "$ICM" stage-done kakkoidev/icm-demo --stage "$st" >/dev/null 2>&1 || exit 5
    done
    ICM_SH="$ICM" "$TOOL" 2>&1
)
rc=$?
rm -rf "$sb"
[ "$rc" -eq 0 ] || { echo "FAIL: close-run exited $rc"; printf '%s\n' "$out"; exit 1; }

need() { printf '%s\n' "$out" | grep -Eq -- "$2" || { echo "FAIL: missing $1 (/$2/)"; printf '%s\n' "$out"; exit 1; }; }
need "reify section"        'REIFY TELEMETRY'
need "audit section"        'AUDIT \(icm.sh audit\)'
need "advisory-only note"   'NOTE on the one audit deviation'
need "seal verified"        'SEAL OK '
need "evidence index"       'EVIDENCE INDEX'
need "indexed 01 evidence"  '\[present\] .*01-lifecycle/output/lifecycle\.md'
need "indexed 02 evidence"  '\[present\] .*02-enforcement/output/enforcement\.md'
need "indexed 03 evidence"  '\[present\] .*03-telemetry-seal/output/telemetry\.md'
need "completed"            'close-run complete'
echo "ok"
