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

# ---- case 0: every shell script parses under the system bash ----
# A parse error in icm.sh behind the ".*" gate-hook denies every tool call, so a
# bad commit must fail CI here, not in a user's session. On macOS /bin/bash is
# 3.2, which rejects constructs newer bash accepts (e.g. a ")" case pattern
# inside "$( )"). Lint with /bin/bash when present so the macOS runner catches
# the 3.2-specific class that ubuntu's bash 5 would silently accept.
parse_bash=$(command -v bash || echo bash)
[ -x /bin/bash ] && parse_bash=/bin/bash
parse_ver=$("$parse_bash" -c 'echo "${BASH_VERSION:-?}"' 2>/dev/null)
# Lint EVERY shell script the repo ships (installer.sh lives at the root, outside
# skills/ and tests/ - it is the largest script and a member of the same bug
# class). File-fed loop, not a pipe, so the PASS/FAIL counters survive.
find "$REPO_DIR" -name '*.sh' -not -path '*/.git/*' 2>/dev/null | sort > "$TMP/sh_list"
while IFS= read -r parse_s; do
    [ -n "$parse_s" ] || continue
    if parse_err=$("$parse_bash" -n "$parse_s" 2>&1); then
        t_ok "0 parse: ${parse_s#"$REPO_DIR"/} ($parse_bash $parse_ver)"
    else
        t_fail "0 parse: ${parse_s#"$REPO_DIR"/} parse error under $parse_bash $parse_ver" "$parse_err"
    fi
done < "$TMP/sh_list"

# ---- case 0b: the pi adapter (icm-gate.ts) transpiles cleanly ----
# There is no pi harness here, so this cannot test runtime behavior - it verifies
# the TypeScript parses/transpiles, catching syntax breakage that would brick the
# pi enforcement path. Uses bun when present; SKIPs (does not fail) when no TS
# tool exists, so a bare POSIX box still runs the rest of the suite.
icm_gate_ts="$REPO_DIR/skills/icm/runtime/icm-gate.ts"
if command -v bun >/dev/null 2>&1; then
    if bun build "$icm_gate_ts" --target=node --external '*' --outfile="$TMP/icm-gate.js" >"$TMP/bun.out" 2>&1; then
        t_ok "0b pi adapter: icm-gate.ts transpiles (bun)"
    else
        t_fail "0b pi adapter: icm-gate.ts failed to transpile" "$(head -5 "$TMP/bun.out")"
    fi
else
    echo "SKIP  0b pi adapter transpile (bun not installed)"
fi

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
# Gates are scoped to the active stage: close 01-work so 02-send (the gated stage)
# is active and its gate is in scope.
"$ICM" stage-done testns/gated-ws --stage 01-work >/dev/null 2>&1
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

# ---- case 8e: broken icm.sh (parse error) -> fail OPEN, not deny ----
# Regression: a single parse error in icm.sh behind the ".*" matcher must not
# brick the session. The hook must allow the tool (no deny JSON) and warn.
mkdir -p "$TMP/broken"
cp "$HOOK" "$TMP/broken/gate-hook.sh"
printf '#!/bin/sh\nthis is not valid shell ((\n' > "$TMP/broken/icm.sh"
chmod +x "$TMP/broken/icm.sh"
out=$(hook_json mcp__test__send "$PROJECT" | "$TMP/broken/gate-hook.sh" 2>/dev/null); rc=$?
err=$(hook_json mcp__test__send "$PROJECT" | "$TMP/broken/gate-hook.sh" 2>&1 1>/dev/null)
if [ "$rc" -eq 0 ] && ! printf '%s' "$out" | grep -q '"deny"' \
    && printf '%s' "$err" | grep -q 'gate-check could not run'; then
    t_ok "8e hook: broken icm.sh fails open (allow + warn), does not brick"
else
    t_fail "8e hook: broken icm.sh fails open" "rc=$rc out=[$out] err=[$err]"
fi

# ---- case 8f: a genuine DENY still fails closed (regression guard for 8e) ----
out=$(hook_json mcp__test__send "$PROJECT" | (cd "$TMP" && "$HOOK")); rc=$?
if [ "$rc" -eq 0 ] && printf '%s' "$out" | grep -q '"deny"'; then
    t_ok "8f hook: genuine DENY still fails closed"
else
    t_fail "8f hook: genuine DENY still fails closed" "rc=$rc out=$out"
fi

# ---- case 8g: fail-open breadcrumb is valid JSONL even with control chars ----
# A checker whose first output line contains a TAB must not produce an invalid
# JSON line (regression for the tr-strip approach that left control chars in).
mkdir -p "$TMP/broken2"
cp "$HOOK" "$TMP/broken2/gate-hook.sh"
printf '#!/bin/sh\nprintf "checker\\tboom\\n" >&2\nexit 3\n' > "$TMP/broken2/icm.sh"
chmod +x "$TMP/broken2/icm.sh"
hook_json mcp__test__send "$PROJECT" | "$TMP/broken2/gate-hook.sh" >/dev/null 2>&1
bc_line=$(tail -1 "$PROJECT/.icm/telemetry/hook-errors.jsonl" 2>/dev/null)
if [ -n "$bc_line" ] && printf '%s' "$bc_line" | jq -e . >/dev/null 2>&1; then
    t_ok "8g hook: fail-open breadcrumb is valid JSONL (control chars escaped)"
else
    t_fail "8g hook: breadcrumb valid JSONL" "line=[$bc_line]"
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
# Close 01-work so the gated 02-send stage is active.
"$ICM" stage-done testns/gated-ws --stage 01-work >/dev/null 2>&1
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
        && [ "$model" = "x" ] && [ "$matcher" = ".*" ]; then
        t_ok "11 installer --hooks: idempotent, preserves keys, wide matcher"
    else
        t_fail "11 installer --hooks: idempotent, preserves keys, wide matcher" "rc=$rc rc2=$rc2 count=$count model=$model matcher=$matcher out=$out out2=$out2"
    fi

    # ---- case 11b: --hooks migrates a pre-0.6 mcp__.* registration ----
    printf '{"model":"x","hooks":{"PreToolUse":[{"matcher":"mcp__.*","hooks":[{"type":"command","command":"%s","timeout":15}]}]}}\n' \
        "$FAKEHOME/.agents/skills/icm/runtime/gate-hook.sh" > "$settings"
    out=$(HOME="$FAKEHOME" "$REPO_DIR/installer.sh" --hooks 2>&1); rc=$?
    count=$(grep -c 'gate-hook.sh' "$settings")
    matcher=$(jq -r '.hooks.PreToolUse[0].matcher' "$settings")
    model=$(jq -r '.model' "$settings")
    if [ "$rc" -eq 0 ] && [ "$count" -eq 1 ] && [ "$matcher" = ".*" ] && [ "$model" = "x" ]; then
        t_ok "11b installer --hooks: migrates mcp__.* matcher to .*"
    else
        t_fail "11b installer --hooks: migrates mcp__.* matcher to .*" "rc=$rc count=$count matcher=$matcher out=$out"
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
    # Close 01-work so the gated 02-send stage is active.
    "$ICM" stage-done testns/gated-ws --stage 01-work >/dev/null 2>&1
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

    # ---- case 13d: pi adapter records newest session transcript path ----
    mkdir -p "$HOME/.pi/agent/sessions"
    printf '{"ts":"x"}\n' > "$HOME/.pi/agent/sessions/pi-session.jsonl"
    rm -f "$PROJECT/.icm/telemetry/transcript-path"
    out=$(cd "$PROJECT" && node "$DRIVER" "$EXT" mcp__test__send 2>/dev/null) || true
    if [ "$(cat "$PROJECT/.icm/telemetry/transcript-path" 2>/dev/null)" = "$HOME/.pi/agent/sessions/pi-session.jsonl" ]; then
        t_ok "13d pi adapter: records newest session transcript path"
    else
        t_fail "13d pi adapter: records newest session transcript path" "got=$(cat "$PROJECT/.icm/telemetry/transcript-path" 2>/dev/null)"
    fi
    rm -f "$PROJECT/.icm/telemetry/transcript-path"
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

    # ---- case 14b: --remove unregisters hook + pi extension ----
    out=$(HOME="$FAKEHOME" "$REPO_DIR/installer.sh" --remove 2>&1); rc=$?
    settings="$FAKEHOME/.claude/settings.json"
    hook_left=$(grep -c 'gate-hook.sh' "$settings" || true)
    model=$(jq -r '.model' "$settings")
    if [ "$rc" -eq 0 ] && [ "$hook_left" -eq 0 ] && [ "$model" = "x" ] \
        && [ ! -e "$FAKEHOME/.pi/agent/extensions/icm-gate.ts" ]; then
        t_ok "14b installer --remove: unregisters hook and pi extension"
    else
        t_fail "14b installer --remove: unregisters hook and pi extension" "rc=$rc hook_left=$hook_left model=$model out=$out"
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

# ---- case 18b: stage-done writes a stage_done event to events.jsonl ----
"$ICM" stage-done testns/tool-ws --stage 01-work --model claude-test \
    --tokens-in 500 --tokens-out 200 2>/dev/null
_latest_run=$(cd .icm/testns/tool-ws && ls -1 2>/dev/null | sort -r | head -1)
events_jsonl=".icm/testns/tool-ws/$_latest_run/telemetry/events.jsonl"
if [ -f "$events_jsonl" ] && grep -q '"type":"stage_done","stage":"01-work"' "$events_jsonl"; then
    t_ok "18b stage-done: writes stage_done event to telemetry/events.jsonl"
else
    t_fail "18b stage-done: writes stage_done event to telemetry/events.jsonl" "file=$events_jsonl"
fi

# ---- case 18c: events.jsonl carries a run_init header event ----
if grep -q '"type":"run_init"' "$events_jsonl"; then
    t_ok "18c events.jsonl: run_init header event written at init"
else
    t_fail "18c events.jsonl: run_init header event written at init" "file=$events_jsonl"
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
    t_ok "19c audit: reports per-stage token usage from events.jsonl"
else
    t_fail "19c audit: reports per-stage token usage from events.jsonl" "out=$audit_out"
fi

# ---- case 19d: audit handles null token counts without crashing ----
# Append a stage_done event with null counts directly.
_latest_run=$(cd .icm/testns/tool-ws && ls -1 2>/dev/null | sort -r | head -1)
if [ -n "$_latest_run" ]; then
    _run_dir=".icm/testns/tool-ws/$_latest_run"
    printf '{"ts":"2026-06-12T09:00:00Z","type":"stage_done","stage":"02-more","model":"claude-test","tokens_in":null,"cache_creation":null,"cache_read":null,"tokens_out":null,"counts":"estimated","transcript_source":"none"}\n' \
        >> "$_run_dir/telemetry/events.jsonl"
    mkdir -p "$_run_dir/02-more/output"
    printf 'done\n' > "$_run_dir/02-more/output/done.md"
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
# Clear fail-open breadcrumbs left by earlier hook tests (shared project file)
# so this workspace's audit deviation count is deterministic.
rm -f "$run_g/../../../telemetry/hook-errors.jsonl"
printf 'done\n' > "$run_g/01-pub/output/done.md"
# Realistic order: the gate-hook logs the tool DURING stage work, before the
# stage-done boundary -- so the tool falls inside stage 01-pub's window.
"$ICM" gate-check --tool mcp__test__send >/dev/null 2>&1 || true
"$ICM" stage-done testns/icmtools-ws --stage 01-pub --model m >/dev/null 2>&1
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

# ---- case 21c: audit --strict exits 1 when deviations>0 ----
audit_strict=$("$ICM" audit testns/icmtools-ws --strict 2>&1); rc=$?
if [ "$rc" -eq 1 ] && printf '%s' "$audit_strict" | grep -q "STRICT:"; then
    t_ok "21c audit --strict: exits 1 when deviations>0"
else
    t_fail "21c audit --strict: exits 1 when deviations>0" "rc=$rc out=$audit_strict"
fi

# ---- case 21d: bare audit stays exit 0 with deviations (informational) ----
"$ICM" audit testns/icmtools-ws >/dev/null 2>&1; rc=$?
if [ "$rc" -eq 0 ]; then
    t_ok "21d audit: bare audit stays exit 0 with deviations"
else
    t_fail "21d audit: bare audit stays exit 0 with deviations" "rc=$rc"
fi

# ---- case 21e: fail-open events surfaced and counted as deviations ----
icm_tdir="$run_g/../../../telemetry"
mkdir -p "$icm_tdir"
printf '{"ts":"2099-01-01T00:00:00Z","event":"gate-check-error","tool":"Bash","rc":2,"msg":"boom"}\n' >> "$icm_tdir/hook-errors.jsonl"
audit_fo=$("$ICM" audit testns/icmtools-ws 2>&1)
if printf '%s' "$audit_fo" | grep -q "FAIL-OPEN EVENTS" \
    && printf '%s' "$audit_fo" | grep -q "Deviations: 2"; then
    t_ok "21e audit: fail-open event surfaced and counted"
else
    t_fail "21e audit: fail-open event surfaced and counted" "out=$audit_fo"
fi
rm -f "$icm_tdir/hook-errors.jsonl"

# ---- case 21f/21g: PER-STAGE tool attribution (controlled timestamps) ----
# Hand-build a 2-stage run with fixed boundaries so windowing is deterministic:
#   stage 01-a done @ :10, stage 02-b done @ :20 ; run_start = :00 (dir name)
#   toolA called @ :05 (-> stage 01-a window [:00,:10]), toolB @ :15 (-> 02-b (:10,:20])
# Future ts (2030) so these lines are isolated from real entries; cleaned after.
RUN5=".icm/testns/perstage-ws/2030-01-01_00-00-00"
mkdir -p "$RUN5/01-a/output" "$RUN5/02-b/output" "$RUN5/telemetry"
printf '# 01-a\n<!-- ICM-TOOLS expect="toolA" -->\n' > "$RUN5/01-a/CONTEXT.md"
printf '# 02-b\n<!-- ICM-TOOLS expect="toolB" -->\n' > "$RUN5/02-b/CONTEXT.md"
printf 'x\n' > "$RUN5/01-a/output/o.md"; printf 'x\n' > "$RUN5/02-b/output/o.md"
printf '{"ts":"2030-01-01T00:00:10Z","type":"stage_done","stage":"01-a","model":"m","tokens_in":null,"cache_creation":null,"cache_read":null,"tokens_out":null,"counts":"estimated","transcript_source":"none"}\n' > "$RUN5/telemetry/events.jsonl"
printf '{"ts":"2030-01-01T00:00:20Z","type":"stage_done","stage":"02-b","model":"m","tokens_in":null,"cache_creation":null,"cache_read":null,"tokens_out":null,"counts":"estimated","transcript_source":"none"}\n' >> "$RUN5/telemetry/events.jsonl"
TC5="$RUN5/../../../telemetry/tool-calls.jsonl"
mkdir -p "$RUN5/../../../telemetry"
printf '{"ts":"2030-01-01T00:00:05Z","tool":"icm.sh","cmd":"gate-check","args":["gate-check","--tool","toolA"],"cwd":"x","ec":0}\n' >> "$TC5"
printf '{"ts":"2030-01-01T00:00:15Z","tool":"icm.sh","cmd":"gate-check","args":["gate-check","--tool","toolB"],"cwd":"x","ec":0}\n' >> "$TC5"
audit5=$("$ICM" audit testns/perstage-ws 2>&1)
if printf '%s' "$audit5" | grep -q "✓ toolA" \
    && printf '%s' "$audit5" | grep -q "✓ toolB" \
    && ! printf '%s' "$audit5" | grep -q "✗ tool" \
    && printf '%s' "$audit5" | grep -q "Deviations: 0"; then
    t_ok "21f audit: per-stage attribution maps toolA->01-a, toolB->02-b"
else
    t_fail "21f audit: per-stage attribution" "out=$audit5"
fi
# 21g (the proof): stage 01-a now expects toolB, which was only used in stage 02-b.
# Run-wide it would pass; per-stage it must FAIL.
printf '# 01-a\n<!-- ICM-TOOLS expect="toolB" -->\n' > "$RUN5/01-a/CONTEXT.md"
audit5b=$("$ICM" audit testns/perstage-ws --strict 2>&1); rc=$?
if [ "$rc" -eq 1 ] && printf '%s' "$audit5b" | grep -q "✗ toolB"; then
    t_ok "21g audit: cross-stage tool no longer satisfies (per-stage proof)"
else
    t_fail "21g audit: cross-stage tool no longer satisfies" "rc=$rc out=$audit5b"
fi
# Robust cleanup: grep -v exits 1 if it keeps zero lines, which would skip a
# chained mv and leak the ghost lines. Guard with || true and always mv.
{ grep -v '2030-01-01T00:00:05Z\|2030-01-01T00:00:15Z' "$TC5" || true; } > "$TC5.tmp"; mv "$TC5.tmp" "$TC5"

# ---- case 21h: missing mid-pipeline stage-done -> unreliable, no false ✓ ----
# 3 stages, 02-b has NO stage-done; toolB called in the gap (:15). Pre-fix, 03-c's
# window (:10,:30] would absorb toolB and wrongly print "✓ toolB".
RUN6=".icm/testns/perstage-gap/2030-02-01_00-00-00"
mkdir -p "$RUN6/01-a/output" "$RUN6/02-b/output" "$RUN6/03-c/output" "$RUN6/telemetry"
printf '# 01-a\n<!-- ICM-TOOLS expect="toolA" -->\n' > "$RUN6/01-a/CONTEXT.md"
printf '# 02-b\n<!-- ICM-TOOLS expect="toolB" -->\n' > "$RUN6/02-b/CONTEXT.md"
printf '# 03-c\n<!-- ICM-TOOLS expect="toolB" -->\n' > "$RUN6/03-c/CONTEXT.md"
for s in 01-a 02-b 03-c; do printf 'x\n' > "$RUN6/$s/output/o.md"; done
printf '{"ts":"2030-02-01T00:00:10Z","type":"stage_done","stage":"01-a","model":"m","tokens_in":null,"cache_creation":null,"cache_read":null,"tokens_out":null,"counts":"estimated","transcript_source":"none"}\n' > "$RUN6/telemetry/events.jsonl"
printf '{"ts":"2030-02-01T00:00:30Z","type":"stage_done","stage":"03-c","model":"m","tokens_in":null,"cache_creation":null,"cache_read":null,"tokens_out":null,"counts":"estimated","transcript_source":"none"}\n' >> "$RUN6/telemetry/events.jsonl"
TC6="$RUN6/../../../telemetry/tool-calls.jsonl"
printf '{"ts":"2030-02-01T00:00:15Z","tool":"icm.sh","cmd":"gate-check","args":["gate-check","--tool","toolB"],"cwd":"x","ec":0}\n' >> "$TC6"
audit6=$("$ICM" audit testns/perstage-gap 2>&1)
if printf '%s' "$audit6" | grep -q "attribution unreliable" \
    && ! printf '%s' "$audit6" | grep -q "✓ toolB"; then
    t_ok "21h audit: missing stage-done -> unreliable, no false-positive"
else
    t_fail "21h audit: missing stage-done -> unreliable" "out=$audit6"
fi
{ grep -v '2030-02-01T00:00:15Z' "$TC6" || true; } > "$TC6.tmp"; mv "$TC6.tmp" "$TC6"

# ---- case 21i: re-run (non-monotonic boundary) -> unreliable, no false ✗ ----
# 01-a re-run @:50 (after 02-b @:20). Pre-fix, 02-b window (:50,:20] inverts and
# silently drops toolB@:15 -> "✗ toolB" false negative.
RUN7=".icm/testns/perstage-rerun/2030-03-01_00-00-00"
mkdir -p "$RUN7/01-a/output" "$RUN7/02-b/output" "$RUN7/telemetry"
printf '# 01-a\n<!-- ICM-TOOLS expect="toolA" -->\n' > "$RUN7/01-a/CONTEXT.md"
printf '# 02-b\n<!-- ICM-TOOLS expect="toolB" -->\n' > "$RUN7/02-b/CONTEXT.md"
printf 'x\n' > "$RUN7/01-a/output/o.md"; printf 'x\n' > "$RUN7/02-b/output/o.md"
{ printf '{"ts":"2030-03-01T00:00:10Z","type":"stage_done","stage":"01-a","model":"m","tokens_in":null,"cache_creation":null,"cache_read":null,"tokens_out":null,"counts":"estimated","transcript_source":"none"}\n'
  printf '{"ts":"2030-03-01T00:00:20Z","type":"stage_done","stage":"02-b","model":"m","tokens_in":null,"cache_creation":null,"cache_read":null,"tokens_out":null,"counts":"estimated","transcript_source":"none"}\n'
  printf '{"ts":"2030-03-01T00:00:50Z","type":"stage_done","stage":"01-a","model":"m","tokens_in":1,"cache_creation":0,"cache_read":0,"tokens_out":1,"counts":"transcript","transcript_source":"none"}\n'; } > "$RUN7/telemetry/events.jsonl"
TC7="$RUN7/../../../telemetry/tool-calls.jsonl"
printf '{"ts":"2030-03-01T00:00:15Z","tool":"icm.sh","cmd":"gate-check","args":["gate-check","--tool","toolB"],"cwd":"x","ec":0}\n' >> "$TC7"
audit7=$("$ICM" audit testns/perstage-rerun 2>&1)
if printf '%s' "$audit7" | grep -q "non-monotonic" \
    && ! printf '%s' "$audit7" | grep -q "✗ toolB"; then
    t_ok "21i audit: re-run non-monotonic -> unreliable, no false-negative"
else
    t_fail "21i audit: re-run non-monotonic -> unreliable" "out=$audit7"
fi
{ grep -v '2030-03-01T00:00:15Z' "$TC7" || true; } > "$TC7.tmp"; mv "$TC7.tmp" "$TC7"

# ---- case 21j: same-second boundary tool lands in the earlier stage ----
# tool @ exactly ts1 (:10) -> stage1 (inclusive upper), NOT stage2 (exclusive lower).
RUN8=".icm/testns/perstage-edge/2030-04-01_00-00-00"
mkdir -p "$RUN8/01-a/output" "$RUN8/02-b/output" "$RUN8/telemetry"
printf '# 01-a\n<!-- ICM-TOOLS expect="toolX" -->\n' > "$RUN8/01-a/CONTEXT.md"
printf '# 02-b\n<!-- ICM-TOOLS expect="toolX" -->\n' > "$RUN8/02-b/CONTEXT.md"
printf 'x\n' > "$RUN8/01-a/output/o.md"; printf 'x\n' > "$RUN8/02-b/output/o.md"
printf '{"ts":"2030-04-01T00:00:10Z","type":"stage_done","stage":"01-a","model":"m","tokens_in":null,"cache_creation":null,"cache_read":null,"tokens_out":null,"counts":"estimated","transcript_source":"none"}\n' > "$RUN8/telemetry/events.jsonl"
printf '{"ts":"2030-04-01T00:00:20Z","type":"stage_done","stage":"02-b","model":"m","tokens_in":null,"cache_creation":null,"cache_read":null,"tokens_out":null,"counts":"estimated","transcript_source":"none"}\n' >> "$RUN8/telemetry/events.jsonl"
TC8="$RUN8/../../../telemetry/tool-calls.jsonl"
printf '{"ts":"2030-04-01T00:00:10Z","tool":"icm.sh","cmd":"gate-check","args":["gate-check","--tool","toolX"],"cwd":"x","ec":0}\n' >> "$TC8"
audit8=$("$ICM" audit testns/perstage-edge 2>&1)
if printf '%s' "$audit8" | grep -q "✓ toolX" && printf '%s' "$audit8" | grep -q "✗ toolX"; then
    t_ok "21j audit: boundary tool lands in earlier stage (inclusive upper, exclusive lower)"
else
    t_fail "21j audit: boundary tool attribution" "out=$audit8"
fi
{ grep -v '2030-04-01T00:00:10Z' "$TC8" || true; } > "$TC8.tmp"; mv "$TC8.tmp" "$TC8"

# ---- case 21k: gates declared but no enforcement records -> advisory banner ----
# A run that declares ICM-TOOLS but has no gate-check records (hook not installed).
# Future ts isolates it from the shared tool-calls.jsonl; no --tool lines exist.
RUN9=".icm/testns/advisory-ws/2031-01-01_00-00-00"
mkdir -p "$RUN9/01-a/output" "$RUN9/telemetry"
printf '# 01-a\n<!-- ICM-TOOLS expect="toolZ" -->\n' > "$RUN9/01-a/CONTEXT.md"
printf 'x\n' > "$RUN9/01-a/output/o.md"
printf '{"ts":"2031-01-01T00:00:10Z","type":"stage_done","stage":"01-a","model":"m","tokens_in":null,"cache_creation":null,"cache_read":null,"tokens_out":null,"counts":"estimated","transcript_source":"none"}\n' > "$RUN9/telemetry/events.jsonl"
audit9=$("$ICM" audit testns/advisory-ws 2>&1); rc9=$?
"$ICM" audit testns/advisory-ws --strict >/dev/null 2>&1; rc9s=$?
if [ "$rc9" -eq 0 ] && printf '%s' "$audit9" | grep -q "GATES NOT ENFORCED" \
    && printf '%s' "$audit9" | grep -q "ADVISORY ONLY" \
    && [ "$rc9s" -eq 1 ]; then
    t_ok "21k audit: gates declared without enforcement -> advisory banner, strict fails"
else
    t_fail "21k audit: gates declared without enforcement -> advisory banner" "rc=$rc9 rc_strict=$rc9s out=$audit9"
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
    sj="$run_h/telemetry/events.jsonl"
    if [ "$rc" -eq 0 ] && grep -q '"type":"reify".*"counts":"transcript"' "$sj" \
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
    sj="$run_i/telemetry/events.jsonl"
    if [ "$rc" -eq 0 ] && printf '%s' "$out" | grep -q "picked newest" \
        && printf '%s' "$out" | grep -q "new.jsonl" \
        && grep -q '"type":"reify".*"tokens_in":7' "$sj"; then
        t_ok "23 reify-telemetry: auto-detect picks newest by mtime + warns"
    else
        t_fail "23 reify-telemetry: auto-detect picks newest by mtime + warns" "rc=$rc out=$out sj=$(cat "$sj" 2>/dev/null)"
    fi
    rm -rf "$HOME/.claude/projects"
else
    echo "SKIP  23 reify-telemetry auto-detect (jq not installed)"
fi

# ---- case 24: stage-done snapshots usage events + computes counts ----
if command -v jq >/dev/null 2>&1; then
    sleep 1
    run_j=$("$ICM" init testns/tool-ws 2>/dev/null)
    ts_now=$(date -u +%Y-%m-%dT%H:%M:%SZ)
    printf '{"ts":"%s","usage":{"input_tokens":11,"output_tokens":5}}\n{"ts":"%s","usage":{"input_tokens":9,"output_tokens":4}}\n' \
        "$ts_now" "$ts_now" > "$TMP/sess.jsonl"
    printf '%s\n' "$TMP/sess.jsonl" > .icm/telemetry/transcript-path
    printf 'done\n' > "$run_j/01-work/output/done.md"
    "$ICM" stage-done testns/tool-ws --stage 01-work --model m >/dev/null 2>&1
    ej="$run_j/telemetry/events.jsonl"
    if [ "$(grep -c '"type":"usage","stage":"01-work"' "$ej")" -eq 2 ] \
        && grep -q '"type":"stage_done","stage":"01-work"' "$ej" \
        && grep -q '"tokens_in":20' "$ej" && grep -q '"tokens_out":9' "$ej" \
        && grep -q '"counts":"transcript"' "$ej"; then
        t_ok "24 stage-done: usage events + 4-field counts in events.jsonl"
    else
        t_fail "24 stage-done: usage events + 4-field counts in events.jsonl" "ej=$(cat "$ej" 2>/dev/null)"
    fi

    # ---- case 24b: --full freezes raw window into the stage dir ----
    sleep 1
    run_k=$("$ICM" init testns/tool-ws 2>/dev/null)
    ts_now=$(date -u +%Y-%m-%dT%H:%M:%SZ)
    printf '{"ts":"%s","usage":{"input_tokens":3,"output_tokens":2}}\n{"ts":"%s","type":"text","content":"hello"}\n' \
        "$ts_now" "$ts_now" > "$TMP/sess.jsonl"
    printf 'done\n' > "$run_k/01-work/output/done.md"
    "$ICM" stage-done testns/tool-ws --stage 01-work --model m --full >/dev/null 2>&1
    ft="$run_k/01-work/transcript.jsonl"
    if [ -f "$ft" ] && [ "$(wc -l < "$ft" | tr -d ' ')" -eq 2 ] && grep -q '"content":"hello"' "$ft"; then
        t_ok "24b stage-done --full: raw window frozen into stage dir"
    else
        t_fail "24b stage-done --full: raw window frozen into stage dir" "ft=$(cat "$ft" 2>/dev/null)"
    fi
    # ---- case 24c: Claude Code format -- nested usage, dup message ids, cache ----
    sleep 1
    run_l=$("$ICM" init testns/tool-ws 2>/dev/null)
    ts_now=$(date -u +%Y-%m-%dT%H:%M:%SZ)
    cat > "$TMP/sess.jsonl" <<EOF
{"type":"assistant","timestamp":"$ts_now","message":{"id":"msg_1","model":"claude-x","usage":{"input_tokens":10,"cache_read_input_tokens":1000,"cache_creation_input_tokens":5,"output_tokens":40}}}
{"type":"assistant","timestamp":"$ts_now","message":{"id":"msg_1","model":"claude-x","usage":{"input_tokens":10,"cache_read_input_tokens":1000,"cache_creation_input_tokens":5,"output_tokens":40}}}
{"type":"assistant","timestamp":"$ts_now","message":{"id":"msg_2","model":"claude-x","usage":{"input_tokens":2,"output_tokens":8}}}
EOF
    printf 'done\n' > "$run_l/01-work/output/done.md"
    "$ICM" stage-done testns/tool-ws --stage 01-work --model m >/dev/null 2>&1
    ej="$run_l/telemetry/events.jsonl"
    if [ "$(grep -c '"type":"usage","stage":"01-work"' "$ej" 2>/dev/null)" -eq 2 ] \
        && grep -q '"type":"stage_done"' "$ej" && grep -q '"tokens_in":12' "$ej" \
        && grep -q '"cache_creation":5' "$ej" && grep -q '"cache_read":1000' "$ej" \
        && grep -q '"tokens_out":48' "$ej"; then
        t_ok "24c stage-done: Claude dedup; new-input/cache split (Obs 2 fix)"
    else
        t_fail "24c stage-done: Claude dedup; new-input/cache split" "ej=$(cat "$ej" 2>/dev/null)"
    fi
    # ---- case 24d: session-env transcript wins over a clobbered hook path ----
    # Concurrency: another session overwrote .icm/telemetry/transcript-path with
    # its own transcript. With CLAUDE_CODE_SESSION_ID set this run must resolve
    # its OWN transcript deterministically, not the clobbered shared file.
    sleep 1
    run_m=$("$ICM" init testns/tool-ws 2>/dev/null)
    ts_now=$(date -u +%Y-%m-%dT%H:%M:%SZ)
    munged=$(printf '%s' "$PROJECT" | sed 's,[/.],-,g')
    sdir="$HOME/.claude/projects/$munged"
    mkdir -p "$sdir"
    printf '{"ts":"%s","usage":{"input_tokens":42,"output_tokens":7}}\n' "$ts_now" > "$sdir/mysession.jsonl"
    printf '{"ts":"%s","usage":{"input_tokens":999,"output_tokens":999}}\n' "$ts_now" > "$TMP/wrong.jsonl"
    printf '%s\n' "$TMP/wrong.jsonl" > .icm/telemetry/transcript-path
    printf 'done\n' > "$run_m/01-work/output/done.md"
    CLAUDECODE=1 CLAUDE_CODE_SESSION_ID=mysession "$ICM" stage-done testns/tool-ws --stage 01-work --model m >/dev/null 2>&1
    sj="$run_m/telemetry/events.jsonl"
    if grep -q '"tokens_in":42' "$sj" && grep -q '"transcript_source":"session-env"' "$sj" \
        && ! grep -q '999' "$sj"; then
        t_ok "24d stage-done: session-env transcript beats clobbered hook path"
    else
        t_fail "24d stage-done: session-env transcript beats clobbered hook path" "sj=$(cat "$sj" 2>/dev/null)"
    fi
    rm -rf "$HOME/.claude/projects"
    rm -f .icm/telemetry/transcript-path
    # ---- case 24e: scan fallback is cwd-filtered + provenance recorded ----
    sleep 1
    run_n=$("$ICM" init testns/tool-ws 2>/dev/null)
    ts_now=$(date -u +%Y-%m-%dT%H:%M:%SZ)
    munged=$(printf '%s' "$PROJECT" | sed 's,[/.],-,g')
    sdir="$HOME/.claude/projects/$munged"
    mkdir -p "$sdir"
    printf '{"ts":"%s","usage":{"input_tokens":13,"output_tokens":4}}\n' "$ts_now" > "$sdir/scan.jsonl"
    printf 'done\n' > "$run_n/01-work/output/done.md"
    env -u CLAUDE_CODE_SESSION_ID CLAUDECODE=1 "$ICM" stage-done testns/tool-ws --stage 01-work --model m >/dev/null 2>&1
    sj="$run_n/telemetry/events.jsonl"
    if grep -q '"transcript_source":"fallback-cwd"' "$sj" && grep -q '"tokens_in":13' "$sj"; then
        t_ok "24e stage-done: scan fallback is cwd-filtered + provenance recorded"
    else
        t_fail "24e stage-done: scan fallback is cwd-filtered + provenance recorded" "sj=$(cat "$sj" 2>/dev/null)"
    fi
    rm -rf "$HOME/.claude/projects"
    rm -f .icm/telemetry/transcript-path
    # ---- case 24f: transcript counts override hand-passed --tokens-in ----
    sleep 1
    run_o=$("$ICM" init testns/tool-ws 2>/dev/null)
    ts_now=$(date -u +%Y-%m-%dT%H:%M:%SZ)
    printf '{"ts":"%s","usage":{"input_tokens":11,"output_tokens":5}}\n' "$ts_now" > "$TMP/sess.jsonl"
    printf '%s\n' "$TMP/sess.jsonl" > .icm/telemetry/transcript-path
    printf 'done\n' > "$run_o/01-work/output/done.md"
    env -u CLAUDE_CODE_SESSION_ID "$ICM" stage-done testns/tool-ws --stage 01-work --model m --tokens-in 999999 --tokens-out 888888 >/dev/null 2>&1
    sj="$run_o/telemetry/events.jsonl"
    if grep -q '"tokens_in":11' "$sj" && grep -q '"tokens_out":5' "$sj" \
        && grep -q '"counts":"transcript"' "$sj" && ! grep -q '999999' "$sj"; then
        t_ok "24f stage-done: transcript counts override hand-passed --tokens-in"
    else
        t_fail "24f stage-done: transcript counts override hand-passed --tokens-in" "sj=$(cat "$sj" 2>/dev/null)"
    fi
    rm -f .icm/telemetry/transcript-path
    # ---- case 24g: provisional global entry at stage-done, final after reify ----
    sleep 1
    run_p=$("$ICM" init testns/tool-ws 2>/dev/null)
    ts_now=$(date -u +%Y-%m-%dT%H:%M:%SZ)
    printf '{"ts":"%s","usage":{"input_tokens":17,"output_tokens":6}}\n' "$ts_now" > "$TMP/sess.jsonl"
    printf '%s\n' "$TMP/sess.jsonl" > .icm/telemetry/transcript-path
    printf 'done\n' > "$run_p/01-work/output/done.md"
    pid_run=$(basename "$run_p")
    env -u CLAUDE_CODE_SESSION_ID "$ICM" stage-done testns/tool-ws --stage 01-work --model m >/dev/null 2>&1
    g="$HOME/.icm/telemetry/skill-runs.jsonl"
    prov=$(grep "\"run_id\":\"$pid_run\"" "$g" | grep -c '"status":"provisional"')
    env -u CLAUDE_CODE_SESSION_ID "$ICM" reify-telemetry testns/tool-ws >/dev/null 2>&1
    fin=$(grep "\"run_id\":\"$pid_run\"" "$g" | grep -c '"status":"final"')
    last=$(grep "\"run_id\":\"$pid_run\"" "$g" | tail -1)
    if [ "$prov" -ge 1 ] && [ "$fin" -ge 1 ] \
        && printf '%s' "$last" | grep -q '"status":"final"' \
        && printf '%s' "$last" | grep -q '"tokens_in":17'; then
        t_ok "24g telemetry: provisional entry at stage-done, final after reify"
    else
        t_fail "24g telemetry: provisional entry at stage-done, final after reify" "prov=$prov fin=$fin last=$last"
    fi
    rm -f .icm/telemetry/transcript-path
else
    echo "SKIP  24 stage-done snapshot (jq not installed)"
fi

# ---- case 25: gate-hook records transcript_path into .icm/telemetry ----
rm -f "$PROJECT/.icm/telemetry/transcript-path"
hook_json mcp__other__thing "$PROJECT" | "$HOOK" >/dev/null 2>&1 || true
if [ -f "$PROJECT/.icm/telemetry/transcript-path" ] \
    && [ "$(cat "$PROJECT/.icm/telemetry/transcript-path")" = "/tmp/t.jsonl" ]; then
    t_ok "25 gate-hook: records transcript_path for snapshots"
else
    t_fail "25 gate-hook: records transcript_path for snapshots" "got=$(cat "$PROJECT/.icm/telemetry/transcript-path" 2>/dev/null)"
fi
rm -f "$PROJECT/.icm/telemetry/transcript-path"

# ---- case 26: seal + verify-seal + tamper detection ----
out=$("$ICM" seal testns/tool-ws 2>&1); rc=$?
v_ok=$("$ICM" verify-seal testns/tool-ws 2>&1); rc_ok=$?
_latest_run=$(cd .icm/testns/tool-ws && ls -1 2>/dev/null | sort -r | head -1)
printf 'x' >> ".icm/testns/tool-ws/$_latest_run/telemetry/events.jsonl"
v_bad=$("$ICM" verify-seal testns/tool-ws 2>&1); rc_bad=$?
if [ "$rc" -eq 0 ] && [ -f .icm-seals.log ] \
    && [ "$rc_ok" -eq 0 ] && printf '%s' "$v_ok" | grep -q "SEAL OK" \
    && [ "$rc_bad" -eq 1 ] && printf '%s' "$v_bad" | grep -q "SEAL MISMATCH.*events.jsonl"; then
    t_ok "26 seal: digests recorded, verify-seal detects tampering"
else
    t_fail "26 seal: digests recorded, verify-seal detects tampering" "rc=$rc rc_ok=$rc_ok rc_bad=$rc_bad ok=$v_ok bad=$v_bad"
fi

# ---- case 27: built-in tool names gate end-to-end through the hook ----
WS5_DIR="$TMP/skills/testns/builtin-ws"
mkdir -p "$WS5_DIR/stages"
cat > "$WS5_DIR/stages/01-send.md" <<'EOF'
# Stage 01
<!-- ICM-GATE tools="^WebSearch$" run="grep -Eq '^RESULT: PASS$' output/evidence.md" -->
EOF
run_m=$("$ICM" init testns/builtin-ws 2>/dev/null)
out=$(hook_json WebSearch "$PROJECT" | (cd "$TMP" && "$HOOK")); rc=$?
out2=$(hook_json Bash "$PROJECT" | (cd "$TMP" && "$HOOK")); rc2=$?
if [ "$rc" -eq 0 ] && printf '%s' "$out" | grep -q '"deny"' && printf '%s' "$out" | grep -q '01-send' \
    && [ "$rc2" -eq 0 ] && [ -z "$out2" ]; then
    t_ok "27 hook: built-in tool gated (WebSearch deny, Bash untouched)"
else
    t_fail "27 hook: built-in tool gated (WebSearch deny, Bash untouched)" "rc=$rc out=$out rc2=$rc2 out2=$out2"
fi
printf 'RESULT: PASS\n' > "$run_m/01-send/output/evidence.md"
out=$(hook_json WebSearch "$PROJECT" | (cd "$TMP" && "$HOOK")); rc=$?
if [ "$rc" -eq 0 ] && [ -z "$out" ]; then
    t_ok "27b hook: built-in tool allowed once checker passes"
else
    t_fail "27b hook: built-in tool allowed once checker passes" "rc=$rc out=$out"
fi

# ---- case 28: verify-seal --all across workspaces, skip pruned runs ----
"$ICM" seal testns/builtin-ws >/dev/null 2>&1
v_all=$("$ICM" verify-seal --all 2>&1); rc_all=$?
if [ "$rc_all" -eq 1 ] \
    && printf '%s' "$v_all" | grep -q "SEAL OK testns/builtin-ws" \
    && printf '%s' "$v_all" | grep -q "SEAL MISMATCH testns/tool-ws"; then
    t_ok "28 verify-seal --all: aggregates OK and MISMATCH across workspaces"
else
    t_fail "28 verify-seal --all: aggregates OK and MISMATCH across workspaces" "rc=$rc_all out=$v_all"
fi
_latest_run=$(cd .icm/testns/tool-ws && ls -1 2>/dev/null | sort -r | head -1)
rm -rf ".icm/testns/tool-ws/$_latest_run"
v_all=$("$ICM" verify-seal --all 2>&1); rc_all=$?
if [ "$rc_all" -eq 0 ] && printf '%s' "$v_all" | grep -q "SEAL SKIP testns/tool-ws"; then
    t_ok "28b verify-seal --all: pruned run skipped, exit 0"
else
    t_fail "28b verify-seal --all: pruned run skipped, exit 0" "rc=$rc_all out=$v_all"
fi

# ---- case 29: clean rotates tool-calls.jsonl past 10000 lines ----
awk 'BEGIN{for(i=0;i<10500;i++)print "{\"ts\":\"2026-01-01T00:00:00Z\",\"tool\":\"icm.sh\",\"cmd\":\"pad\",\"args\":[\"pad\"],\"cwd\":\"/\",\"ec\":0}"}' \
    >> .icm/telemetry/tool-calls.jsonl
out=$("$ICM" clean testns/tool-ws --keep 5 2>&1); rc=$?
# clean's own exit appends one telemetry line after rotating: 10000 + 1.
lines=$(wc -l < .icm/telemetry/tool-calls.jsonl | tr -d ' ')
if [ "$rc" -eq 0 ] && [ "$lines" -le 10001 ] && printf '%s' "$out" | grep -q "Rotated tool-calls.jsonl"; then
    t_ok "29 clean: rotates tool-calls.jsonl to last 10000 lines"
else
    t_fail "29 clean: rotates tool-calls.jsonl to last 10000 lines" "rc=$rc lines=$lines out=$out"
fi

# ---- case 30: --caller linkage recorded on child, propagated, queryable, sealed ----
mkdir -p "$TMP/skills/testns/caller-parent/stages" "$TMP/skills/testns/caller-child/stages"
printf '# p\nwork\n' > "$TMP/skills/testns/caller-parent/stages/01-work.md"
printf '# c\nwork\n' > "$TMP/skills/testns/caller-child/stages/01-work.md"

cp_parent=$("$ICM" init testns/caller-parent 2>/dev/null); cp_pts=$(basename "$cp_parent")
cp_child=$("$ICM" init testns/caller-child --caller "testns/caller-parent/$cp_pts/01-work" 2>/dev/null)
cp_cts=$(basename "$cp_child")

if grep -q '"caller": "testns/caller-parent/'"$cp_pts"'/01-work"' "$cp_child/telemetry/run.json"; then
    t_ok "30 init --caller: records caller line in child run.json"
else
    t_fail "30 init --caller: records caller line in child run.json" "$(cat "$cp_child/telemetry/run.json")"
fi

# 30b: standalone init writes no caller line (run.json shape unchanged)
if ! grep -q '"caller"' "$cp_parent/telemetry/run.json"; then
    t_ok "30b init without --caller: no caller line (standalone unchanged)"
else
    t_fail "30b init without --caller: no caller line" "$(cat "$cp_parent/telemetry/run.json")"
fi

# 30c: run.json stays valid JSON with the caller field (jq optional)
if command -v jq >/dev/null 2>&1; then
    if jq -e '.caller == "testns/caller-parent/'"$cp_pts"'/01-work"' "$cp_child/telemetry/run.json" >/dev/null 2>&1; then
        t_ok "30c init --caller: run.json parses as JSON with caller field"
    else
        t_fail "30c init --caller: run.json parses as JSON with caller field" "$(cat "$cp_child/telemetry/run.json")"
    fi
else
    t_ok "30c init --caller: jq absent, JSON parse check skipped"
fi

# 30d: telemetry propagates caller to skill-runs.jsonl; null when standalone
printf 'done\n' > "$cp_child/01-work/output/d.md"
"$ICM" telemetry testns/caller-child --model m --tokens-in 1 --tokens-out 1 --cost 0 >/dev/null 2>&1 || true
printf 'done\n' > "$cp_parent/01-work/output/d.md"
"$ICM" telemetry testns/caller-parent --model m --tokens-in 1 --tokens-out 1 --cost 0 >/dev/null 2>&1 || true
if grep -q '"skill":"testns/caller-child".*"caller":"testns/caller-parent/'"$cp_pts"'/01-work"' "$GLOBAL_TELEM" \
    && grep -q '"skill":"testns/caller-parent".*"caller":null' "$GLOBAL_TELEM"; then
    t_ok "30d telemetry: caller propagated to skill-runs.jsonl (null when standalone)"
else
    t_fail "30d telemetry: caller propagated to skill-runs.jsonl" "$(grep -h 'caller-parent\|caller-child' "$GLOBAL_TELEM")"
fi

# 30e: children lists the child under the parent run, with the invoking stage
ch_out=$("$ICM" children testns/caller-parent "$cp_pts" 2>&1); ch_rc=$?
if [ "$ch_rc" -eq 0 ] \
    && printf '%s' "$ch_out" | grep -q "testns/caller-child/$cp_cts" \
    && printf '%s' "$ch_out" | grep -q "from stage: 01-work"; then
    t_ok "30e children: lists child run with invoking stage"
else
    t_fail "30e children: lists child run with invoking stage" "rc=$ch_rc out=$ch_out"
fi

# 30f: a leaf run reports no children
ch_out=$("$ICM" children testns/caller-child "$cp_cts" 2>&1)
if printf '%s' "$ch_out" | grep -q "no children for testns/caller-child/$cp_cts"; then
    t_ok "30f children: leaf run reports none"
else
    t_fail "30f children: leaf run reports none" "out=$ch_out"
fi

# 30g: caller is in the sealed set -> tampering it trips verify-seal
"$ICM" seal testns/caller-child >/dev/null 2>&1
sed 's#caller-parent#caller-EVIL#' "$cp_child/telemetry/run.json" > "$cp_child/telemetry/run.json.t" \
    && mv "$cp_child/telemetry/run.json.t" "$cp_child/telemetry/run.json"
vout=$("$ICM" verify-seal testns/caller-child 2>&1); vrc=$?
if [ "$vrc" -eq 1 ] && printf '%s' "$vout" | grep -q "SEAL MISMATCH"; then
    t_ok "30g seal: tampered caller trips verify-seal (linkage is tamper-evident)"
else
    t_fail "30g seal: tampered caller trips verify-seal" "rc=$vrc out=$vout"
fi

# ---- case 31: seal covers stage output files (work product is tamper-evident) ----
WS_SEALOUT="$TMP/skills/testns/seal-out-ws"
mkdir -p "$WS_SEALOUT/stages"
printf '# 01-make\nproduce output\n' > "$WS_SEALOUT/stages/01-make.md"
run_so=$("$ICM" init testns/seal-out-ws 2>/dev/null)
mkdir -p "$run_so/01-make/output"
printf 'original output\n' > "$run_so/01-make/output/result.md"
"$ICM" seal testns/seal-out-ws >/dev/null 2>&1
so_line=$(grep '"workspace":"testns/seal-out-ws"' .icm-seals.log | tail -1)
so_ok=$("$ICM" verify-seal testns/seal-out-ws 2>&1); so_rc_ok=$?
# Tamper ONLY the output file -> verify-seal must trip on that path.
printf 'TAMPERED\n' >> "$run_so/01-make/output/result.md"
so_bad=$("$ICM" verify-seal testns/seal-out-ws 2>&1); so_rc_bad=$?
if printf '%s' "$so_line" | grep -q '01-make/output/result.md' \
    && [ "$so_rc_ok" -eq 0 ] && printf '%s' "$so_ok" | grep -q "SEAL OK" \
    && [ "$so_rc_bad" -eq 1 ] && printf '%s' "$so_bad" | grep -q "SEAL MISMATCH.*01-make/output/result.md"; then
    t_ok "31 seal: stage output files sealed and tamper-evident"
else
    t_fail "31 seal: stage output files sealed and tamper-evident" "line=$so_line rc_ok=$so_rc_ok rc_bad=$so_rc_bad ok=$so_ok bad=$so_bad"
fi

# ---- case 41: gates are scoped to the active stage (deadlock fix) ----
# A later stage's Write gate must NOT deny Write while an earlier stage is active.
WS_SCOPE="$TMP/skills/testns/scope-ws"
mkdir -p "$WS_SCOPE/stages"
printf '# 01-a\nwrite frame\n' > "$WS_SCOPE/stages/01-a.md"
printf '# 02-b\n<!-- ICM-GATE tools="Write" run="test -s ../01-a/output/frame.md" -->\n' > "$WS_SCOPE/stages/02-b.md"
sleep 1
run_sc=$("$ICM" init testns/scope-ws 2>/dev/null)
# 01-a is active (nothing closed); 02-b's Write gate must be out of scope.
out=$("$ICM" gate-check --tool Write 2>&1); rc=$?
if [ "$rc" -eq 0 ] && [ -z "$out" ]; then
    t_ok "41 gate scope: later-stage Write gate does not deny during earlier stage"
else
    t_fail "41 gate scope: later-stage Write gate does not deny during earlier stage" "rc=$rc out=$out"
fi
# Close 01-a -> 02-b active; precondition unmet (frame.md absent) -> gate fires.
"$ICM" stage-done testns/scope-ws --stage 01-a >/dev/null 2>&1
out=$("$ICM" gate-check --tool Write 2>&1); rc=$?
if [ "$rc" -eq 1 ] && printf '%s' "$out" | grep -q "DENY testns/scope-ws .* 02-b"; then
    t_ok "41b gate scope: gate fires once its owning stage is active"
else
    t_fail "41b gate scope: gate fires once its owning stage is active" "rc=$rc out=$out"
fi
# Satisfy the precondition -> the active-stage gate passes.
mkdir -p "$run_sc/01-a/output"; printf 'x\n' > "$run_sc/01-a/output/frame.md"
out=$("$ICM" gate-check --tool Write 2>&1); rc=$?
if [ "$rc" -eq 0 ]; then
    t_ok "41c gate scope: active-stage gate passes when precondition met"
else
    t_fail "41c gate scope: active-stage gate passes when precondition met" "rc=$rc out=$out"
fi
# Complete the run (close 02-b) and remove the precondition: a finished run has no
# active stage, so its gate denies nothing -- no cross-workspace/stale blocking.
rm -f "$run_sc/01-a/output/frame.md"
"$ICM" stage-done testns/scope-ws --stage 02-b >/dev/null 2>&1
out=$("$ICM" gate-check --tool Write 2>&1); rc=$?
if [ "$rc" -eq 0 ] && [ -z "$out" ]; then
    t_ok "41d gate scope: completed run has no active stage, denies nothing"
else
    t_fail "41d gate scope: completed run has no active stage, denies nothing" "rc=$rc out=$out"
fi

# ---- case 42: cross-harness tool-name normalization ----
# Anchored gate patterns so the match REQUIRES normalization (an unanchored core
# name would substring-match the wrapped name even without it).
WS_NORM="$TMP/skills/testns/norm-ws"
mkdir -p "$WS_NORM/stages"
printf '# 01-pub\n<!-- ICM-GATE tools="^notion-fetch$" run="false" -->\n' > "$WS_NORM/stages/01-pub.md"
sleep 1
run_nm=$("$ICM" init testns/norm-ws 2>/dev/null)
# Claude Code MCP wrapper name normalizes to notion-fetch -> matches -> "false" denies.
out=$("$ICM" gate-check --tool mcp__claude_ai_Notion__notion-fetch 2>&1); rc=$?
if [ "$rc" -eq 1 ] && printf '%s' "$out" | grep -q "DENY testns/norm-ws"; then
    t_ok "42 tool-name norm: canonical gate matches mcp__ wrapped name"
else
    t_fail "42 tool-name norm: canonical gate matches mcp__ wrapped name" "rc=$rc out=$out"
fi
# Built-in alias: gate names canonical web_search; harness reports WebSearch.
printf '# 01-pub\n<!-- ICM-GATE tools="^web_search$" run="false" -->\n' > "$WS_NORM/stages/01-pub.md"
sleep 1
run_nm2=$("$ICM" init testns/norm-ws 2>/dev/null)
out=$("$ICM" gate-check --tool WebSearch 2>&1); rc=$?
if [ "$rc" -eq 1 ] && printf '%s' "$out" | grep -q "DENY testns/norm-ws"; then
    t_ok "42b tool-name norm: canonical gate matches built-in alias (WebSearch)"
else
    t_fail "42b tool-name norm: canonical gate matches built-in alias (WebSearch)" "rc=$rc out=$out"
fi
# An unrelated tool still passes: normalization must not over-match.
out=$("$ICM" gate-check --tool mcp__claude_ai_Slack__slack_send 2>&1); rc=$?
if [ "$rc" -eq 0 ] && [ -z "$out" ]; then
    t_ok "42c tool-name norm: unrelated tool still allowed (no over-match)"
else
    t_fail "42c tool-name norm: unrelated tool still allowed" "rc=$rc out=$out"
fi

# ---- case 43: catalog lists skills with descriptions from SKILL.md frontmatter ----
mkdir -p "$TMP/skills/catns/cat-skill/stages"
cat > "$TMP/skills/catns/cat-skill/SKILL.md" <<'EOF'
---
name: cat-skill
description: >
  A test skill for the catalog command.
---
# cat-skill
EOF
cat_out=$("$ICM" catalog 2>&1)
if printf '%s' "$cat_out" | grep -q '| Skill | Description |' \
    && printf '%s' "$cat_out" | grep -q 'catns/cat-skill' \
    && printf '%s' "$cat_out" | grep -q 'A test skill for the catalog command'; then
    t_ok "43 catalog: lists skill slug + description from SKILL.md frontmatter"
else
    t_fail "43 catalog: lists skill slug + description from SKILL.md frontmatter" "out=$cat_out"
fi

# ---- case 44: new-skill scaffolds a usable skill skeleton ----
out=$("$ICM" new-skill testns/scaffolded --stages frame,draft,ship --desc "Scaffold test." 2>&1); rc=$?
nsd="$TMP/skills/testns/scaffolded"
if [ "$rc" -eq 0 ] && [ -f "$nsd/SKILL.md" ] \
    && grep -q '^name: scaffolded' "$nsd/SKILL.md" \
    && grep -q 'runtime README' "$nsd/SKILL.md" \
    && [ -f "$nsd/stages/01-frame.md" ] && [ -f "$nsd/stages/03-ship.md" ] \
    && grep -q 'stage-done testns/scaffolded --stage 01-frame' "$nsd/stages/01-frame.md" \
    && [ -d "$nsd/tools" ] && [ -d "$nsd/eval" ]; then
    t_ok "44 new-skill: scaffolds SKILL.md + stage stubs + tools/ + eval/"
else
    t_fail "44 new-skill: scaffolds skeleton" "rc=$rc out=$out tree=$(find "$nsd" -type f 2>/dev/null)"
fi
# The scaffolded skill is immediately runnable by the runtime.
sc_stages=$("$ICM" stages testns/scaffolded 2>/dev/null)
sc_run=$("$ICM" init testns/scaffolded 2>/dev/null)
if printf '%s' "$sc_stages" | grep -q '01-frame' && [ -d "$sc_run/01-frame" ]; then
    t_ok "44b new-skill: scaffolded skill initializes and lists its stages"
else
    t_fail "44b new-skill: scaffolded skill initializes" "stages=$sc_stages run=$sc_run"
fi
# Refuses to clobber an existing skill.
out=$("$ICM" new-skill testns/scaffolded --stages x 2>&1); rc=$?
if [ "$rc" -ne 0 ] && printf '%s' "$out" | grep -q "already exists"; then
    t_ok "44c new-skill: refuses to overwrite an existing skill dir"
else
    t_fail "44c new-skill: refuses to overwrite" "rc=$rc out=$out"
fi

# ---- case 45: hook captures tool args to a dedicated tool-args.jsonl ----
if command -v jq >/dev/null 2>&1; then
    rm -f "$PROJECT/.icm/telemetry/tool-args.jsonl"
    printf '{"session_id":"t","transcript_path":"/tmp/t.jsonl","cwd":"%s","hook_event_name":"PreToolUse","tool_name":"mcp__test__send","tool_input":{"channel":"C1","text":"hi"}}' "$PROJECT" \
        | (cd "$TMP" && "$HOOK") >/dev/null 2>&1 || true
    ta="$PROJECT/.icm/telemetry/tool-args.jsonl"
    if [ -f "$ta" ] && tail -1 "$ta" | jq -e '.tool == "mcp__test__send" and .input.channel == "C1" and .input.text == "hi"' >/dev/null 2>&1; then
        t_ok "45 hook: captures tool args (tool + input) to tool-args.jsonl"
    else
        t_fail "45 hook: captures tool args to tool-args.jsonl" "line=$(tail -1 "$ta" 2>/dev/null)"
    fi
    # The args file must NOT pollute tool-calls.jsonl tool-name attribution.
    if [ ! -s "$PROJECT/.icm/telemetry/tool-args.jsonl" ] || ! grep -q '"--tool"' "$ta" 2>/dev/null; then
        t_ok "45b hook: args live in a separate file (no --tool tokens to mis-attribute)"
    else
        t_fail "45b hook: args separated from attribution" "ta=$(cat "$ta" 2>/dev/null)"
    fi
    rm -f "$PROJECT/.icm/telemetry/tool-args.jsonl"
else
    echo "SKIP  45 hook tool-args capture (jq not installed)"
fi

# ---- case 46: ICM-CALL execution-spec verification (arg-field presence) ----
if command -v jq >/dev/null 2>&1; then
    RUN_EC=".icm/testns/exec-ws/2032-01-01_00-00-00"
    mkdir -p "$RUN_EC/01-pub/output" "$RUN_EC/telemetry" "$RUN_EC/../../../telemetry"
    printf '# 01-pub\n<!-- ICM-CALL tool="notion-create-pages" args="parent,content" -->\n' > "$RUN_EC/01-pub/CONTEXT.md"
    printf 'x\n' > "$RUN_EC/01-pub/output/o.md"
    printf '{"ts":"2032-01-01T00:00:10Z","type":"stage_done","stage":"01-pub","model":"m","tokens_in":null,"cache_creation":null,"cache_read":null,"tokens_out":null,"counts":"estimated","transcript_source":"none"}\n' > "$RUN_EC/telemetry/events.jsonl"
    TA_EC=".icm/telemetry/tool-args.jsonl"
    # In-window call via the mcp wrapper name, both required fields present -> OK.
    printf '{"ts":"2032-01-01T00:00:05Z","tool":"mcp__claude_ai_Notion__notion-create-pages","input":{"parent":"p","content":"hi"}}\n' >> "$TA_EC"
    audit_ec=$("$ICM" audit testns/exec-ws 2>&1)
    if printf '%s' "$audit_ec" | grep -q "EXECUTION SPEC" && printf '%s' "$audit_ec" | grep -q "✓ notion-create-pages"; then
        t_ok "46 ICM-CALL: spec'd tool with required arg fields present -> verified"
    else
        t_fail "46 ICM-CALL: spec'd tool with required arg fields -> verified" "out=$audit_ec"
    fi
    # Same call missing a required field -> deviation.
    { grep -v '2032-01-01T00:00:05Z' "$TA_EC" || true; } > "$TA_EC.tmp"; mv "$TA_EC.tmp" "$TA_EC"
    printf '{"ts":"2032-01-01T00:00:05Z","tool":"mcp__claude_ai_Notion__notion-create-pages","input":{"parent":"p"}}\n' >> "$TA_EC"
    audit_ec=$("$ICM" audit testns/exec-ws 2>&1)
    if printf '%s' "$audit_ec" | grep -q "missing:content" && printf '%s' "$audit_ec" | grep -q "Deviations: 1"; then
        t_ok "46b ICM-CALL: called but missing a required arg field -> deviation"
    else
        t_fail "46b ICM-CALL: missing required arg field -> deviation" "out=$audit_ec"
    fi
    { grep -v '2032-01-01T00:00:05Z' "$TA_EC" || true; } > "$TA_EC.tmp"; mv "$TA_EC.tmp" "$TA_EC"
else
    echo "SKIP  46 ICM-CALL verification (jq not installed)"
fi

# ---- case 48: ICM-CALL value-from-file mapping (field@path) ----
if command -v jq >/dev/null 2>&1; then
    RUN_EV=".icm/testns/exec2-ws/2033-01-01_00-00-00"
    mkdir -p "$RUN_EV/01-pub/output" "$RUN_EV/telemetry" "$RUN_EV/../../../telemetry"
    printf '# 01-pub\n<!-- ICM-CALL tool="pubtool" args="title,body@01-pub/output/page.md" -->\n' > "$RUN_EV/01-pub/CONTEXT.md"
    printf 'rendered body line\n' > "$RUN_EV/01-pub/output/page.md"
    printf 'x\n' > "$RUN_EV/01-pub/output/o.md"
    printf '{"ts":"2033-01-01T00:00:10Z","type":"stage_done","stage":"01-pub","model":"m","tokens_in":null,"cache_creation":null,"cache_read":null,"tokens_out":null,"counts":"estimated","transcript_source":"none"}\n' > "$RUN_EV/telemetry/events.jsonl"
    TA_EV=".icm/telemetry/tool-args.jsonl"
    printf '{"ts":"2033-01-01T00:00:05Z","tool":"pubtool","input":{"title":"T","body":"rendered body line"}}\n' >> "$TA_EV"
    a=$("$ICM" audit testns/exec2-ws 2>&1)
    if printf '%s' "$a" | grep -q "✓ pubtool"; then
        t_ok "48 ICM-CALL: field@path with arg value == file content -> verified"
    else
        t_fail "48 ICM-CALL: value-from-file verified" "out=$a"
    fi
    { grep -v '2033-01-01T00:00:05Z' "$TA_EV" || true; } > "$TA_EV.tmp"; mv "$TA_EV.tmp" "$TA_EV"
    printf '{"ts":"2033-01-01T00:00:05Z","tool":"pubtool","input":{"title":"T","body":"WRONG"}}\n' >> "$TA_EV"
    a=$("$ICM" audit testns/exec2-ws 2>&1)
    if printf '%s' "$a" | grep -q "value:body" && printf '%s' "$a" | grep -q "Deviations: 1"; then
        t_ok "48b ICM-CALL: field@path with mismatched value -> deviation"
    else
        t_fail "48b ICM-CALL: value mismatch -> deviation" "out=$a"
    fi
    { grep -v '2033-01-01T00:00:05Z' "$TA_EV" || true; } > "$TA_EV.tmp"; mv "$TA_EV.tmp" "$TA_EV"
else
    echo "SKIP  48 ICM-CALL value-from-file (jq not installed)"
fi

# ---- case 47: eval runs a skill's eval/*.test.sh and aggregates pass/fail ----
mkdir -p "$TMP/skills/evalns/eval-skill/eval" "$TMP/skills/evalns/eval-skill/stages"
printf '# 01\n' > "$TMP/skills/evalns/eval-skill/stages/01-x.md"
printf '#!/bin/sh\nexit 0\n' > "$TMP/skills/evalns/eval-skill/eval/pass.test.sh"
printf '#!/bin/sh\necho boom; exit 1\n' > "$TMP/skills/evalns/eval-skill/eval/fail.test.sh"
ev_out=$("$ICM" eval evalns/eval-skill 2>&1); ev_rc=$?
if [ "$ev_rc" -ne 0 ] \
    && printf '%s' "$ev_out" | grep -q 'PASS pass.test.sh' \
    && printf '%s' "$ev_out" | grep -q 'FAIL fail.test.sh' \
    && printf '%s' "$ev_out" | grep -q '1 passed, 1 failed'; then
    t_ok "47 eval: runs eval/*.test.sh, aggregates pass/fail, exits nonzero on failure"
else
    t_fail "47 eval: runs eval suite" "rc=$ev_rc out=$ev_out"
fi
rm "$TMP/skills/evalns/eval-skill/eval/fail.test.sh"
ev_out=$("$ICM" eval evalns/eval-skill 2>&1); ev_rc=$?
if [ "$ev_rc" -eq 0 ] && printf '%s' "$ev_out" | grep -q '1 passed, 0 failed'; then
    t_ok "47b eval: all tests pass -> exit 0"
else
    t_fail "47b eval: all pass -> exit 0" "rc=$ev_rc out=$ev_out"
fi

# ---- case 49: caller-scoping - a parent's open gate does not deny a child's tool ----
# A parent run that invokes a child run waits while the child works; the parent's
# still-open gate must not deny the child's legitimate tool call. Gate evaluation
# is suspended for a parent with an open child; tamper checks are not.
mkdir -p "$TMP/skills/testns/xt-parent/stages" "$TMP/skills/testns/xt-child/stages"
printf '# 01-work\nwork\n' > "$TMP/skills/testns/xt-parent/stages/01-work.md"
printf '# 02-pub\n<!-- ICM-GATE tools="mcp__x__publish" run="test -f output/evidence.md" -->\n' > "$TMP/skills/testns/xt-parent/stages/02-pub.md"
printf '# 01-pub\n<!-- ICM-GATE tools="mcp__x__publish" run="true" -->\n' > "$TMP/skills/testns/xt-child/stages/01-pub.md"
sleep 1
xt_p=$("$ICM" init testns/xt-parent 2>/dev/null); xt_pts=$(basename "$xt_p")
"$ICM" stage-done testns/xt-parent --stage 01-work >/dev/null 2>&1  # parent active on 02-pub; gate fails (no evidence)

# Baseline: with no child open, the parent's active gate denies the publish tool.
out=$("$ICM" gate-check --tool mcp__x__publish 2>&1); rc=$?
if [ "$rc" -eq 1 ] && printf '%s' "$out" | grep -q "DENY testns/xt-parent"; then
    t_ok "49-pre parent's active gate denies publish (no child yet)"
else
    t_fail "49-pre parent's active gate denies publish" "rc=$rc out=$out"
fi

# Child invoked by the parent (open; its own gate passes). The parent's gate is
# now suspended, so the child's publish call is allowed. FAILS on pre-fix code.
xt_c=$("$ICM" init testns/xt-child --caller "testns/xt-parent/$xt_pts/02-pub" 2>/dev/null)
out=$("$ICM" gate-check --tool mcp__x__publish 2>&1); rc=$?
if [ "$rc" -eq 0 ] && [ -z "$out" ]; then
    t_ok "49 caller-scope: parent gate suspended while child open; child's publish allowed"
else
    t_fail "49 caller-scope: parent gate should be suspended while child open" "rc=$rc out=$out"
fi

# gate-status (diagnostic) must agree with enforcement: a suspended parent must
# not appear in the denies. Checks the parent specifically, so unrelated blocking
# runs elsewhere in the shared suite do not affect this assertion.
st=$("$ICM" gate-status 2>&1) || true
if printf '%s' "$st" | grep -q "DENY testns/xt-parent"; then
    t_fail "49d gate-status: suspended parent must not appear in denies" "$st"
else
    t_ok "49d gate-status: agrees with enforcement (suspended parent absent from denies)"
fi

# Safety: a suspended parent is still tamper-checked. Corrupt a manifested file
# (a real sha256 mismatch), assert DENY, then restore so 49c is clean.
cp "$xt_p/02-pub/CONTEXT.md" "$TMP/xt_ctx_bak"
printf 'tamper\n' >> "$xt_p/02-pub/CONTEXT.md"
out=$("$ICM" gate-check --tool mcp__x__publish 2>&1); rc=$?
if [ "$rc" -eq 1 ] && printf '%s' "$out" | grep -q "DENY testns/xt-parent.*tampered"; then
    t_ok "49b caller-scope: suspended parent is still tamper-checked (fail-closed)"
else
    t_fail "49b caller-scope: suspended parent still tamper-checked" "rc=$rc out=$out"
fi
cp "$TMP/xt_ctx_bak" "$xt_p/02-pub/CONTEXT.md"

# Resume: once the child run closes, the parent's gate enforces again.
"$ICM" stage-done testns/xt-child --stage 01-pub >/dev/null 2>&1
out=$("$ICM" gate-check --tool mcp__x__publish 2>&1); rc=$?
if [ "$rc" -eq 1 ] && printf '%s' "$out" | grep -q "DENY testns/xt-parent"; then
    t_ok "49c caller-scope: parent gate resumes once the child run closes"
else
    t_fail "49c caller-scope: parent gate resumes after child closes" "rc=$rc out=$out"
fi

# ---- case 50: same-second init collision guard ----
# Two runs of one workspace created in the same second (a parent invoking a child,
# or rapid re-init) must get distinct dirs; the second is suffixed, and the
# suffixed run is still the latest that latest_runs / gate-check see.
mkdir -p "$TMP/skills/testns/collide-ws/stages"
printf '# 01-x\n<!-- ICM-GATE tools="zonk" run="false" -->\n' > "$TMP/skills/testns/collide-ws/stages/01-x.md"
# Pin the run-id `date` to a fixed second so the collision is deterministic (not
# dependent on whether two real inits straddle a second boundary). The ISO
# timestamp (created/events) still delegates to the real date.
mkdir -p "$TMP/fakebin"
cat > "$TMP/fakebin/date" <<'FAKEDATE'
#!/bin/sh
case "$*" in
  *%Y-%m-%d_%H-%M-%S*) echo "2099-01-01_00-00-00" ;;
  *) exec /bin/date "$@" ;;
esac
FAKEDATE
chmod +x "$TMP/fakebin/date"
co_r1=$(PATH="$TMP/fakebin:$PATH" "$ICM" init testns/collide-ws 2>/dev/null)
co_r2=$(PATH="$TMP/fakebin:$PATH" "$ICM" init testns/collide-ws 2>/dev/null)
if [ "$co_r1" != "$co_r2" ] && [ -d "$co_r1" ] && [ -d "$co_r2" ]; then
    t_ok "50 collision guard: same-second inits get distinct run dirs"
else
    t_fail "50 collision guard: same-second inits distinct dirs" "r1=$co_r1 r2=$co_r2"
fi
# The second run carries the numeric suffix (proves the guard fired, not a tick).
case "$(basename "$co_r2")" in
    *.[0-9]*) t_ok "50b collision guard: second run is suffixed (.<n>)" ;;
    *)        t_fail "50b collision guard: second run suffixed" "r2=$co_r2" ;;
esac
# latest_runs tolerates the suffix: gate-check sees the suffixed (latest) run, and
# its failing gate denies, naming the suffixed run id.
co_ts2=$(basename "$co_r2")
out=$("$ICM" gate-check --tool zonk 2>&1); rc=$?
if [ "$rc" -eq 1 ] && printf '%s' "$out" | grep -q "DENY testns/collide-ws $co_ts2"; then
    t_ok "50c collision guard: suffixed run discoverable by latest_runs/gate-check"
else
    t_fail "50c collision guard: suffixed run discoverable" "rc=$rc out=$out ts2=$co_ts2"
fi

echo ""
echo "$PASS passed, $FAIL failed"
[ "$FAIL" -eq 0 ]
