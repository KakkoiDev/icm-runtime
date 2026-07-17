#!/bin/sh
# Self-test for eval-heldout/report-contract.test.sh's value-gate additions: a
# report-only/dropped finding must be visible in the report under ITS OWN id (F1 is not
# satisfied by F10 - the prefix-collision bug), and any drafted comment (inline OR
# body-only) requires the receipt's Human handoff line. Runs from the skill dir.
# Exit 0 = pass.
set -eu

check="eval-heldout/report-contract.test.sh"
test -x "$check" || { echo "FAIL: $check missing or not executable"; exit 1; }

tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT

# Args: name, report body extra line, receipt lines (stdin). Runs are placed under a
# shared parent so the check's sibling-run prior-review scan sees only this run.
mkrun() {
    d="$tmp/$1/run"
    mkdir -p "$d/06-report/output" "$d/01-context/output"
    printf '**Verdict**: SHIP\n## 7-Point Validation\nall pass\n%s\n' "$2" > "$d/06-report/output/REVIEW-99.md"
    cat > "$d/06-report/output/report-receipt.md"
    echo "$d"
}

expect() { # expect <pass|fail> <name> <run-dir> <why>
    if out=$(ICM_RUN_DIR="$3" sh "$check" 2>&1); then got=pass; else got=fail; fi
    [ "$got" = "$1" ] || { echo "FAIL: fixture '$2' expected $1, got $got ($4). Check said: $out"; exit 1; }
}

# Good: report-only finding named in the report, handoff present.
d=$(printf 'Human handoff: read each comment, rewrite in your own words, then submit.\nFindings coverage: F1:inline F2:report-only(pre-existing)\n\nVERIFIED: PASS\n' \
    | mkrun good 'F2 stayed report-only (pre-existing).')
expect pass good "$d" "visible report-only + handoff"

# Prefix collision: coverage has F1:report-only, report mentions only F10.
d=$(printf 'Human handoff: read, rewrite, submit.\nFindings coverage: F1:report-only(pre-existing) F10:inline\n\nVERIFIED: PASS\n' \
    | mkrun prefix 'F10 was the only inline finding.')
expect fail prefix "$d" "F10 must not satisfy F1's visibility"

# Handoff required for body-only drafts too (they reach the PR via the review body).
d=$(printf 'Findings coverage: F1:body-only(no code locus)\n\nVERIFIED: PASS\n' \
    | mkrun nohandoff 'F1 detail here.')
expect fail nohandoff "$d" "a body-only draft without the handoff line must fail"

# Invisible report-only: accounted on the coverage line but absent from the report.
d=$(printf 'Human handoff: read, rewrite, submit.\nFindings coverage: F1:inline F2:report-only(pre-existing)\n\nVERIFIED: PASS\n' \
    | mkrun invisible 'only F1 is discussed.')
expect fail invisible "$d" "a report-only finding absent from the report must fail"

echo "ok: report-contract self-test (1 pass shape, 3 mutations bitten)"
