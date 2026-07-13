#!/bin/sh
# Deterministic freeze of the diverged-state gate (checks/review-precondition.sh):
# stage 04's review Write is blocked on divergence unless a valid seal-decision records
# the target (default sealed; working-tree needs human_approved=yes). It also still
# requires the stage-03 grounding. SOBA-285 #24370 review 4. Runs from the skill dir.
set -eu

CHECKER="$(pwd)/checks/review-precondition.sh"
test -x "$CHECKER" || { echo "FAIL: $CHECKER missing or not executable"; exit 1; }

setup() { # $1 = run root; minimal layout with stage-03 grounding present
  mkdir -p "$1/01-context/output" "$1/03-runtime-evidence/output" "$1/04-review"
  echo grounding > "$1/03-runtime-evidence/output/runtime-evidence.md"
  echo impact > "$1/03-runtime-evidence/output/impact.md"
}
seal() {     printf 'pr_head_sha\taaa\nlocal_head_sha\t%s\ndirty\tno\ndiverged\t%s\n' "$2" "$3" > "$1/01-context/output/seal.tsv"; }
decision() { printf 'target\t%s\nhuman_approved\t%s\nnote\ttest\n' "$2" "$3" > "$1/01-context/output/seal-decision.tsv"; }
gate() { ( cd "$1/04-review" && sh "$CHECKER" >/dev/null 2>&1 ); }

pass=0; fail=0
expect() { # $1 label  $2 pass|deny  $3 run-root
  if gate "$3"; then got=pass; else got=deny; fi
  if [ "$got" = "$2" ]; then echo "ok: $1 -> $got"; pass=$((pass + 1))
  else echo "FAIL: $1 expected $2 got $got"; fail=$((fail + 1)); fi
}

T=$(mktemp -d)
trap 'find "$T" -delete 2>/dev/null || true' EXIT

r="$T/c1"; setup "$r"; seal "$r" aaa no;                              expect "diverged=no (no decision needed)"          pass "$r"
r="$T/c2"; setup "$r"; seal "$r" bbb yes;                             expect "diverged, no seal-decision"                deny "$r"
r="$T/c3"; setup "$r"; seal "$r" bbb yes; decision "$r" sealed no;    expect "diverged, target=sealed"                   pass "$r"
r="$T/c4"; setup "$r"; seal "$r" bbb yes; decision "$r" working-tree yes; expect "diverged, working-tree + approved"     pass "$r"
r="$T/c5"; setup "$r"; seal "$r" bbb yes; decision "$r" working-tree no;  expect "diverged, working-tree NOT approved"   deny "$r"
r="$T/c6"; setup "$r"; : > "$r/03-runtime-evidence/output/runtime-evidence.md"; seal "$r" aaa no; expect "grounding missing" deny "$r"
r="$T/c7"; setup "$r"; seal "$r" bbb yes; decision "$r" bogus no;     expect "diverged, invalid target"                  deny "$r"

[ "$fail" -eq 0 ] || { echo "FAILED: $fail case(s)"; exit 1; }
echo "ok: review-precondition gate ($pass cases)"
