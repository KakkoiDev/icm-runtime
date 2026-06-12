#!/bin/sh
# Claude Code PreToolUse hook: denies gated tool calls while an ICM run's gate
# checker fails. Registered with matcher ".*" (installer.sh --hooks) so built-in
# tools (WebSearch, WebFetch, Bash, ...) are gated and logged, not just mcp__*.
# Reads the harness JSON on stdin, delegates to icm.sh gate-check, emits a
# permissionDecision deny JSON when the gate denies. Never writes to run dirs;
# records the harness transcript_path into .icm/telemetry/ so stage-done
# snapshots the right session.
# Fails closed within ICM projects: missing jq or missing stdin fields deny.
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

# One jq fork for all fields: this path runs on every tool call.
vals=$(printf '%s' "$input" | jq -r '[.tool_name // "", .cwd // "", .transcript_path // ""] | @tsv' 2>/dev/null || :)
IFS='	' read -r tool_name cwd tp <<EOF
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

if out=$("$SCRIPT_DIR/icm.sh" gate-check --tool "$tool_name" 2>&1); then
    exit 0
fi
deny "$(printf '%s\n' "$out" | head -10)"
