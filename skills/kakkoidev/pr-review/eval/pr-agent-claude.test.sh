#!/bin/sh
# Eval: tools/pr-agent-claude.py - the handler that serves pr-agent's LLM calls via
# `claude -p`. Imports the real pinned pr-agent (needs its interpreter: PR_AGENT_PYTHON, else
# the one in the installed pr-agent's shebang) and drives the handler against a stub
# `claude`: the prompt reaches claude intact, claude runs with no tools/settings/MCP, and
# claude's JSON maps to (response, finish_reason) or an error pr-agent records as a failure.
# Prints SKIP and exits 0 when pr-agent is not installed. Runs from the skill dir.
set -eu
SKILL=$(cd "$(dirname "$0")/.." && pwd)
py=${PR_AGENT_PYTHON:-}
if [ -z "$py" ] && command -v pr-agent > /dev/null 2>&1; then py=$(head -1 "$(command -v pr-agent)" | sed 's/^#!//'); fi
if [ -z "$py" ] || ! "$py" -c 'import pr_agent' > /dev/null 2>&1; then echo "SKIP: pr-agent not installed"; exit 0; fi

T=$(mktemp -d)
trap 'rm -f "$T"/bin/claude "$T"/*.log "$T"/reply; rmdir "$T"/bin "$T" 2>/dev/null || true' EXIT
mkdir "$T/bin"
cat > "$T/bin/claude" <<'EOF'
#!/bin/sh
printf '%s\n' "$@" > "$STUB_ARGV"
cat > "$STUB_STDIN"
while [ $# -gt 0 ]; do [ "$1" = --system-prompt-file ] && cp "$2" "$STUB_SYSTEM"; shift; done
cat "$STUB_REPLY"
exit "${STUB_RC:-0}"
EOF
chmod +x "$T/bin/claude"
export PATH="$T/bin:$PATH" STUB_ARGV="$T/argv.log" STUB_STDIN="$T/stdin.log" STUB_SYSTEM="$T/system.log" STUB_REPLY="$T/reply"

call() {
    PYTHONPATH="$SKILL/tools" "$py" -c '
import asyncio, importlib
h = importlib.import_module("pr-agent-claude").ClaudeCLIHandler()
try:
    print(repr(asyncio.run(h.chat_completion(model="m", system="SYS-PROMPT", user="USER-PROMPT"))))
except RuntimeError as e:
    print("RAISED", e)
' 2>/dev/null | tail -1
}

# A: success -> (result, "stop"); prompt delivered; claude locked down.
printf '{"type":"result","subtype":"success","is_error":false,"result":"review: ok","stop_reason":"end_turn"}' > "$T/reply"
got=$(call)
[ "$got" = "('review: ok', 'stop')" ] || { echo "FAIL A: got $got"; exit 1; }
[ "$(cat "$T/stdin.log")" = USER-PROMPT ] || { echo "FAIL A: user prompt must reach claude on stdin"; exit 1; }
grep -q 'SYS-PROMPT' "$T/system.log" || { echo "FAIL A: system prompt must reach claude via --system-prompt-file"; exit 1; }
args=$(tr '\n' ' ' < "$T/argv.log")
for want in "-p " "--model claude-opus-5-5 " "--tools  " "--setting-sources  " "--strict-mcp-config " "--no-session-persistence " "--output-format json "; do
  case "$args" in *"$want"*) ;; *) echo "FAIL A: claude argv missing '$want': $args"; exit 1 ;; esac
done
case "$args" in *--dangerously*|*--bare*) echo "FAIL A: claude argv must not bypass permissions or switch to API-key auth: $args"; exit 1 ;; esac

# B: truncated -> finish_reason "length" (pr-agent then refuses the partial review).
printf '{"type":"result","subtype":"success","is_error":false,"result":"part","stop_reason":"max_tokens"}' > "$T/reply"
got=$(call)
[ "$got" = "('part', 'length')" ] || { echo "FAIL B: got $got"; exit 1; }

# C: claude error -> raise (pr-agent records a failed review, the tool reports FAILED).
printf '{"type":"result","subtype":"error_during_execution","is_error":true,"result":"limit reached"}' > "$T/reply"
got=$(STUB_RC=1 call)
case "$got" in RAISED*) ;; *) echo "FAIL C: an error reply must raise, got $got"; exit 1 ;; esac
printf 'not json' > "$T/reply"
got=$(call)
case "$got" in RAISED*) ;; *) echo "FAIL C: non-JSON output must raise, got $got"; exit 1 ;; esac

echo ok
