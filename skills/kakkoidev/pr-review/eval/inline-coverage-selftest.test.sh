#!/bin/sh
# Self-test for eval-heldout/inline-comment-coverage.test.sh: builds synthetic run dirs
# (modeled on SOBA-103 #24618: 3 findings, only F1 diff-introduced and merge-relevant)
# and asserts the held-out check passes the correct shape and bites every mutation -
# noise posted inline, a real finding suppressed, a missing reason, a skipped value
# gate, an unaccounted finding. Runs from the skill dir. Exit 0 = pass.
set -eu

check="eval-heldout/inline-comment-coverage.test.sh"
test -x "$check" || { echo "FAIL: $check missing or not executable"; exit 1; }

tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT

# Build a synthetic run dir. Args: name, coverage line, inline comment count (json/ndjson
# rows), findings.md body (via stdin).
mkrun() {
    d="$tmp/$1"; cov="$2"; n="$3"
    mkdir -p "$d/04-review/output" "$d/06-report/output"
    cat > "$d/04-review/output/findings.md"
    i=0
    : > "$d/06-report/output/review-comments.ndjson"
    printf '[' > "$d/06-report/output/review-comments.json"
    while [ "$i" -lt "$n" ]; do
        i=$((i + 1))
        printf '{"path":"a.ts","snippet":"s%s","severity":"LOW","body":"**F%s - LOW - scope.** One concise sentence."}\n' "$i" "$i" \
            >> "$d/06-report/output/review-comments.ndjson"
        [ "$i" -gt 1 ] && printf ',' >> "$d/06-report/output/review-comments.json"
        printf '{"path":"a.ts","line":%s,"side":"RIGHT","body":"b"}' "$i" >> "$d/06-report/output/review-comments.json"
    done
    printf ']' >> "$d/06-report/output/review-comments.json"
    { printf 'Findings coverage: %s\n\nVERIFIED: PASS\n' "$cov"; } > "$d/06-report/output/report-receipt.md"
    echo "$d"
}

findings_ok() {
    cat <<'EOF'
## F1 - LOW - scope
Value: introduced-by-diff=yes in-scope=yes merge-decision=yes floor=pass -> proposed: inline
## F2 - LOW - robustness
Value: introduced-by-diff=no in-scope=no merge-decision=no floor=fail -> proposed: report-only(pre-existing)
## F3 - MEDIUM - test coverage
Value: introduced-by-diff=no in-scope=yes merge-decision=no floor=fail -> proposed: report-only(test-nag on zero-test area)
EOF
}

expect() { # expect <pass|fail> <name> <run-dir> <why>
    if out=$(ICM_RUN_DIR="$3" sh "$check" 2>&1); then got=pass; else got=fail; fi
    [ "$got" = "$1" ] || { echo "FAIL: fixture '$2' expected $1, got $got ($4). Check said: $out"; exit 1; }
}

# The #24618 target shape: F1 inline (concise), F2/F3 never reach the PR, 1 inline total.
d=$(findings_ok | mkrun good 'F1:inline F2:report-only(pre-existing pattern, out of scope) F3:dropped(vacuous - asserts a deleted function is not called)' 1)
expect pass good "$d" "the calibration target from #24618"

# Precision: floor=fail posted inline (the incident - noise reached Ahmed).
d=$(findings_ok | mkrun noisy 'F1:inline F2:inline F3:inline' 3)
expect fail noisy "$d" "floor=fail findings posted inline must fail"

# Anti-over-filter: floor=pass demoted to report-only (a real diff-introduced finding suppressed).
d=$(findings_ok | mkrun suppressed 'F1:report-only(too chatty) F2:report-only(pre-existing) F3:dropped(vacuous)' 0)
expect fail suppressed "$d" "a floor=pass finding demoted to report-only must fail"

# Reasonless disposition token.
d=$(findings_ok | mkrun reasonless 'F1:inline F2:report-only F3:dropped(vacuous)' 1)
expect fail reasonless "$d" "report-only without a (reason) must fail"

# Value gate skipped entirely (findings have no Value/floor lines).
d=$(printf '## F1 - LOW - scope\n## F2 - LOW - robustness\n## F3 - MEDIUM - tests\n' | mkrun ungated 'F1:inline F2:report-only(pre-existing) F3:dropped(vacuous)' 1)
expect fail ungated "$d" "findings without floor= Value lines must fail"

# Completeness (the round-1 freeze): a finding absent from the coverage line.
d=$(findings_ok | mkrun unaccounted 'F1:inline F2:report-only(pre-existing)' 1)
expect fail unaccounted "$d" "a finding missing from the coverage line must fail"

# Over-claim: coverage says inline but the anchored payload is short.
d=$(findings_ok | mkrun overclaim 'F1:inline F2:report-only(pre-existing) F3:dropped(vacuous)' 0)
expect fail overclaim "$d" "claimed :inline with an empty payload must fail"

echo "ok: inline-coverage self-test (1 pass shape, 6 mutations bitten)"
