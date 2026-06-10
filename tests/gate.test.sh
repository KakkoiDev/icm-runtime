#!/bin/sh
# Regression suite for ICM stage gates: gate freezing, .manifest tamper evidence,
# gate-check / gate-status. Self-contained: builds an installed-style skills tree
# and a project dir under a tmp dir, so SKILLS_DIR resolves from the script path
# exactly as in a real install. Run: sh tests/gate.test.sh
set -u

REPO_DIR=$(cd "$(dirname "$0")/.." && pwd -P)
TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT INT TERM

PASS=0
FAIL=0

t_ok()   { PASS=$((PASS + 1)); echo "PASS  $1"; }
t_fail() { FAIL=$((FAIL + 1)); echo "FAIL  $1${2:+ [$2]}"; }

# ---- fixture: skills tree mirroring ~/.agents/skills/ ----
mkdir -p "$TMP/skills/icm/runtime"
# cp preserves the exec bit: a non-executable script in the repo fails here
cp "$REPO_DIR/skills/icm/runtime/icm.sh" "$TMP/skills/icm/runtime/icm.sh"
cp "$REPO_DIR/skills/icm/runtime/gate-hook.sh" "$TMP/skills/icm/runtime/gate-hook.sh"
ICM="$TMP/skills/icm/runtime/icm.sh"
HOOK="$TMP/skills/icm/runtime/gate-hook.sh"

# $1=tool $2=cwd -> PreToolUse stdin JSON as the harness sends it
hook_json() {
    printf '{"session_id":"t","transcript_path":"/tmp/t.jsonl","cwd":"%s","permission_mode":"default","hook_event_name":"PreToolUse","tool_name":"%s","tool_input":{}}' "$2" "$1"
}

WS_DIR="$TMP/skills/testns/gated-ws"
mkdir -p "$WS_DIR/stages"
cat > "$WS_DIR/stages/01-work.md" <<'EOF'
# Stage 01 - work
Do the work.
EOF
cat > "$WS_DIR/stages/02-send.md" <<'EOF'
# Stage 02 - send
<!-- ICM-GATE tools="mcp__test__send(_draft)?" run="grep -Eq '^RESULT: PASS$' output/evidence.md" -->
Send the thing.
EOF

WS2_DIR="$TMP/skills/testns/script-ws"
mkdir -p "$WS2_DIR/stages" "$WS2_DIR/checks"
cat > "$WS2_DIR/stages/01-publish.md" <<'EOF'
# Stage 01 - publish
<!-- ICM-GATE tools="mcp__test__publish" run="checks/check.sh" -->
EOF
cat > "$WS2_DIR/checks/check.sh" <<'EOF'
#!/bin/sh
grep -Eq '^OK$' output/evidence.md
EOF
chmod +x "$WS2_DIR/checks/check.sh"

PROJECT="$TMP/project"
mkdir -p "$PROJECT"
cd "$PROJECT" || exit 1

# ---- case 1: no .icm in cwd -> exit 0, silent ----
out=$("$ICM" gate-check --tool mcp__test__send 2>&1); rc=$?
if [ "$rc" -eq 0 ] && [ -z "$out" ]; then
    t_ok "1 no .icm: exit 0 silent"
else
    t_fail "1 no .icm: exit 0 silent" "rc=$rc out=$out"
fi

# ---- case 2: active run, no evidence -> exit 1, DENY names ws/ts/stage ----
run_dir=$("$ICM" init testns/gated-ws 2>/dev/null)
ts=$(basename "$run_dir")
out=$("$ICM" gate-check --tool mcp__test__send 2>&1); rc=$?
if [ "$rc" -eq 1 ] \
    && printf '%s' "$out" | grep -q "DENY testns/gated-ws $ts 02-send" \
    && printf '%s' "$out" | grep -q "checker failed"; then
    t_ok "2 failing checker: exit 1, DENY names ws/ts/stage"
else
    t_fail "2 failing checker: exit 1, DENY names ws/ts/stage" "rc=$rc out=$out"
fi
out=$("$ICM" gate-check --tool mcp__test__send_draft 2>&1); rc=$?
if [ "$rc" -eq 1 ]; then
    t_ok "2b regex variant (_draft)? also gated"
else
    t_fail "2b regex variant (_draft)? also gated" "rc=$rc out=$out"
fi

# ---- case 4: non-matching tool -> exit 0 despite failing checker ----
out=$("$ICM" gate-check --tool mcp__other__thing 2>&1); rc=$?
if [ "$rc" -eq 0 ] && [ -z "$out" ]; then
    t_ok "4 non-matching tool: exit 0 silent"
else
    t_fail "4 non-matching tool: exit 0 silent" "rc=$rc out=$out"
fi

# ---- case 8a: hook e2e in failing state -> deny JSON, exit 0 ----
out=$(hook_json mcp__test__send "$PROJECT" | (cd "$TMP" && "$HOOK")); rc=$?
if [ "$rc" -eq 0 ] \
    && printf '%s' "$out" | grep -q '"permissionDecision"' \
    && printf '%s' "$out" | grep -q '"deny"' \
    && printf '%s' "$out" | grep -q '02-send'; then
    t_ok "8a hook: failing gate -> deny JSON with reason"
else
    t_fail "8a hook: failing gate -> deny JSON with reason" "rc=$rc out=$out"
fi

# ---- case 8c: hook with cwd lacking .icm -> silent allow ----
out=$(hook_json mcp__test__send "$TMP" | "$HOOK"); rc=$?
if [ "$rc" -eq 0 ] && [ -z "$out" ]; then
    t_ok "8c hook: no .icm in cwd -> silent exit 0"
else
    t_fail "8c hook: no .icm in cwd -> silent exit 0" "rc=$rc out=$out"
fi

# ---- case 8d: hook with missing fields -> deny JSON (fail closed) ----
out=$(printf '{}' | "$HOOK"); rc=$?
if [ "$rc" -eq 0 ] && printf '%s' "$out" | grep -q '"deny"'; then
    t_ok "8d hook: missing stdin fields -> deny (fail closed)"
else
    t_fail "8d hook: missing stdin fields -> deny (fail closed)" "rc=$rc out=$out"
fi

# ---- case 3: evidence present -> exit 0 ----
printf 'RESULT: PASS\n' > "$run_dir/02-send/output/evidence.md"
out=$("$ICM" gate-check --tool mcp__test__send 2>&1); rc=$?
if [ "$rc" -eq 0 ] && [ -z "$out" ]; then
    t_ok "3 evidence present: exit 0"
else
    t_fail "3 evidence present: exit 0" "rc=$rc out=$out"
fi

# ---- case 8b: hook e2e in passing state -> silent allow ----
out=$(hook_json mcp__test__send "$PROJECT" | (cd "$TMP" && "$HOOK")); rc=$?
if [ "$rc" -eq 0 ] && [ -z "$out" ]; then
    t_ok "8b hook: passing gate -> silent exit 0"
else
    t_fail "8b hook: passing gate -> silent exit 0" "rc=$rc out=$out"
fi

# ---- case 7: fully complete run -> exit 0 (no stale blocking) ----
printf 'done\n' > "$run_dir/01-work/output/done.md"
next=$("$ICM" next testns/gated-ws 2>/dev/null)
out=$("$ICM" gate-check --tool mcp__test__send 2>&1); rc=$?
if [ "$rc" -eq 0 ] && [ "$next" = "done" ]; then
    t_ok "7 complete run: exit 0"
else
    t_fail "7 complete run: exit 0" "rc=$rc next=$next out=$out"
fi

# ---- case 5: tampered frozen contract (append) -> DENY tamper, any tool ----
cp "$run_dir/02-send/CONTEXT.md" "$TMP/pristine-CONTEXT.md"
printf 'x' >> "$run_dir/02-send/CONTEXT.md"
out=$("$ICM" gate-check --tool mcp__test__send 2>&1); rc=$?
out2=$("$ICM" gate-check --tool mcp__other__thing 2>&1); rc2=$?
if [ "$rc" -eq 1 ] && printf '%s' "$out" | grep -q "tampered" \
    && [ "$rc2" -eq 1 ] && printf '%s' "$out2" | grep -q "tampered"; then
    t_ok "5 tamper (append): DENY for matching and non-matching tools"
else
    t_fail "5 tamper (append): DENY for matching and non-matching tools" "rc=$rc rc2=$rc2 out=$out"
fi
cp "$TMP/pristine-CONTEXT.md" "$run_dir/02-send/CONTEXT.md"

# ---- case 6: gate line DELETED from frozen contract -> still DENY tamper ----
grep -v 'ICM-GATE' "$TMP/pristine-CONTEXT.md" > "$run_dir/02-send/CONTEXT.md"
out=$("$ICM" gate-check --tool mcp__test__send 2>&1); rc=$?
if [ "$rc" -eq 1 ] && printf '%s' "$out" | grep -q "tampered"; then
    t_ok "6 gate line deleted: still DENY (manifest)"
else
    t_fail "6 gate line deleted: still DENY (manifest)" "rc=$rc out=$out"
fi
cp "$TMP/pristine-CONTEXT.md" "$run_dir/02-send/CONTEXT.md"

# sanity after restores: passes again
out=$("$ICM" gate-check --tool mcp__test__send 2>&1); rc=$?
if [ "$rc" -eq 0 ]; then
    t_ok "6b restored contract: passes again"
else
    t_fail "6b restored contract: passes again" "rc=$rc out=$out"
fi

# ---- case 9: live skill edited after init -> frozen contract still enforces ----
sleep 1 # run timestamps have 1s resolution; a same-second init would reuse run A's dir
run_b=$("$ICM" init testns/gated-ws 2>/dev/null)
if [ "$run_b" = "$run_dir" ]; then
    t_fail "9-pre distinct run dir for second init" "collided: $run_b"
fi
cp "$WS_DIR/stages/02-send.md" "$TMP/pristine-stage.md"
grep -v 'ICM-GATE' "$TMP/pristine-stage.md" > "$WS_DIR/stages/02-send.md"
out=$("$ICM" gate-check --tool mcp__test__send 2>&1); rc=$?
if [ "$rc" -eq 1 ] && printf '%s' "$out" | grep -q "DENY testns/gated-ws $(basename "$run_b") 02-send"; then
    t_ok "9 live skill edit cannot weaken frozen gate"
else
    t_fail "9 live skill edit cannot weaken frozen gate" "rc=$rc out=$out"
fi
cp "$TMP/pristine-stage.md" "$WS_DIR/stages/02-send.md"
# complete run B so it stops blocking later cases
printf 'RESULT: PASS\n' > "$run_b/02-send/output/evidence.md"
printf 'done\n' > "$run_b/01-work/output/done.md"

# ---- case 10: checks/-script gate, freezing, and run-dir glob hygiene ----
run_c=$("$ICM" init testns/script-ws 2>/dev/null)
out=$("$ICM" gate-check --tool mcp__test__publish 2>&1); rc=$?
fail_first=$rc
printf 'OK\n' > "$run_c/01-publish/output/evidence.md"
out2=$("$ICM" gate-check --tool mcp__test__publish 2>&1); rc2=$?
if [ "$fail_first" -eq 1 ] && [ "$rc2" -eq 0 ] && [ -f "$run_c/checks/check.sh" ]; then
    t_ok "10 checks/ script: frozen into run, denies then passes"
else
    t_fail "10 checks/ script: frozen into run, denies then passes" "rc=$fail_first rc2=$rc2 out=$out out2=$out2"
fi
printf 'x' >> "$run_c/checks/check.sh"
out=$("$ICM" gate-check --tool mcp__test__publish 2>&1); rc=$?
if [ "$rc" -eq 1 ] && printf '%s' "$out" | grep -q "tampered"; then
    t_ok "10b tampered frozen checker: DENY"
else
    t_fail "10b tampered frozen checker: DENY" "rc=$rc out=$out"
fi
list_out=$("$ICM" list testns/script-ws 2>/dev/null)
if printf '%s' "$list_out" | grep -q "checks"; then
    t_fail "10c list ignores checks/ and .manifest" "list=$list_out"
else
    t_ok "10c list ignores checks/ and .manifest"
fi
# un-tamper so later cases see a clean tree
cp "$WS2_DIR/checks/check.sh" "$run_c/checks/check.sh"

# ---- case 12: gate-status registration reporting ----
mkdir -p "$TMP/fakehome2"
out=$(HOME="$TMP/fakehome2" "$ICM" gate-status 2>&1); rc=$?
if [ "$rc" -eq 1 ] && printf '%s' "$out" | grep -q "NOT REGISTERED" \
    && printf '%s' "$out" | grep -q "RESULT: FAIL"; then
    t_ok "12 gate-status: gates + no hook -> exit 1 NOT REGISTERED"
else
    t_fail "12 gate-status: gates + no hook -> exit 1 NOT REGISTERED" "rc=$rc out=$out"
fi
mkdir -p "$PROJECT/.claude"
printf '{"hooks":{"PreToolUse":[{"matcher":"mcp__.*","hooks":[{"type":"command","command":"%s"}]}]}}\n' \
    "$TMP/skills/icm/runtime/gate-hook.sh" > "$PROJECT/.claude/settings.local.json"
out=$(HOME="$TMP/fakehome2" "$ICM" gate-status 2>&1); rc=$?
if [ "$rc" -eq 0 ] && printf '%s' "$out" | grep -q "REGISTERED      .claude/settings.local.json"; then
    t_ok "12b gate-status: project-local registration -> exit 0"
else
    t_fail "12b gate-status: project-local registration -> exit 0" "rc=$rc out=$out"
fi
rm -rf "$PROJECT/.claude"

echo ""
echo "$PASS passed, $FAIL failed"
[ "$FAIL" -eq 0 ]
