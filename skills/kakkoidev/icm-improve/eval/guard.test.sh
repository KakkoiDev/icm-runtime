#!/bin/sh
# guard.test.sh -- invariant 1: the improver may change stage prose only.
# Runs from the skill dir (icm.sh eval does `cd <skill> && sh <test>`). Exit 0 = pass.
set -eu

SCRIPT="scripts/icm-improve.sh"
[ -f "$SCRIPT" ] || { echo "FAIL: $SCRIPT not found (run from the skill dir)"; exit 1; }

TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT

mkA() {
    mkdir -p "$1/stages" "$1/checks" "$1/tools"
    cat > "$1/stages/01-make.md" <<'MD'
# 01-make

## Process
1. Do the thing. This is editable prose.

## Outputs
- `output/result.md` (the produced artifact)

<!-- ICM-TOOLS expect="(Read|Write)" -->
<!-- ICM-GATE tools="Write" run="checks/ready.sh" -->
MD
    printf '#!/bin/sh\ntest -s output/result.md\n' > "$1/checks/ready.sh"
    printf '#!/bin/sh\necho work\n' > "$1/tools/run.sh"
    printf -- '---\nname: t\ndescription: t\n---\n' > "$1/SKILL.md"
    mkdir -p "$1/eval-heldout"
    printf '#!/bin/sh\ntest -s "$ICM_RUN_DIR"/01-make/output/result.md\n' > "$1/eval-heldout/contract.test.sh"
}

guard() { sh "$SCRIPT" guard "$1" "$2" >/dev/null 2>&1; }

A="$TMP/a"; mkA "$A"

# 1: prose-only edit (in ## Process) -> ALLOWED
B="$TMP/b1"; cp -R "$A" "$B"
sed 's/Do the thing./Do the thing differently./' "$A/stages/01-make.md" > "$B/stages/01-make.md"
if guard "$A" "$B"; then echo "ok 1 prose-only edit allowed"; else echo "FAIL 1: prose-only edit rejected"; exit 1; fi

# 2: editing the ## Outputs rubric -> FORBIDDEN
B="$TMP/b2"; cp -R "$A" "$B"
sed 's#`output/result.md`#`output/CHANGED.md`#' "$A/stages/01-make.md" > "$B/stages/01-make.md"
if guard "$A" "$B"; then echo "FAIL 2: ## Outputs edit allowed"; exit 1; else echo "ok 2 Outputs edit forbidden"; fi

# 3: editing an ICM-TOOLS declaration -> FORBIDDEN
B="$TMP/b3"; cp -R "$A" "$B"
sed 's/expect="(Read|Write)"/expect="(Read)"/' "$A/stages/01-make.md" > "$B/stages/01-make.md"
if guard "$A" "$B"; then echo "FAIL 3: ICM-TOOLS edit allowed"; exit 1; else echo "ok 3 ICM-TOOLS edit forbidden"; fi

# 4: editing a checks/ script -> FORBIDDEN (outside stages/)
B="$TMP/b4"; cp -R "$A" "$B"
printf '#!/bin/sh\nexit 0\n' > "$B/checks/ready.sh"
if guard "$A" "$B"; then echo "FAIL 4: checks/ edit allowed"; exit 1; else echo "ok 4 checks edit forbidden"; fi

# 5: adding a stage file -> FORBIDDEN (stage set changed)
B="$TMP/b5"; cp -R "$A" "$B"
printf '# 02-x\nprose\n' > "$B/stages/02-x.md"
if guard "$A" "$B"; then echo "FAIL 5: stage add allowed"; exit 1; else echo "ok 5 stage add forbidden"; fi

# 6: editing SKILL.md -> FORBIDDEN (outside stages/)
B="$TMP/b6"; cp -R "$A" "$B"
printf -- '---\nname: t\ndescription: CHANGED\n---\n' > "$B/SKILL.md"
if guard "$A" "$B"; then echo "FAIL 6: SKILL.md edit allowed"; exit 1; else echo "ok 6 SKILL.md edit forbidden"; fi

# 7: editing an eval-heldout/ contract test -> FORBIDDEN (outside stages/; the
# held-out check must not be weakenable by a prose-only improver edit)
B="$TMP/b7"; cp -R "$A" "$B"
printf '#!/bin/sh\nexit 0\n' > "$B/eval-heldout/contract.test.sh"
if guard "$A" "$B"; then echo "FAIL 7: eval-heldout edit allowed"; exit 1; else echo "ok 7 eval-heldout edit forbidden"; fi

echo "guard.test.sh: all assertions passed"
