#!/bin/sh
# Eval: the offline enforcement tour (tools/sandbox-tour) exercises every
# offline-checkable runtime mechanic and prints the expected markers. This is the
# deterministic surface of this skill: no model, no network. It fails if the runtime
# stops denying, stops normalizing wrapped names, or stops catching tampering.
# Runs from the skill dir (icm.sh eval cwd's here). Exit 0 = pass.
set -u

# Pick a writable sandbox base for the tour: prefer $TMPDIR, else a repo-local dir
# we create and remove. The tour itself removes its own icm-demo.XXXXXX subdir.
base="${TMPDIR:-/tmp}"
if ( : > "$base/.icmdemo_wtest.$$" ) 2>/dev/null; then
    rm -f "$base/.icmdemo_wtest.$$"
else
    base="$PWD/.eval-tmp"
fi
mkdir -p "$base"
export ICM_DEMO_TMP="$base"
trap 'rm -rf "$PWD/.eval-tmp"' EXIT INT TERM

out=$(tools/sandbox-tour 2>&1) || { echo "FAIL: sandbox-tour exited non-zero"; printf '%s\n' "$out"; exit 1; }

need() { # $1 = human label, $2 = grep ERE
    printf '%s\n' "$out" | grep -Eq -- "$2" || { echo "FAIL: missing $1 (/$2/)"; printf '%s\n' "$out"; exit 1; }
}

need "stage-scoping / non-gated / allow"   'ALLOW \(gate-check exit 0\)'
need "gate DENY on unmet precondition"     'DENY .* 02-enforcement: checker failed: checks/ready\.sh'
need "cross-harness wrapped name present"  'mcp__claude_ai_Notion__demo_publish'
need "seal verified"                       'SEAL OK '
need "seal-tamper detected"                'SEAL MISMATCH .*events\.jsonl'
need "contract-tamper detected"            'contract tampered'
need "tour completed cleanly"              'tour complete'

# The wrapped mcp__ name must itself be DENIED, proving normalization matched the
# gate (not merely that the string was printed): expect >= 2 'checker failed'
# denials - the canonical name in step 2 AND the wrapped name in step 3.
n=$(printf '%s\n' "$out" | grep -c 'checker failed: checks/ready\.sh')
[ "$n" -ge 2 ] || { echo "FAIL: expected >=2 'checker failed' denials (got $n); normalization step did not deny"; exit 1; }

echo "ok"
