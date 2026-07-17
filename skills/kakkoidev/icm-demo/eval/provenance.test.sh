#!/bin/sh
# Eval: init records skill provenance - a DERIVED skill_ref (git SHA of the skill
# workspace, "unknown" outside git) and a skill_dirty flag - in both run.json (the
# sealed static header) and the run_init event. Lineage is derived, never
# hand-maintained: a declared version number rots on the first forgotten bump.
# When dirty=yes the frozen copies in the run dir stay the ground truth; the
# provenance line just labels them. Runs from the skill dir; exit 0 = pass.
set -u

base="${TMPDIR:-/tmp}"
if ( : > "$base/.icmdemo_ptest.$$" ) 2>/dev/null; then rm -f "$base/.icmdemo_ptest.$$"; else base="$PWD/.eval-tmp"; fi
mkdir -p "$base"
trap 'rm -rf "$PWD/.eval-tmp"' EXIT INT TERM

ICM="${ICM_SH:-$(cd ../../icm/runtime 2>/dev/null && pwd)/icm.sh}"
[ -f "$ICM" ] || { echo "FAIL: cannot find icm.sh at $ICM"; exit 1; }

sb=$(mktemp -d "$base/icm-prov.XXXXXX") || { echo "FAIL: mktemp under $base"; exit 1; }
run=$(
    HOME="$sb"; export HOME
    cd "$sb" || exit 3
    "$ICM" init kakkoidev/icm-demo 2>"$sb/init.err"
) || { echo "FAIL: init failed"; cat "$sb/init.err" 2>/dev/null; rm -rf "$sb"; exit 1; }
run="$sb/$run"

fail() { echo "FAIL: $1"; rm -rf "$sb"; exit 1; }

# Both artifacts carry the fields, with non-empty values.
ref_json=$(sed -n 's/.*"skill_ref"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/p' "$run/telemetry/run.json" | head -1)
dirty_json=$(sed -n 's/.*"skill_dirty"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/p' "$run/telemetry/run.json" | head -1)
[ -n "$ref_json" ] || fail "run.json has no skill_ref (provenance not recorded)"
case "$dirty_json" in yes|no) : ;; *) fail "run.json skill_dirty must be yes|no (got: '${dirty_json:-<empty>}')" ;; esac

grep -q '"type":"run_init".*"skill_ref":"'"$ref_json"'"' "$run/telemetry/events.jsonl" \
    || fail "run_init event missing skill_ref (or it disagrees with run.json)"
grep -q '"type":"run_init".*"skill_dirty":"'"$dirty_json"'"' "$run/telemetry/events.jsonl" \
    || fail "run_init event missing skill_dirty (or it disagrees with run.json)"

# The stderr info line surfaces the same lineage to the operator.
grep -q "skill: kakkoidev/icm-demo @ $ref_json (dirty: $dirty_json)" "$sb/init.err" \
    || fail "init stderr missing the 'skill: <ws> @ <sha> (dirty: ...)' line"

# In this repo the skill dir IS git-tracked, so the ref must be a real short SHA,
# and it must match the actual HEAD of the skill workspace.
if command -v git >/dev/null 2>&1 && head_sha=$(git -C "$PWD" rev-parse --short HEAD 2>/dev/null); then
    [ "$ref_json" = "$head_sha" ] || fail "skill_ref '$ref_json' != skill workspace HEAD '$head_sha'"
fi

rm -rf "$sb"
echo ok
