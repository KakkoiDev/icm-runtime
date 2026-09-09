#!/bin/sh
# Freezes checks/loop-exit.sh: the gate that blocks 03-close until the loop has actually
# converged. Builds a fake stage layout and runs the check from the 03 stage dir, the way
# icm.sh does. Runs from the skill dir. Exit 0 = pass.
set -eu

check="checks/loop-exit.sh"
test -x "$check" || { echo "FAIL: $check missing or not executable"; exit 1; }
tools=$(cd tools && pwd)
chk=$(cd checks && pwd)/loop-exit.sh

tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT
T=$(printf '\t')
mkdir -p "$tmp/run/02-round/output" "$tmp/run/03-close"
o="$tmp/run/02-round/output"

seed_converged() {
    printf '1%sFIRED%ssha1%ssha1%sno%s2%s2%s0%s0%ssha2%sdone\n' "$T" "$T" "$T" "$T" "$T" "$T" "$T" "$T" "$T" "$T" > "$o/rounds.tsv"
    printf '2%sFIRED%ssha2%ssha2%sno%s0%s0%s0%s0%s-%sn/a\n'     "$T" "$T" "$T" "$T" "$T" "$T" "$T" "$T" "$T" "$T" >> "$o/rounds.tsv"
    printf '1%sF1%sHIGH%sfixed%smissing guard%sPROVEN\n' "$T" "$T" "$T" "$T" "$T" > "$o/ledger.tsv"
    printf 'nothing refused, nothing deferred\n' > "$o/pr-body.md"
    printf 'head_sha%ssha2\nobserved_at%s2026-09-09T01:00:00Z\n' "$T" "$T" > "$o/exit-head.tsv"
}

gate() { ( cd "$tmp/run/03-close" && LOOP_TOOLS="$tools" sh "$chk" 2>&1 ); }

# ---- 1. a converged loop opens the gate ----
seed_converged
if ! out=$(gate); then
    echo "FAIL: the gate must open on a converged loop:"; printf '%s\n' "$out"; exit 1
fi
printf '%s' "$out" | grep -q 'ok: loop converged' \
    || { echo "FAIL: expected the converged message, got: $out"; exit 1; }

# ---- 2. a noisy last round keeps it shut ----
seed_converged
printf '3%sFIRED%ssha2%ssha2%sno%s1%s1%s0%s0%s-%sn/a\n' "$T" "$T" "$T" "$T" "$T" "$T" "$T" "$T" "$T" "$T" >> "$o/rounds.tsv"
if out=$(gate); then
    echo "FAIL: the gate must stay shut while a round still returns findings"; printf '%s\n' "$out"; exit 1
fi

# ---- 3. a push after the last review keeps it shut (R9) ----
seed_converged
printf '3%sFIRED%ssha2%ssha2%sno%s0%s0%s0%s0%ssha3%sdone\n' "$T" "$T" "$T" "$T" "$T" "$T" "$T" "$T" "$T" "$T" >> "$o/rounds.tsv"
if out=$(gate); then
    echo "FAIL: the gate must stay shut when the loop's last action was a push"; printf '%s\n' "$out"; exit 1
fi

# ---- 4. a missing stage-02 artifact is a clear message, not a crash ----
seed_converged
rm -f "$o/exit-head.tsv"
out=$(gate) && { echo "FAIL: a missing exit-head.tsv must keep the gate shut"; exit 1; }
printf '%s' "$out" | grep -q 'exit-head.tsv' \
    || { echo "FAIL: the gate must name the missing file, got: $out"; exit 1; }

# ---- 5. the gate does NOT require the R11 cleanup - that happens inside 03, after it ----
seed_converged
out=$(gate)
if printf '%s' "$out" | grep -qi 'superseded'; then
    echo "FAIL: the convergence gate must not demand the closing cleanup"; exit 1
fi

# ---- 6. the gate is hermetic: it must not shell out to a GitHub CLI ----
if grep -v '^[[:space:]]*#' "$chk" | grep -qE '(^|[^-a-zA-Z])gh(-axi)?[[:space:]]'; then
    echo "FAIL: the gate must not call a GitHub CLI (an approval click per Write)"; exit 1
fi

echo ok
