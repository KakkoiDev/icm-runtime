#!/bin/sh
# Held-out check for the local-context dimension.
#
# Born from a past shared-repo PR, where ten commits in a row removed things that
# were never wrong code: a real page id and user id offered as copyable recipe values, one
# person's role vocabulary in rulings a stranger reads, a personal tool's ignore rule in the
# shared .gitignore, four throwaway browser scripts, a draft written for one audience. All
# of it compiled, linted, tested green and survived several review rounds, because it only
# reads wrong to someone who is not in that environment.
#
# NOT a tautology: the tool runs against a FROZEN offline fixture with a known answer (no
# gh, no network, no live repo). It asserts BOTH halves - that each planted signal is
# found, at the right line, across multiple hunks; and that the look-alikes stay silent,
# because a detector that reports every id and every email costs the reviewer more than it
# saves. The fixture's total is frozen at 8, so new noise fails too, not just a lost hit.
#
# Fails on these known bad reverts, one assertion each:
#   - drop the HOMEPATH regex                                            -> A1
#   - stop advancing the line counter on context lines, or advance it on
#     removed lines, or stop resetting it per hunk                       -> A1 + A7
#   - drop the bounded 32-hex / uuid rules                               -> A2
#   - drop the EMAIL rule                                                -> A3
#   - drop either branch of SCRATCH (the dir list, the draft suffix)     -> A4 / A5
#   - drop the personal-ignore rule                                      -> A6
#   - drop the vocab pass, or hardcode terms instead of reading the file -> A7
#   - drop HOMESKIP (CI and container homes)                             -> P1
#   - drop EMAILSKIP (noreply / example.com)                             -> P2
#   - drop SKIPPATH (lockfiles and generated trees)                      -> P3
#   - emit on `-` lines, or advance the counter on them                  -> A7, P4
#   - drop IGNORESKIP, or accept a non-dot ignore entry                  -> P5
#   - drop the "a Slack id contains a digit" guard                       -> P6
#   - stop excluding the lexicon file from its own scan                  -> C2
#   - swallow an awk error with `|| :` (a silent false all-clear)         -> C4
#   - drop the collected rows, or skip the report entirely, when the path pass
#     matches nothing last (the abort this tool replaced)                -> C5
#   - stay silent when the lexicon file is missing                       -> C6
# Runs from anywhere - it locates itself. Exit 0 = pass.
set -eu

HERE=$(cd "$(dirname "$0")/.." && pwd)
cd "$HERE"

LL=tools/gather-local-leakage
FIX=eval/fixtures/local-leakage
test -x "$LL" || { echo "FAIL: $LL missing or not executable"; exit 1; }
test -f "$FIX/pr.diff" || { echo "FAIL: fixture diff $FIX/pr.diff missing"; exit 1; }
test -f references/private-vocab.example.txt || { echo "FAIL: references/private-vocab.example.txt missing - the lexicon format must ship with the review tooling"; exit 1; }
test -f references/private-vocab.txt && { echo "FAIL: references/private-vocab.txt is in the skill tree - the real lexicon lives in ~/.config/icm"; exit 1; }

OUT=$(mktemp -d); trap 'rm -rf "$OUT"' EXIT
# The test's own lexicon: the two terms the fixture plants. Never the real list.
TV="$OUT/vocab.txt"
printf 'captain\nego-lite\n' > "$TV"

sh "$LL" "$FIX/pr.diff" "$OUT" "$TV" >/dev/null 2>&1 \
    || { echo "FAIL: gather-local-leakage exited non-zero on the fixture"; exit 1; }
R="$OUT/local-leakage.tsv"
test -s "$R" || { echo "FAIL: local-leakage.tsv not written"; exit 1; }

want() { # class, path, line, why
    grep -q "^$1	$2	$3	" "$R" || { echo "FAIL($4): expected $1 at $2:$3 - $5"; exit 1; }
}
deny() { # pattern, id, why
    grep -q "$1" "$R" && { echo "FAIL($2): $3"; exit 1; }
    return 0
}

# ---------------------------------------------------------------- recall (planted)
# A1 - the author's own home directory, on an added line in the FIRST hunk. The exact
#      line number is part of the assertion: it is the cheapest proof that the added /
#      context / removed walk is still correct.
want home-path skills/notion-ticket/SKILL.md 12 A1 "the absolute home path a reader cannot resolve"

# A2 - the copyable-id shape: a real-looking id offered as a copyable recipe VALUE, on the
#      same line as the placeholder form the file uses everywhere else.
want identity-value skills/notion-ticket/references/recipes.md 21 A2 "the 32-hex page id and the uuid caller id in a recipe"

# A3 - an addressable human, distinct from the bot and placeholder addresses below.
want identity-value docs/contributors.md 6 A3 "a real-looking personal address"

# A4/A5 - both branches of the scratch class: a personal-tool directory, and a file
#         whose NAME says it was written to be pasted somewhere else.
want scratch-path .ego-lite/unnamed/probe.js - A4 "a throwaway browser script committed by mistake"
want scratch-path docs/roadmap-notion-draft.md - A5 "a draft written for another audience, shipping inside the repo"

# A6 - an ignore rule for a tool only this author runs, added to the file every
#      contributor clones. A finding about the repository, not about the author.
want personal-ignore .gitignore 3 A6 "a personal tool's ignore rule in the shared .gitignore"

# A7 - a lexicon term, on an added line in the SECOND hunk, AFTER a removed line. If the
#      counter advanced on the removal or failed to reset at the hunk header this lands
#      on the wrong line and the assertion fails, so one check covers both the vocab pass
#      and the rest of the walk.
want private-vocab skills/notion-ticket/SKILL.md 45 A7 "a private role term a stranger cannot resolve"
grep -q '^private-vocab	skills/notion-ticket/SKILL.md	45	\[captain\] ' "$R" \
    || { echo "FAIL(A7b): the matched term does not lead the evidence - a reviewer cannot see which word fired, and the lexicon is not in the repo they are reading"; exit 1; }

# ------------------------------------------------------------- precision (silence)
# P1 - CI and container homes are not a person's machine. /home/runner is in almost
#      every workflow file; reporting it would bury the one row that matters.
deny '/home/runner' P1 "the CI checkout path was reported as a personal home directory"

# P2 - the bot address and the documentation placeholder are load-bearing exactly as
#      written; neither identifies anyone.
deny 'noreply' P2 "a noreply bot address was reported as an identity value"
deny 'example\.com' P2 "an example.com placeholder was reported as an identity value"

# P3 - a lockfile hash is not a personal id. Two independent guards cover the
#      package-lock line (the path exclusion and the digest-word skip); the go.sum line
#      carries a bare hash with no digest word, so it is guarded by the path exclusion
#      ALONE and fails this assertion when that exclusion is reverted on its own.
deny '^identity-value	package-lock\.json	' P3 "a lockfile integrity hash was reported as an identity value"
deny '	go\.sum	' P3 "a go.sum module hash was reported - the generated-tree exclusion regressed"

# P4 - this class is about what SHIPS. The fixture deletes a line carrying the same home
#      path A1 catches; if the parser ever emits on `-` lines it appears here.
deny 'src/removed\.ts' P4 "a REMOVED line produced a hit - the class is what the diff ships"
deny 'old-path' P4 "the deleted home path was reported - removals must never emit"

# P5 - .next/ is a project build directory, and node_modules/.cache is not a dot-entry
#      at all. Only a rule that belongs in a personal global ignore file is a finding.
deny '\.next/' P5 "a project build directory was reported as a personal ignore rule"
deny 'node_modules/\.cache' P5 "a non-dot ignore entry was reported"

# P6 - the loudest false positive this class can produce: SCREAMING_CASE constants match
#      a Slack id's shape. A real id mixes letters and digits; TIMESTAMP does not.
deny 'TIMESTAMP' P6 "an all-caps constant was reported as a Slack identifier"

# A8 - the frozen answer, checked LAST so every revert above fails on its own named
#      assertion first and this one only catches what none of them named.
grep -q '^# TOTAL: 8 local-context signals' "$R" \
    || { echo "FAIL(A8): the frozen total moved - expected 8. New noise and a lost hit both land here; re-read the rows before changing this number."; exit 1; }
grep -q 'a SIGNAL, not a finding' "$R" \
    || { echo "FAIL(A8): the totals line must say a hit is a signal - a tool that reads as a verdict gets rubber-stamped in 04"; exit 1; }

# ------------------------------------------------------------------ markers + self
# C1 - a clean diff records a SEARCHED-and-clear result, distinct from not-checked, and
#      says out loud what bounds it.
CLEAN=$(mktemp -d)
printf 'diff --git a/src/f.ts b/src/f.ts\n--- a/src/f.ts\n+++ b/src/f.ts\n@@ -1,1 +1,2 @@\n const a = 1\n+export const x = a + 1\n' > "$CLEAN/pr.diff"
sh "$LL" "$CLEAN/pr.diff" "$CLEAN/out" "$TV" >/dev/null 2>&1 \
    || { echo "FAIL(C1): gather-local-leakage failed on a clean diff"; rm -rf "$CLEAN"; exit 1; }
grep -q '^# CLEAR:' "$CLEAN/out/local-leakage.tsv" \
    || { echo "FAIL(C1): no explicit CLEAR marker - an unchecked run would look identical"; rm -rf "$CLEAN"; exit 1; }
grep -q 'bounded by the lexicon' "$CLEAN/out/local-leakage.tsv" \
    || { echo "FAIL(C1): the CLEAR marker must state what bounds it - a lexicon-bounded clear is not proof of portability"; rm -rf "$CLEAN"; exit 1; }
rm -rf "$CLEAN"

# C2 - the lexicon must never be readable FROM the reviewed repo. a past PR's first guard
#      hardcoded the words it banned inside a file that shipped, publishing the list it
#      existed to suppress. A diff that adds a private-vocab.txt must not make the tool
#      quote every term in it back into the review artifact.
SELF=$(mktemp -d)
printf 'diff --git a/references/private-vocab.txt b/references/private-vocab.txt\n--- /dev/null\n+++ b/references/private-vocab.txt\n@@ -0,0 +1,2 @@\n+captain\n+ego-lite\n' > "$SELF/pr.diff"
sh "$LL" "$SELF/pr.diff" "$SELF/out" "$TV" >/dev/null 2>&1 \
    || { echo "FAIL(C2): gather-local-leakage failed on a diff touching the lexicon"; rm -rf "$SELF"; exit 1; }
grep -q '^# CLEAR:' "$SELF/out/local-leakage.tsv" \
    || { echo "FAIL(C2): the lexicon file was scanned against itself - the tool republished the list it exists to suppress"; rm -rf "$SELF"; exit 1; }
rm -rf "$SELF"

# C3 - the lexicon is DATA, read at runtime. A tool that inlines the terms cannot be
#      tuned without editing the scanner, and puts the banned words back into a file
#      that ships with the skill.
EMPTYV=$(mktemp -d); : > "$EMPTYV/vocab.txt"
sh "$LL" "$FIX/pr.diff" "$EMPTYV/out" "$EMPTYV/vocab.txt" >/dev/null 2>&1 \
    || { echo "FAIL(C3): gather-local-leakage failed with an empty lexicon"; rm -rf "$EMPTYV"; exit 1; }
grep -q '^private-vocab	' "$EMPTYV/out/local-leakage.tsv" \
    && { echo "FAIL(C3): private-vocab rows appeared with an EMPTY lexicon file - the terms are hardcoded in the scanner"; rm -rf "$EMPTYV"; exit 1; }
rm -rf "$EMPTYV"

# C4 - a scan that ERRORS must never look like a clean diff. The tool is copied, its awk
#      broken, and the run must exit non-zero with no artifact at all: a `|| :` after the
#      scan would swallow the error and write a CLEAR, which is the most expensive bug
#      this whole dimension can have - a silent false all-clear.
BROKE=$(mktemp -d)
sed 's|^function ev(s,   t)|function ev(s,   t) { { {|' "$LL" > "$BROKE/tool"
if sh "$BROKE/tool" "$FIX/pr.diff" "$BROKE/out" "$TV" >/dev/null 2>&1; then
    echo "FAIL(C4): a broken scan exited 0"; rm -rf "$BROKE"; exit 1
fi
test -f "$BROKE/out/local-leakage.tsv" \
    && { echo "FAIL(C4): a broken scan still wrote local-leakage.tsv - an error can be read as a CLEAR"; rm -rf "$BROKE"; exit 1; }
rm -rf "$BROKE"

# C5 - a hit collected EARLY, then a last added path that is NOT a scratch path. The path
#      class is judged last, over every added path at once. The commit that added this tool
#      says the draft it replaced "exited via set -e before writing any report whenever the
#      last added path was not a scratch path", so a diff of this shape lost every hit
#      already in hand and wrote no CLEAR either. C1 is not this assertion: C1 proves an
#      EMPTY result still records a CLEAR, and a run that drops real rows and then writes
#      that same CLEAR passes C1 while reporting a leaking diff as clean - the most
#      expensive failure this dimension has. This is the only check here that plants a hit
#      and then ends the diff outside the scratch class.
LATE=$(mktemp -d)
printf 'diff --git a/docs/setup.md b/docs/setup.md\n--- a/docs/setup.md\n+++ b/docs/setup.md\n@@ -1,1 +1,2 @@\n # Setup\n+run it from /Users/someone/Code/icm/bin/tool\ndiff --git a/src/util.ts b/src/util.ts\n--- a/src/util.ts\n+++ b/src/util.ts\n@@ -1,1 +1,2 @@\n export const a = 1\n+export const b = a + 1\n' > "$LATE/pr.diff"
sh "$LL" "$LATE/pr.diff" "$LATE/out" "$TV" >/dev/null 2>&1 \
    || { echo "FAIL(C5): exited non-zero when the last added path was not a scratch path"; rm -rf "$LATE"; exit 1; }
test -s "$LATE/out/local-leakage.tsv" \
    || { echo "FAIL(C5): no report written when the last added path was not a scratch path - the run aborted and took its hits with it"; rm -rf "$LATE"; exit 1; }
grep -q '^home-path	docs/setup\.md	2	' "$LATE/out/local-leakage.tsv" \
    || { echo "FAIL(C5): the home path from the FIRST file is missing - a later non-matching path must never discard an earlier hit"; rm -rf "$LATE"; exit 1; }
grep -q '^scratch-path	' "$LATE/out/local-leakage.tsv" \
    && { echo "FAIL(C5): a scratch-path row appeared - this fixture must end on a path OUTSIDE the class or it stops testing the abort"; rm -rf "$LATE"; exit 1; }
grep -q '^# TOTAL: 1 ' "$LATE/out/local-leakage.tsv" \
    || { echo "FAIL(C5): expected a TOTAL of 1, not a CLEAR - a report that loses the row still has to stop claiming clear"; rm -rf "$LATE"; exit 1; }
rm -rf "$LATE"

# C6 - the lexicon is a local untracked file, so on a fresh machine it is absent. A run
#      without it must say the private-vocab class was NOT searched, or its CLEAR reads
#      as a lexicon-bounded all-clear that never consulted a lexicon.
grep -q '^# NO-LEXICON:' "$R" \
    && { echo "FAIL(C6): NO-LEXICON reported although the lexicon file exists"; exit 1; }
NOV=$(mktemp -d)
sh "$LL" "$FIX/pr.diff" "$NOV/out" "$NOV/absent-vocab.txt" >/dev/null 2>&1 \
    || { echo "FAIL(C6): gather-local-leakage failed without a lexicon file"; rm -rf "$NOV"; exit 1; }
grep -q '^# NO-LEXICON: .*absent-vocab\.txt not found' "$NOV/out/local-leakage.tsv" \
    || { echo "FAIL(C6): a missing lexicon file left no NO-LEXICON line - the vocab class looked searched"; rm -rf "$NOV"; exit 1; }
grep -q '^private-vocab	' "$NOV/out/local-leakage.tsv" \
    && { echo "FAIL(C6): private-vocab rows appeared without a lexicon file"; rm -rf "$NOV"; exit 1; }
rm -rf "$NOV"

echo "PASS: planted home path, recipe id, address, scratch files, personal ignore rule and lexicon term all found at the right lines; CI paths, bot/placeholder addresses, lockfile hashes, build-dir ignores, all-caps constants and every removed line stayed silent; a hit found before a non-scratch final path survived into the report"
