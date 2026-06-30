#!/bin/sh
# Claude Code PreToolUse hook: denies gated tool calls while an ICM run's gate
# checker fails. Registered with matcher ".*" (installer.sh --hooks) so built-in
# tools (WebSearch, WebFetch, Bash, ...) are gated and logged, not just mcp__*.
# Reads the harness JSON on stdin, delegates to icm.sh gate-check, emits a
# permissionDecision deny JSON when the gate denies. Never writes to run dirs;
# records the harness transcript_path into .icm/telemetry/ so stage-done
# snapshots the right session.
# Fails closed within ICM projects: missing jq or missing stdin fields deny.
# A genuine gate DENY fails closed; a broken checker (icm.sh crash / parse error)
# fails OPEN with a warning + telemetry breadcrumb, so one bug behind the ".*"
# matcher cannot brick every tool call and trap the session.
# Outside .icm dirs it always allows -- the wide matcher must not tax other work.
set -eu
SCRIPT_DIR=$(cd "$(dirname "$0")" && pwd -P)

deny() {
    if command -v jq >/dev/null 2>&1; then
        reason=$(printf '%s' "$1" | jq -Rs .)
    else
        reason="\"$(printf '%s' "$1" | tr -d '"\\' | tr '\n' ' ')\""
    fi
    printf '{"hookSpecificOutput":{"hookEventName":"PreToolUse","permissionDecision":"deny","permissionDecisionReason":%s}}\n' "$reason"
    exit 0
}

input=$(cat)

# Wide matcher: failing closed on missing jq would brick every tool call in
# every directory. Restrict that deny to actual ICM projects (crude sed
# extraction of cwd is enough for this test); allow everywhere else.
if ! command -v jq >/dev/null 2>&1; then
    cwd=$(printf '%s' "$input" | sed -n 's/.*"cwd":"\([^"]*\)".*/\1/p')
    if [ -n "$cwd" ] && [ -d "$cwd/.icm" ]; then
        deny "icm gate-hook: jq missing - gates cannot be evaluated. Install jq or unregister this hook."
    fi
    exit 0
fi

# One jq fork for all fields: this path runs on every tool call. tool_path is the
# target of a file-writing tool (Write/Edit/NotebookEdit); empty for path-less
# tools. gate-check uses it to scope a run's write-gate to that run's own tree.
vals=$(printf '%s' "$input" | jq -r '[.tool_name // "", .cwd // "", .transcript_path // "", (.tool_input.file_path // .tool_input.path // .tool_input.notebook_path // "")] | @tsv' 2>/dev/null || :)
IFS='	' read -r tool_name cwd tp tool_path <<EOF
$vals
EOF

[ -n "$tool_name" ] || deny "icm gate-hook: no tool_name in hook input (protocol mismatch) - failing closed."
[ -n "$cwd" ] || deny "icm gate-hook: no cwd in hook input (protocol mismatch) - failing closed."
[ -d "$cwd" ] || exit 0
cd "$cwd"
[ -d .icm ] || exit 0

# Record the authoritative session transcript path for stage-done snapshots.
# Best-effort: never let it interfere with gate evaluation.
if [ -n "$tp" ] && [ -d .icm/telemetry ]; then
    printf '%s\n' "$tp" > .icm/telemetry/transcript-path 2>/dev/null || :
fi

# Capture the tool call's arguments for execution-spec verification (audit reads
# them to check an ICM-CALL spec). Written to a DEDICATED file, not
# tool-calls.jsonl, so arbitrary arg content (e.g. a Bash command containing
# "--tool") cannot pollute that file's tool-name attribution parsing. One jq fork,
# best-effort: a malformed/oversized payload just drops the record, never blocks.
if [ -d .icm/telemetry ]; then
    ta_ts=$(date -u +%Y-%m-%dT%H:%M:%SZ 2>/dev/null || echo "")
    printf '%s' "$input" | jq -c --arg ts "$ta_ts" --arg tool "$tool_name" \
        '{ts:$ts,tool:$tool,input:(.tool_input // {})}' \
        >> .icm/telemetry/tool-args.jsonl 2>/dev/null || :
fi

# Distinguish a genuine gate DENY from a checker that failed to RUN.
# gate-check signals a real denial with rc=1 AND DENY-prefixed stdout. Any other
# failure (parse error in icm.sh, missing dependency, crash) must NOT brick the
# session: behind the ".*" matcher it would deny every tool call, and the agent
# cannot even Edit/Read to self-repair (a single bad line traps the whole run).
# So: genuine denials fail closed; a broken checker fails OPEN, but loudly --
# stderr warning + a telemetry breadcrumb so the breakage is visible, not silent.
gc_rc=0
out=$("$SCRIPT_DIR/icm.sh" gate-check --tool "$tool_name" --path "$tool_path" 2>&1) || gc_rc=$?
if [ "$gc_rc" -eq 0 ]; then
    exit 0
fi
if printf '%s\n' "$out" | grep -q '^DENY '; then
    deny "$(printf '%s\n' "$out" | head -10)"
fi
# Checker is broken, not denying. Allow the tool but surface the failure.
printf 'icm gate-hook: gate-check could not run (rc=%s); gates NOT enforced this call. Fix icm.sh.\n%s\n' \
    "$gc_rc" "$(printf '%s' "$out" | head -3)" >&2
if [ -d .icm/telemetry ]; then
    # jq is known-present here (the jq-missing branch exited earlier). Build the
    # line with jq so control chars / quotes in checker output cannot produce an
    # invalid JSONL line.
    gc_ts=$(date -u +%Y-%m-%dT%H:%M:%SZ 2>/dev/null || echo "")
    gc_msg=$(printf '%s' "$out" | head -1)
    jq -cn --arg ts "$gc_ts" --arg tool "$tool_name" --argjson rc "$gc_rc" --arg msg "$gc_msg" \
        '{ts:$ts,event:"gate-check-error",tool:$tool,rc:$rc,msg:$msg}' \
        >> .icm/telemetry/hook-errors.jsonl 2>/dev/null || :
fi
exit 0
