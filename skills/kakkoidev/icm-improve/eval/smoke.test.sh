#!/bin/sh
# smoke.test.sh -- start seeds a phase-1 candidate; next-phase clones it forward.
# Runs from the skill dir. Exit 0 = pass.
set -eu

SCRIPT="scripts/icm-improve.sh"
[ -f "$SCRIPT" ] || { echo "FAIL: $SCRIPT not found (run from the skill dir)"; exit 1; }

TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT

# Fake source skill under a fake skills dir.
mkdir -p "$TMP/skills/ns/demo/stages" "$TMP/skills/ns/demo/eval"
printf '# 01\n## Outputs\n- `output/x.md`\n' > "$TMP/skills/ns/demo/stages/01.md"
printf -- '---\nname: demo\ndescription: d\n---\n' > "$TMP/skills/ns/demo/SKILL.md"

sdir=$(ICM_SKILLS_DIR="$TMP/skills" ICM_IMPROVE_ROOT="$TMP/improve" sh "$SCRIPT" start ns/demo --phases 2 --session s1)
[ -d "$sdir/phase-1/candidate/stages" ] || { echo "FAIL: candidate stages not copied"; exit 1; }
[ -f "$sdir/phase-1/candidate/stages/01.md" ] || { echo "FAIL: stage file not copied"; exit 1; }
[ -f "$sdir/phase-1/candidate/SKILL.md" ] || { echo "FAIL: SKILL.md not copied"; exit 1; }
[ "$(cat "$sdir/phases")" = "2" ] || { echo "FAIL: phases not recorded"; exit 1; }

cand2=$(ICM_IMPROVE_ROOT="$TMP/improve" sh "$SCRIPT" next-phase "$sdir" 1)
[ -f "$cand2/stages/01.md" ] || { echo "FAIL: next-phase did not clone candidate"; exit 1; }

# start refuses to clobber an existing session
if ICM_SKILLS_DIR="$TMP/skills" ICM_IMPROVE_ROOT="$TMP/improve" sh "$SCRIPT" start ns/demo --session s1 >/dev/null 2>&1; then
    echo "FAIL: start clobbered an existing session"; exit 1
fi

# install-candidate stages a scratch skill; refuses non-__improve names; uninstall removes it
dest=$(ICM_SKILLS_DIR="$TMP/skills" sh "$SCRIPT" install-candidate "$sdir/phase-1/candidate" "ns/demo__improve")
[ -f "$dest/stages/01.md" ] || { echo "FAIL: install-candidate did not copy"; exit 1; }
if ICM_SKILLS_DIR="$TMP/skills" sh "$SCRIPT" install-candidate "$sdir/phase-1/candidate" "ns/demo" >/dev/null 2>&1; then
    echo "FAIL: install-candidate accepted a non-__improve name"; exit 1
fi
ICM_SKILLS_DIR="$TMP/skills" sh "$SCRIPT" uninstall-candidate "ns/demo__improve" >/dev/null
if [ -d "$dest" ]; then echo "FAIL: uninstall-candidate did not remove scratch skill"; exit 1; fi
if ICM_SKILLS_DIR="$TMP/skills" sh "$SCRIPT" uninstall-candidate "ns/demo" >/dev/null 2>&1; then
    echo "FAIL: uninstall-candidate removed a non-__improve skill"; exit 1
fi

echo "smoke.test.sh: all assertions passed"
