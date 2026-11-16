#!/bin/sh
# Deterministic eval: stage 07-pr-agent and tools/run-pr-agent against stubs.
# pr-agent (The-PR-Agent/pr-agent, pinned) is a second, independent reviewer. Its LLM calls
# run through `claude -p` (tools/pr-agent-claude.py injects that handler into pr-agent's own
# CLI); pr-agent itself never gets a GitHub token and only reviews the sealed diff. The tool
# then publishes the result as ONE PR comment, identifiable as pr-agent output, only when
# called with --publish, and only when the review actually ran. Runs from the skill dir.
set -eu
SKILL=$(cd "$(dirname "$0")/.." && pwd)
T=$(mktemp -d)
trap 'rm -f "$T"/bin/* "$T"/out/* "$T"/*.log "$T"/pr.diff "$T"/body; rmdir "$T"/bin "$T"/out "$T" 2>/dev/null || true' EXIT
mkdir "$T/bin" "$T/out"

# Stub pr-agent: only answers --version (the real 0.50.0 logs warnings to stdout first).
cat > "$T/bin/pr-agent" <<'EOF'
#!/bin/sh
[ "${1:-}" = --version ] || { echo "stub: pr-agent must only be asked its version" >&2; exit 9; }
echo "2026-11-16 | WARNING | Settings file not found: .secrets.toml. Skipping it."
echo "pr-agent $STUB_VERSION"
EOF
# Stub python (PR_AGENT_PYTHON): logs argv + env, then behaves like pr-agent's CLI:
# writes --output / --json-output; on STUB_FAIL writes the real failure text, exits 1 only
# when config.propagate_tool_errors is true (real 0.50.0 behavior).
cat > "$T/bin/py" <<'EOF'
#!/bin/sh
echo "$*" >> "$STUB_LOG"
env | sort > "$STUB_ENV"
out=""; json=""
while [ $# -gt 0 ]; do
  case "$1" in --output) out=$2; shift ;; --json-output) json=$2; shift ;; esac
  shift
done
if [ "${STUB_FAIL:-0}" = 1 ]; then
  printf 'Failed to review PR' > "$out"
  [ "${CONFIG__PROPAGATE_TOOL_ERRORS:-}" = true ] && exit 1
  exit 0
fi
printf '## PR Reviewer Guide\nstub finding in a.ts\n' > "$out"
printf '{"review":{"key_issues_to_review":[]}}\n' > "$json"
EOF
# Stub gh: records the comment call and its body, prints a comment URL.
cat > "$T/bin/gh" <<'EOF'
#!/bin/sh
echo "$*" >> "$STUB_GH"
while [ $# -gt 0 ]; do [ "$1" = --body-file ] && cp "$2" "$STUB_BODY"; shift; done
echo "https://github.com/o/r/pull/7#issuecomment-123"
EOF
printf '#!/bin/sh\nexit 0\n' > "$T/bin/claude"
chmod +x "$T"/bin/*
printf 'diff --git a/a.ts b/a.ts\n--- a/a.ts\n+++ b/a.ts\n@@ -1 +1 @@\n-x\n+y\n' > "$T/pr.diff"
export PATH="$T/bin:$PATH" PR_AGENT_PYTHON="$T/bin/py" STUB_LOG="$T/call.log" STUB_ENV="$T/env.log" \
  STUB_GH="$T/gh.log" STUB_BODY="$T/body" STUB_VERSION=0.50.0
TOOL="$SKILL/tools/run-pr-agent"
reset() { rm -f "$T"/out/* "$STUB_BODY"; : > "$STUB_LOG"; : > "$STUB_GH"; }

# --- Structure: stage 07 is wired, gated on 06, publishes, and owns the seal. -----------
f=stages/07-pr-agent.md
test -s "$f" || { echo "FAIL: $f missing"; exit 1; }
grep -q 'ICM-GATE .*run="test -s ../06-report/output/report-receipt.md"' "$f" || { echo "FAIL: 07 gate must require 06 report-receipt.md"; exit 1; }
grep -qE 'tools/run-pr-agent .* --publish' "$f" || { echo "FAIL: 07 must invoke tools/run-pr-agent with --publish"; exit 1; }
grep -q 'stage-done kakkoidev/pr-review --stage 07-pr-agent' "$f" || { echo "FAIL: 07 missing its stage-done marker"; exit 1; }
grep -q 'icm.sh seal kakkoidev/pr-review' "$f" || { echo "FAIL: 07 (the last stage) must seal the run"; exit 1; }
if grep -q 'icm.sh seal' stages/06-report.md; then echo "FAIL: 06 must not seal - seal refuses while 07 has no stage-done"; exit 1; fi
test -x "$TOOL" || { echo "FAIL: $TOOL missing or not executable"; exit 1; }
test -s "$SKILL/tools/pr-agent-claude.py" || { echo "FAIL: tools/pr-agent-claude.py missing"; exit 1; }

# --- A: no claude CLI -> BLOCKED, nothing run, nothing posted. ---------------------------
reset; mv "$T/bin/claude" "$T/claude.off"
PATH="$T/bin:/usr/bin:/bin" sh "$TOOL" "$T/pr.diff" "$T/out" o/r 7 --publish > "$T/a.log" 2>&1 || { echo "FAIL A: missing claude must not fail the stage"; cat "$T/a.log"; exit 1; }
mv "$T/claude.off" "$T/bin/claude"
grep -q '^STATUS: BLOCKED' "$T/out/PR-AGENT-7.md" || { echo "FAIL A: must say STATUS: BLOCKED"; exit 1; }
test ! -s "$STUB_LOG" || { echo "FAIL A: pr-agent must not run without claude"; exit 1; }
test ! -s "$STUB_GH" || { echo "FAIL A: nothing may be posted when blocked"; exit 1; }

# --- B: version drift -> refuse. ---------------------------------------------------------
reset
if STUB_VERSION=0.49.0 sh "$TOOL" "$T/pr.diff" "$T/out" o/r 7 > "$T/b.log" 2>&1; then
  echo "FAIL B: a pr-agent version other than the pin must be refused"; exit 1
fi
grep -q '0.50.0' "$T/b.log" || { echo "FAIL B: refusal must name the pinned version"; cat "$T/b.log"; exit 1; }

# --- C: without --publish: local only. pr-agent reviews the sealed diff with no token. ---
reset
CONFIG__PUBLISH_OUTPUT=true GH_TOKEN=t1 GITHUB_TOKEN=t2 GITHUB__USER_TOKEN=t3 \
  sh "$TOOL" "$T/pr.diff" "$T/out" o/r 7 > "$T/c.log" 2>&1 || { echo "FAIL C: run failed"; cat "$T/c.log"; exit 1; }
argv=$(cat "$STUB_LOG")
case "$argv" in "$SKILL/tools/pr-agent-claude.py "*) ;; *) echo "FAIL C: must run pr-agent through tools/pr-agent-claude.py: $argv"; exit 1 ;; esac
case "$argv" in *--pr_url*|*--pr-url*) echo "FAIL C: pr-agent must never get a PR url: $argv"; exit 1 ;; esac
case "$argv" in *"--diff-file $T/pr.diff"*" review") ;; *) echo "FAIL C: must review the sealed diff via --diff-file: $argv"; exit 1 ;; esac
grep -qx 'CONFIG__GIT_PROVIDER=plain-diff' "$STUB_ENV" || { echo "FAIL C: child env must force plain-diff"; exit 1; }
grep -qx 'CONFIG__PUBLISH_OUTPUT=false' "$STUB_ENV" || { echo "FAIL C: pr-agent's own publishing must stay off"; exit 1; }
if grep -qE '^(GH_TOKEN|GITHUB_TOKEN|GITHUB__USER_TOKEN|GH_ENTERPRISE_TOKEN|GITHUB_ENTERPRISE_TOKEN)=' "$STUB_ENV"; then
  echo "FAIL C: a GitHub token reached pr-agent"; exit 1
fi
test ! -s "$STUB_GH" || { echo "FAIL C: nothing may be posted without --publish"; cat "$STUB_GH"; exit 1; }
r="$T/out/PR-AGENT-7.md"
grep -q '^STATUS: RAN' "$r" || { echo "FAIL C: must say STATUS: RAN"; exit 1; }
grep -q '^Published: no' "$r" || { echo "FAIL C: must record Published: no"; exit 1; }
grep -q 'stub finding in a.ts' "$r" || { echo "FAIL C: report must carry pr-agent's output verbatim"; exit 1; }
test -s "$T/out/pr-agent-review.json" || { echo "FAIL C: structured json output missing"; exit 1; }

# --- D: --publish posts ONE comment identifiable as pr-agent output, URL recorded. -------
reset
sh "$TOOL" "$T/pr.diff" "$T/out" o/r 7 --publish > "$T/d.log" 2>&1 || { echo "FAIL D: publish run failed"; cat "$T/d.log"; exit 1; }
test "$(wc -l < "$STUB_GH" | tr -d ' ')" = 1 || { echo "FAIL D: expected exactly one gh call"; cat "$STUB_GH"; exit 1; }
grep -q '^pr comment 7 --repo o/r --body-file ' "$STUB_GH" || { echo "FAIL D: must post one PR comment on o/r#7"; cat "$STUB_GH"; exit 1; }
head -1 "$STUB_BODY" | grep -qx '<!-- pr-agent-review -->' || { echo "FAIL D: body must open with the <!-- pr-agent-review --> marker"; exit 1; }
grep -q 'pr-agent 0.50.0' "$STUB_BODY" || { echo "FAIL D: body must name pr-agent and its version"; exit 1; }
grep -q 'claude -p' "$STUB_BODY" || { echo "FAIL D: body must say the model ran through claude -p"; exit 1; }
grep -qi 'AI-generated' "$STUB_BODY" || { echo "FAIL D: body must carry the AI-generated disclaimer"; exit 1; }
grep -q 'stub finding in a.ts' "$STUB_BODY" || { echo "FAIL D: body must carry pr-agent's findings"; exit 1; }
grep -q '^Published: https://github.com/o/r/pull/7#issuecomment-123' "$T/out/PR-AGENT-7.md" || { echo "FAIL D: report must record the comment URL"; exit 1; }

# --- E: a failed review (claude error, outage) is FAILED and is never posted. ------------
reset
if STUB_FAIL=1 sh "$TOOL" "$T/pr.diff" "$T/out" o/r 7 --publish > "$T/e.log" 2>&1; then
  echo "FAIL E: a failed pr-agent review must exit non-zero"; exit 1
fi
grep -q '^STATUS: FAILED' "$T/out/PR-AGENT-7.md" || { echo "FAIL E: must say STATUS: FAILED"; exit 1; }
test ! -s "$STUB_GH" || { echo "FAIL E: a failed review must not be posted"; exit 1; }

echo ok
