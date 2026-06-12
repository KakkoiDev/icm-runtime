#!/bin/sh
# Regression suite for ICM stage gates: gate freezing, .manifest tamper evidence,
# gate-check / gate-status. Self-contained: builds an installed-style skills tree
# and a project dir under a tmp dir, so SKILLS_DIR resolves from the script path
# exactly as in a real install. Run: sh tests/gate.test.sh
set -u

REPO_DIR=$(cd "$(dirname "$0")/.." && pwd -P)
TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT INT TERM

# Hermetic HOME: icm.sh telemetry writes to ~/.icm and installer touches
# ~/.claude / ~/.pi. Without this the suite mutates the developer's real HOME
# and can false-pass against leftover local state.
HOME="$TMP/home"
export HOME
mkdir -p "$HOME"

PASS=0
FAIL=0

t_ok()   { PASS=$((PASS + 1)); echo "PASS  $1"; }
t_fail() { FAIL=$((FAIL + 1)); echo "FAIL  $1${2:+ [$2]}"; }

# ---- fixture: skills tree mirroring ~/.agents/skills/ ----
mkdir -p "$TMP/skills/icm/runtime"
# cp preserves the exec bit: a non-executable script in the repo fails here
cp "$REPO_DIR/skills/icm/runtime/icm.sh" "$TMP/skills/icm/runtime/icm.sh"
cp "$REPO_DIR/skills/icm/runtime/gate-hook.sh" "$TMP/skills/icm/runtime/gate-hook.sh"
cp "$REPO_DIR/skills/icm/runtime/icm-gate.ts" "$TMP/skills/icm/runtime/icm-gate.ts"
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
out=$(HOME="$TMP/fakehome2" CLAUDECODE='' "$ICM" gate-status 2>&1); rc=$?
if [ "$rc" -eq 1 ] && printf '%s' "$out" | grep -q "NOT REGISTERED" \
    && printf '%s' "$out" | grep -q "RESULT: FAIL"; then
    t_ok "12 gate-status: gates + no hook -> exit 1 NOT REGISTERED"
else
    t_fail "12 gate-status: gates + no hook -> exit 1 NOT REGISTERED" "rc=$rc out=$out"
fi
mkdir -p "$PROJECT/.claude"
printf '{"hooks":{"PreToolUse":[{"matcher":"mcp__.*","hooks":[{"type":"command","command":"%s"}]}]}}\n' \
    "$TMP/skills/icm/runtime/gate-hook.sh" > "$PROJECT/.claude/settings.local.json"
out=$(HOME="$TMP/fakehome2" CLAUDECODE='' "$ICM" gate-status 2>&1); rc=$?
if [ "$rc" -eq 0 ] && printf '%s' "$out" | grep -q "REGISTERED      .claude/settings.local.json"; then
    t_ok "12b gate-status: project-local registration -> exit 0"
else
    t_fail "12b gate-status: project-local registration -> exit 0" "rc=$rc out=$out"
fi
rm -rf "$PROJECT/.claude"

# ---- case 12c: pi-only registration satisfies the any-scope rule ----
mkdir -p "$TMP/fakehome3/.pi/agent/extensions"
cp "$TMP/skills/icm/runtime/icm-gate.ts" "$TMP/fakehome3/.pi/agent/extensions/icm-gate.ts"
out=$(HOME="$TMP/fakehome3" CLAUDECODE='' "$ICM" gate-status 2>&1); rc=$?
if [ "$rc" -eq 0 ] && printf '%s' "$out" | grep -q "REGISTERED      $TMP/fakehome3/.pi/agent/extensions/icm-gate.ts"; then
    t_ok "12c gate-status: pi extension registered -> exit 0 outside Claude Code"
else
    t_fail "12c gate-status: pi extension registered -> exit 0 outside Claude Code" "rc=$rc out=$out"
fi

# ---- case 12d: pi-only registration fails inside Claude Code (harness-aware) ----
out=$(HOME="$TMP/fakehome3" CLAUDECODE=1 "$ICM" gate-status 2>&1); rc=$?
if [ "$rc" -eq 1 ] && printf '%s' "$out" | grep -q "not registered in any Claude scope"; then
    t_ok "12d gate-status: pi-only registration under CLAUDECODE -> exit 1"
else
    t_fail "12d gate-status: pi-only registration under CLAUDECODE -> exit 1" "rc=$rc out=$out"
fi

# ---- case 11: installer.sh --hooks is idempotent and preserves existing keys ----
if command -v jq >/dev/null 2>&1; then
    FAKEHOME="$TMP/fakehome"
    mkdir -p "$FAKEHOME/.agents/skills" "$FAKEHOME/.claude"
    ln -s "$TMP/skills/icm" "$FAKEHOME/.agents/skills/icm"
    printf '{"model":"x"}\n' > "$FAKEHOME/.claude/settings.json"
    out=$(HOME="$FAKEHOME" "$REPO_DIR/installer.sh" --hooks 2>&1); rc=$?
    out2=$(HOME="$FAKEHOME" "$REPO_DIR/installer.sh" --hooks 2>&1); rc2=$?
    settings="$FAKEHOME/.claude/settings.json"
    count=$(grep -c 'gate-hook.sh' "$settings")
    model=$(jq -r '.model' "$settings")
    matcher=$(jq -r '.hooks.PreToolUse[0].matcher' "$settings")
    if [ "$rc" -eq 0 ] && [ "$rc2" -eq 0 ] && [ "$count" -eq 1 ] \
        && [ "$model" = "x" ] && [ "$matcher" = "mcp__.*" ]; then
        t_ok "11 installer --hooks: idempotent, preserves keys"
    else
        t_fail "11 installer --hooks: idempotent, preserves keys" "rc=$rc rc2=$rc2 count=$count model=$model matcher=$matcher out=$out out2=$out2"
    fi
else
    echo "SKIP  11 installer --hooks (jq not installed)"
fi

# ---- case 13: pi extension adapter end-to-end (needs node >= 23.6 for .ts) ----
if command -v node >/dev/null 2>&1; then
    EXT="$TMP/skills/icm/runtime/icm-gate.ts"
    DRIVER="$REPO_DIR/tests/pi-driver.ts"
    sleep 1 # avoid same-second run-dir collision with earlier inits
    run_d=$("$ICM" init testns/gated-ws 2>/dev/null)
    out=$(cd "$PROJECT" && node "$DRIVER" "$EXT" mcp__test__send 2>/dev/null); rc=$?
    if [ "$rc" -eq 0 ] && printf '%s' "$out" | grep -q '"block":true' \
        && printf '%s' "$out" | grep -q '02-send'; then
        t_ok "13a pi adapter: failing gate -> block with reason"
    else
        t_fail "13a pi adapter: failing gate -> block with reason" "rc=$rc out=$out"
    fi
    printf 'RESULT: PASS\n' > "$run_d/02-send/output/evidence.md"
    out=$(cd "$PROJECT" && node "$DRIVER" "$EXT" mcp__test__send 2>/dev/null); rc=$?
    if [ "$rc" -eq 0 ] && [ "$out" = "null" ]; then
        t_ok "13b pi adapter: passing gate -> allow"
    else
        t_fail "13b pi adapter: passing gate -> allow" "rc=$rc out=$out"
    fi
    out=$(cd "$TMP" && node "$DRIVER" "$EXT" mcp__test__send 2>/dev/null); rc=$?
    if [ "$rc" -eq 0 ] && [ "$out" = "null" ]; then
        t_ok "13c pi adapter: no .icm in cwd -> allow"
    else
        t_fail "13c pi adapter: no .icm in cwd -> allow" "rc=$rc out=$out"
    fi
else
    echo "SKIP  13 pi adapter (node not installed)"
fi

# ---- case 14: installer --hooks registers the pi extension when ~/.pi exists ----
if command -v jq >/dev/null 2>&1; then
    mkdir -p "$TMP/fakehome/.pi"
    out=$(HOME="$TMP/fakehome" "$REPO_DIR/installer.sh" --hooks 2>&1); rc=$?
    out2=$(HOME="$TMP/fakehome" "$REPO_DIR/installer.sh" --hooks 2>&1); rc2=$?
    link="$TMP/fakehome/.pi/agent/extensions/icm-gate.ts"
    if [ "$rc" -eq 0 ] && [ "$rc2" -eq 0 ] && [ -L "$link" ] \
        && [ "$(readlink "$link")" = "$TMP/fakehome/.agents/skills/icm/runtime/icm-gate.ts" ]; then
        t_ok "14 installer --hooks: pi extension symlink, idempotent"
    else
        t_fail "14 installer --hooks: pi extension symlink, idempotent" "rc=$rc rc2=$rc2 out=$out out2=$out2"
    fi
else
    echo "SKIP  14 installer pi extension (jq not installed)"
fi

# ---- case 15: tool-calls.jsonl is created and populated ----
LOG_FILE="$PROJECT/.icm/telemetry/tool-calls.jsonl"
if [ -f "$LOG_FILE" ]; then
    count=$(wc -l < "$LOG_FILE" | tr -d ' ')
    if [ "$count" -ge 1 ]; then
        t_ok "15 tool-calls.jsonl exists and has entries ($count lines)"
    else
        t_fail "15 tool-calls.jsonl exists and has entries" "lines=$count"
    fi
else
    t_fail "15 tool-calls.jsonl exists" "file not found at $LOG_FILE"
fi

# ---- case 15b: log is real JSONL -- one valid JSON object per line ----
# Regression: jq without -c pretty-printed the args array across lines.
bad_lines=$(grep -cv '^{.*}$' "$LOG_FILE" 2>/dev/null | tr -d ' ')
if command -v jq >/dev/null 2>&1; then
    jq -e . "$LOG_FILE" >/dev/null 2>&1; jq_rc=$?
else
    jq_rc=0
fi
if [ "${bad_lines:-1}" -eq 0 ] && [ "$jq_rc" -eq 0 ]; then
    t_ok "15b tool-calls.jsonl: one valid JSON object per line"
else
    t_fail "15b tool-calls.jsonl: one valid JSON object per line" "bad_lines=$bad_lines jq_rc=$jq_rc"
fi

# ---- case 16: tools/ directory frozen into run ----
WS3_DIR="$TMP/skills/testns/tool-ws"
mkdir -p "$WS3_DIR/stages" "$WS3_DIR/tools"
cat > "$WS3_DIR/stages/01-work.md" <<'EOF'
# Stage 01
Call `tools/do-work.sh` to process.
EOF
cat > "$WS3_DIR/tools/do-work.sh" <<'EOF'
#!/bin/sh
echo "work done"
EOF
chmod +x "$WS3_DIR/tools/do-work.sh"

run_e=$("$ICM" init testns/tool-ws 2>/dev/null)
if [ -d "$run_e/tools" ] && [ -f "$run_e/tools/do-work.sh" ]; then
    t_ok "16 tools/ dir frozen into run by init"
else
    t_fail "16 tools/ dir frozen into run by init" "run=$run_e"
fi

# ---- case 16b: tools/ in manifest ----
if grep -q 'tools/do-work.sh' "$run_e/.manifest"; then
    t_ok "16b tools/ files listed in .manifest"
else
    t_fail "16b tools/ files listed in .manifest" "manifest=$(cat "$run_e/.manifest")"
fi

# ---- case 16c: tampered tool -> DENY ----
printf 'x' >> "$run_e/tools/do-work.sh"
out=$("$ICM" gate-check --tool mcp__test__send 2>&1); rc=$?
if [ "$rc" -eq 1 ] && printf '%s' "$out" | grep -q "tampered"; then
    t_ok "16c tampered tool: DENY"
else
    t_fail "16c tampered tool: DENY" "rc=$rc out=$out"
fi

# ---- case 17: telemetry/run.json created ----
if [ -f "$run_e/telemetry/run.json" ]; then
    if grep -q '"workspace"' "$run_e/telemetry/run.json" && grep -q '"stages"' "$run_e/telemetry/run.json"; then
        t_ok "17 telemetry/run.json created with metadata"
    else
        t_fail "17 telemetry/run.json created with metadata" "missing workspace or stages key"
    fi
else
    t_fail "17 telemetry/run.json created" "file not found"
fi

# ---- case 18: icm.sh telemetry writes to global file ----
later_run=$("$ICM" init testns/tool-ws 2>/dev/null)
printf 'done\n' > "$later_run/01-work/output/done.md"
"$ICM" stage-done testns/tool-ws --stage 01-work --model claude-test \
    --tokens-in 500 --tokens-out 200 2>/dev/null || true
GLOBAL_TELEM="$HOME/.icm/telemetry/skill-runs.jsonl"
OUT=$(cd "$PROJECT" && "$ICM" telemetry testns/tool-ws \
    --model claude-test --tokens-in 500 --tokens-out 200 --cost 0.001 2>&1) || true
if [ -f "$GLOBAL_TELEM" ] && grep -q 'tool-ws' "$GLOBAL_TELEM"; then
    t_ok "18 icm.sh telemetry: writes to ~/.icm/telemetry/skill-runs.jsonl"
else
    t_fail "18 icm.sh telemetry: writes to ~/.icm/telemetry/skill-runs.jsonl" "out=$OUT"
fi

# ---- case 18b: stage-done writes to stages.jsonl ----
"$ICM" stage-done testns/tool-ws --stage 01-work --model claude-test \
    --tokens-in 500 --tokens-out 200 2>/dev/null
_latest_run=$(cd .icm/testns/tool-ws && ls -1 2>/dev/null | sort -r | head -1)
stages_jsonl=".icm/testns/tool-ws/$_latest_run/telemetry/stages.jsonl"
if [ -f "$stages_jsonl" ] && grep -q '"stage":"01-work"' "$stages_jsonl"; then
    t_ok "18b stage-done: writes to telemetry/stages.jsonl"
else
    t_fail "18b stage-done: writes to telemetry/stages.jsonl" "file=$stages_jsonl"
fi

# ---- case 18c: stage-done creates .stage-telemetry marker ----
if [ -f ".icm/testns/tool-ws/$_latest_run/01-work/.stage-telemetry" ]; then
    t_ok "18c stage-done: creates .stage-telemetry marker"
else
    t_fail "18c stage-done: creates .stage-telemetry marker"
fi

# ---- case 18d: audit flags missing stage telemetry ----
sleep 1
run_f=$("$ICM" init testns/tool-ws 2>/dev/null)
if [ "$run_f" = "$run_e" ]; then
    t_fail "18d-pre distinct run dir" "collided: $run_f"
fi
printf 'done\n' > "$run_f/01-work/output/done.md"
# Intentionally do NOT call stage-done for run_f/01-work
audit_out=$("$ICM" audit testns/tool-ws 2>&1); rc=$?
if [ "$rc" -eq 0 ] && printf '%s' "$audit_out" | grep -q "MISSING stage-done"; then
    t_ok "18d audit: flags stage without stage-done telemetry"
else
    t_fail "18d audit: flags stage without stage-done telemetry" "rc=$rc out=$audit_out"
fi

# ---- case 19: audit on a completed run (with telemetry) ----
# Complete the first run properly with stage-done
"$ICM" stage-done testns/tool-ws --stage 01-work --model claude-test \
    --tokens-in 500 --tokens-out 200 2>/dev/null
audit_out=$("$ICM" audit testns/tool-ws 2>&1); rc=$?
if [ "$rc" -eq 0 ] && printf '%s' "$audit_out" | grep -q "AUDIT:"; then
    t_ok "19 audit: produces report for completed run"
else
    t_fail "19 audit: produces report for completed run" "rc=$rc out=$audit_out"
fi

# ---- case 19b: audit detects expected tools from contract ----
if printf '%s' "$audit_out" | grep -q "tools/do-work.sh"; then
    t_ok "19b audit: detects expected tools from stage contract"
else
    t_fail "19b audit: detects expected tools from stage contract" "out=$audit_out"
fi

# ---- case 19c: audit reports per-stage token usage ----
if printf '%s' "$audit_out" | grep -q "Per-stage token usage" \
    && printf '%s' "$audit_out" | grep -q "01-work: in=500 out=200"; then
    t_ok "19c audit: reports per-stage token usage from stages.jsonl"
else
    t_fail "19c audit: reports per-stage token usage from stages.jsonl" "out=$audit_out"
fi

# ---- case 19d: audit handles null token counts without crashing ----
# Find the latest run dir and append a null-entry directly
_latest_run=$(cd .icm/testns/tool-ws && ls -1 2>/dev/null | sort -r | head -1)
if [ -n "$_latest_run" ]; then
    _run_dir=".icm/testns/tool-ws/$_latest_run"
    printf '{"ts":"2026-06-12T09:00:00Z","stage":"02-more","model":"claude-test","tokens_in":null,"tokens_out":null,"counts":"estimated"}\n' \
        >> "$_run_dir/telemetry/stages.jsonl"
    mkdir -p "$_run_dir/02-more/output"
    printf 'done\n' > "$_run_dir/02-more/output/done.md"
    touch "$_run_dir/02-more/.stage-telemetry"
fi
audit_out=$("$ICM" audit testns/tool-ws 2>&1); rc=$?
if [ "$rc" -eq 0 ] && printf '%s' "$audit_out" | grep -q "in=null out=null"; then
    t_ok "19d audit: handles null token counts without crashing"
else
    t_fail "19d audit: handles null token counts without crashing" "rc=$rc out=$audit_out"
fi

# ---- case 20: audit on non-existent workspace ----
audit_out=$("$ICM" audit no-such-workspace 2>&1); rc=$?
if [ "$rc" -eq 1 ]; then
    t_ok "20 audit: exit 1 for non-existent workspace"
else
    t_fail "20 audit: exit 1 for non-existent workspace" "rc=$rc"
fi

# ---- case 21: ICM-TOOLS declaration drives expected-vs-actual matching ----
WS4_DIR="$TMP/skills/testns/icmtools-ws"
mkdir -p "$WS4_DIR/stages"
cat > "$WS4_DIR/stages/01-pub.md" <<'EOF'
# Stage 01
<!-- ICM-TOOLS expect="mcp__test__send mcp__never__called" -->
Do it.
EOF
run_g=$("$ICM" init testns/icmtools-ws 2>/dev/null)
printf 'done\n' > "$run_g/01-pub/output/done.md"
"$ICM" stage-done testns/icmtools-ws --stage 01-pub --model m >/dev/null 2>&1
"$ICM" gate-check --tool mcp__test__send >/dev/null 2>&1 || true
audit_out=$("$ICM" audit testns/icmtools-ws 2>&1); rc=$?
if [ "$rc" -eq 0 ] \
    && printf '%s' "$audit_out" | grep -q "✓ mcp__test__send" \
    && printf '%s' "$audit_out" | grep -q "✗ mcp__never__called"; then
    t_ok "21 audit: ICM-TOOLS matched against gate-check telemetry"
else
    t_fail "21 audit: ICM-TOOLS matched against gate-check telemetry" "rc=$rc out=$audit_out"
fi
if printf '%s' "$audit_out" | grep -q "Deviations: 1"; then
    t_ok "21b audit: missing expected tool counted as deviation"
else
    t_fail "21b audit: missing expected tool counted as deviation" "out=$audit_out"
fi

# ---- case 22: reify-telemetry fills per-stage counts from --transcript ----
if command -v jq >/dev/null 2>&1; then
    sleep 1
    run_h=$("$ICM" init testns/tool-ws 2>/dev/null)
    printf 'done\n' > "$run_h/01-work/output/done.md"
    "$ICM" stage-done testns/tool-ws --stage 01-work --model m >/dev/null 2>&1
    cat > "$TMP/transcript.jsonl" <<'EOF'
{"ts":"2020-01-01T00:00:00Z","usage":{"input_tokens":100,"output_tokens":50}}
{"ts":"2020-01-01T00:00:01Z","usage":{"input_tokens":200,"output_tokens":70}}
EOF
    out=$("$ICM" reify-telemetry testns/tool-ws --transcript "$TMP/transcript.jsonl" 2>&1); rc=$?
    sj="$run_h/telemetry/stages.jsonl"
    if [ "$rc" -eq 0 ] && grep -q '"counts":"transcript"' "$sj" \
        && grep -q '"tokens_in":300' "$sj" && grep -q '"tokens_out":120' "$sj"; then
        t_ok "22 reify-telemetry: per-stage counts summed from transcript"
    else
        t_fail "22 reify-telemetry: per-stage counts summed from transcript" "rc=$rc out=$out sj=$(cat "$sj" 2>/dev/null)"
    fi
else
    echo "SKIP  22 reify-telemetry transcript (jq not installed)"
fi

# ---- case 23: reify-telemetry auto-detect picks newest transcript, warns ----
if command -v jq >/dev/null 2>&1; then
    sleep 1
    run_i=$("$ICM" init testns/tool-ws 2>/dev/null)
    printf 'done\n' > "$run_i/01-work/output/done.md"
    "$ICM" stage-done testns/tool-ws --stage 01-work --model m >/dev/null 2>&1
    proj_dir="$HOME/.claude/projects/some-session"
    mkdir -p "$proj_dir"
    printf '{"ts":"2020-01-01T00:00:00Z","usage":{"input_tokens":1,"output_tokens":1}}\n' > "$proj_dir/old.jsonl"
    sleep 1
    printf '{"ts":"2020-01-01T00:00:00Z","usage":{"input_tokens":7,"output_tokens":3}}\n' > "$proj_dir/new.jsonl"
    out=$(CLAUDECODE=1 "$ICM" reify-telemetry testns/tool-ws 2>&1); rc=$?
    sj="$run_i/telemetry/stages.jsonl"
    if [ "$rc" -eq 0 ] && printf '%s' "$out" | grep -q "picked newest" \
        && printf '%s' "$out" | grep -q "new.jsonl" \
        && grep -q '"tokens_in":7' "$sj"; then
        t_ok "23 reify-telemetry: auto-detect picks newest by mtime + warns"
    else
        t_fail "23 reify-telemetry: auto-detect picks newest by mtime + warns" "rc=$rc out=$out sj=$(cat "$sj" 2>/dev/null)"
    fi
    rm -rf "$HOME/.claude/projects"
else
    echo "SKIP  23 reify-telemetry auto-detect (jq not installed)"
fi

echo ""
echo "$PASS passed, $FAIL failed"
[ "$FAIL" -eq 0 ]
