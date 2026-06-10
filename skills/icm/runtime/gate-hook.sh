#!/bin/sh
# Claude Code PreToolUse hook: denies gated MCP tool calls while an ICM run's gate
# checker fails. Registered with matcher "mcp__.*" (installer.sh --hooks). Reads the
# harness JSON on stdin, delegates to icm.sh gate-check, emits a permissionDecision
# deny JSON when the gate denies. Read-only: never writes to the run dir.
# Fails closed: missing jq or missing stdin fields deny rather than silently allow.
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

command -v jq >/dev/null 2>&1 || deny "icm gate-hook: jq missing - gates cannot be evaluated. Install jq or unregister this hook."

tool_name=$(printf '%s' "$input" | jq -r '.tool_name // empty' 2>/dev/null || :)
cwd=$(printf '%s' "$input" | jq -r '.cwd // empty' 2>/dev/null || :)

[ -n "$tool_name" ] || deny "icm gate-hook: no tool_name in hook input (protocol mismatch) - failing closed."
[ -n "$cwd" ] || deny "icm gate-hook: no cwd in hook input (protocol mismatch) - failing closed."
[ -d "$cwd" ] || exit 0
cd "$cwd"
[ -d .icm ] || exit 0

if out=$("$SCRIPT_DIR/icm.sh" gate-check --tool "$tool_name" 2>&1); then
    exit 0
fi
deny "$(printf '%s\n' "$out" | head -10)"
