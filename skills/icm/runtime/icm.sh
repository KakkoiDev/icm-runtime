#!/bin/sh
# ICM Runtime — POSIX-compatible (macOS, Linux, WSL)
# Usage:
#   icm.sh init   <workspace-name> [--caller <ws>/<run_id>/<stage>]  Create new run; --caller records the invoking parent run
#   icm.sh children <workspace-name> [<run_id>]  List runs that recorded this run as their --caller (parent->child links)
#   icm.sh next   <workspace-name>          Print path to next empty stage, or "done"
#   icm.sh list   <workspace-name>          List all runs with stage completion status
#   icm.sh diff   <workspace-name>          Diff output files of last two completed runs
#   icm.sh stages <workspace-name>          Print stage names in order
#   icm.sh clean  <workspace-name> [--keep N]  Remove old completed runs, keep N most recent
#   icm.sh gate-check --tool <tool-name> [--cwd DIR]  Evaluate frozen ICM-GATE lines; exit 1 + DENY on failure
#   icm.sh gate-status [--cwd DIR]           List declared gates and hook registration per scope
#   icm.sh telemetry <workspace> [--cwd <dir>]   Totals derived from per-stage telemetry; legacy --model/--tokens-in/--tokens-out/--cost accepted but ignored
#   icm.sh stage-done <workspace> --stage <name> [--full] [--transcript <path>] [--cwd <dir>]   Model+tokens auto-detected from transcript; legacy --model/--tokens-in/--tokens-out are a no-transcript fallback
#   icm.sh reify-telemetry <workspace> [--cwd <dir>] [--transcript <path>]
#   icm.sh audit <workspace> [--strict] [--cwd <dir>]  --strict exits 1 if deviations>0
#   icm.sh seal <workspace> [--cwd <dir>]         Append run evidence digests to .icm-seals.log
#   icm.sh verify-seal <workspace>|--all [--cwd <dir>]  Recompute digests against last seal(s); exit 1 on mismatch

set -eu

ICM_VERSION="0.9.0"

# --- telemetry ---
ICM_TELEMETRY_DIR=".icm/telemetry"
ICM_LOG_START=""
ICM_LOG_CMD=""

_log_start() {
    [ -d "$ICM_TELEMETRY_DIR" ] || return 0
    ICM_LOG_START=$(date -u +%Y-%m-%dT%H:%M:%SZ)
    ICM_LOG_CMD="$*"
}

_log_end() {
    [ -d "$ICM_TELEMETRY_DIR" ] || return 0
    [ -n "${ICM_LOG_START:-}" ] || return 0
    _ec=${1:-0}
    # Single sed fork builds the compact JSON array (escape \ and ", split on
    # spaces). This runs on every hooked tool call; keep it fork-lean. Must
    # stay one physical line: multi-line entries break every JSONL consumer.
    _args_json=$(printf '%s' "$ICM_LOG_CMD" \
        | sed 's/\\/\\\\/g; s/"/\\"/g; s/ /","/g; s/^/["/; s/$/"]/')
    printf '{"ts":"%s","tool":"icm.sh","cmd":"%s","args":%s,"cwd":"%s","ec":%s}\n' \
        "$ICM_LOG_START" "${ICM_LOG_CMD%% *}" \
        "$_args_json" "$PWD" "$_ec" \
        >> "$ICM_TELEMETRY_DIR/tool-calls.jsonl" 2>/dev/null || true
}
# Logical (not -P) resolution on purpose: when invoked via the installed symlink
# (~/.agents/skills/icm/runtime/icm.sh), SKILLS_DIR must be ~/.agents/skills - where
# EVERY installed skill lives - not this repo's skills/, which only holds its own.
# Physical resolution broke init/stages for all externally-installed workspaces.
SCRIPT_DIR=$(cd "$(dirname "$0")" && pwd)
SKILLS_DIR=$(cd "$SCRIPT_DIR/../.." && pwd)

usage() {
    echo "Usage: icm.sh <init|next|list|diff|stages|clean> <workspace-name> [--keep N]" >&2
    echo "       icm.sh init <workspace> [--caller <parentWs>/<parentRunId>/<stage>]" >&2
    echo "       icm.sh catalog                  # markdown index of installed skills" >&2
    echo "       icm.sh new-skill <ns>/<name> --stages a,b,c [--desc <one-liner>]" >&2
    echo "       icm.sh eval <workspace>         # run the skill's eval/*.test.sh checks" >&2
    echo "       icm.sh children <workspace> [<run_id>]" >&2
    echo "       icm.sh gate-check --tool <tool-name> [--cwd <dir>]" >&2
    echo "       icm.sh gate-status [--cwd <dir>]" >&2
    echo "       icm.sh telemetry <workspace> [--cwd <dir>]   # counts derived from per-stage telemetry" >&2
    echo "       icm.sh stage-done <workspace> --stage <name> [--full] [--transcript <path>] [--cwd <dir>]" >&2
    echo "       icm.sh reify-telemetry <workspace> [--cwd <dir>] [--transcript <path>]" >&2
    echo "       icm.sh audit <workspace> [--strict] [--cwd <dir>]" >&2
    echo "       icm.sh seal <workspace> [--cwd <dir>]" >&2
    echo "       icm.sh verify-seal <workspace>|--all [--cwd <dir>]" >&2
    echo "       icm.sh --version" >&2
    echo "" >&2
    echo "Examples:" >&2
    echo "  icm.sh init kakkoidev/icm-demo                       # start a new run" >&2
    echo "  icm.sh next kakkoidev/icm-demo                       # path to the next empty stage" >&2
    echo "  icm.sh stage-done kakkoidev/icm-demo --stage 01-lifecycle  # close a stage, snapshot tokens" >&2
    echo "  icm.sh audit kakkoidev/icm-demo --strict             # fail on any deviation" >&2
    echo "  icm.sh seal kakkoidev/icm-demo                       # anchor evidence digests" >&2
    echo "  icm.sh eval kakkoidev/icm-demo                       # run the skill's eval suite" >&2
    exit 1
}

# Resolve skill stages directory
# Supports namespace/name syntax for deterministic resolution under a namespace.
# Bare names fall back to recursive find (backward compatible).
find_workspace() {
    ws=$1
    case "$ws" in
        */*)
            # Namespaced: "company/fix-payments"
            namespace="${ws%%/*}"
            name="${ws#*/}"
            found="$SKILLS_DIR/$namespace/$name"
            if [ ! -d "$found" ]; then
                echo "Error: workspace '$ws' not found at $found" >&2
                exit 1
            fi
            ;;
        *)
            # Bare name: recursive find (backward compatible). -L because installed
            # skills are SYMLINKS into their source repos (installer.sh default mode);
            # without it, find -type d skips every symlinked workspace.
            found=$(find -L "$SKILLS_DIR" -maxdepth 4 -type d -name "$ws" 2>/dev/null | head -1)
            if [ -z "$found" ]; then
                echo "Error: workspace '$ws' not found under $SKILLS_DIR" >&2
                echo "Tip: use namespace/name if the skill is nested, e.g. company/fix-payments" >&2
                exit 1
            fi
            ;;
    esac

    stages_dir="$found/stages"
    if [ ! -d "$stages_dir" ]; then
        echo "Error: workspace path has no stages/ directory" >&2
        exit 1
    fi
    echo "$found"
}

# Find latest timestamp directory for a workspace
latest_run() {
    ws=$1
    icm_dir=".icm/$ws"
    if [ ! -d "$icm_dir" ]; then
        echo ""
        return
    fi
    newest=$(cd "$icm_dir" && ls -1 2>/dev/null | sort -r | head -1)
    echo "$newest"
}

# Cold-path hint: a run-scoped command found no run in the CURRENT cwd. If the
# workspace DOES have runs at the git toplevel, the caller is almost certainly
# running from a stage/subdir (.icm resolves cwd-relative). Point them at the
# repo root instead of the misleading "no active run". One git fork, only in the
# already-failing error branch - never the gate hot path (which uses latest_runs).
_cwd_hint() {
    _ch_ws=$1
    [ -d ".icm/$_ch_ws" ] && return 0
    _ch_top=$(git rev-parse --show-toplevel 2>/dev/null) || return 0
    [ -n "$_ch_top" ] || return 0
    [ "$_ch_top" = "$PWD" ] && return 0
    if [ -d "$_ch_top/.icm/$_ch_ws" ]; then
        echo "  hint: no .icm/ in this cwd; the run lives at the repo root -- run from: cd $_ch_top" >&2
    fi
}

# Check if a directory is empty (POSIX)
is_empty_dir() {
    [ -z "$(ls -A "$1" 2>/dev/null)" ]
}

# Portable sha256: prints "<hash>  <path>"
sha_file() {
    if command -v sha256sum >/dev/null 2>&1; then
        sha256sum "$1"
    else
        shasum -a 256 "$1"
    fi
}

# Locate the current session transcript for a run. $1 = run dir.
# Prints "<path>\t<source>" (tab-separated) on success, nothing on failure.
# Resolution order, most authoritative first:
#   session-env     Claude Code exports CLAUDE_CODE_SESSION_ID and names the
#                   transcript <session_id>.jsonl under the munged-cwd project
#                   dir, so the exact path is computable with no shared state.
#                   Concurrency-safe: each session resolves only its own file.
#   hook            path recorded by gate-hook.sh into .icm/telemetry. A single
#                   shared file, correct only without concurrent sessions.
#   fallback-cwd    newest *.jsonl under the run's munged-cwd project dir.
#   fallback-newest newest *.jsonl across all sessions; cwd could not be matched
#                   so attribution is a guess (audit flags this source).
# cwd is read from run.json (the recorded run cwd), not pwd, so resolution holds
# even if stage-done is invoked from a subdir. Warnings go to stderr.
find_transcript() {
    ft_run=$1
    ft_cwd=$(grep '"cwd"' "$ft_run/telemetry/run.json" 2>/dev/null | sed 's/.*"cwd": "\(.*\)".*/\1/' || :)
    [ -n "$ft_cwd" ] || ft_cwd=$(pwd)
    ft_munged=$(printf '%s' "$ft_cwd" | sed 's,[/.],-,g')

    if [ -n "${CLAUDECODE:-}" ] && [ -n "${CLAUDE_CODE_SESSION_ID:-}" ]; then
        ft_det="${HOME}/.claude/projects/$ft_munged/${CLAUDE_CODE_SESSION_ID}.jsonl"
        if [ -f "$ft_det" ]; then
            printf '%s\t%s\n' "$ft_det" "session-env"
            return 0
        fi
    fi

    if [ -f ".icm/telemetry/transcript-path" ]; then
        ft_p=$(head -1 ".icm/telemetry/transcript-path" 2>/dev/null || :)
        if [ -n "$ft_p" ] && [ -f "$ft_p" ]; then
            printf '%s\t%s\n' "$ft_p" "hook"
            return 0
        fi
    fi

    ft_search=""
    ft_src="fallback-newest"
    if [ -n "${CLAUDECODE:-}" ]; then
        if [ -d "${HOME}/.claude/projects/$ft_munged" ]; then
            ft_search="${HOME}/.claude/projects/$ft_munged"
            ft_src="fallback-cwd"
        else
            ft_search="${HOME}/.claude/projects"
            ft_src="fallback-newest"
        fi
    elif [ -d "${HOME}/.pi" ]; then
        ft_search="${HOME}/.pi/agent/sessions"
        ft_src="fallback-newest"
    fi
    [ -n "$ft_search" ] || return 0
    ft_found=""
    ft_n=0
    for ft_c in $(find "$ft_search" -name '*.jsonl' -newer "$ft_run/.manifest" 2>/dev/null); do
        ft_n=$((ft_n + 1))
        if [ -z "$ft_found" ] || [ "$ft_c" -nt "$ft_found" ]; then
            ft_found=$ft_c
        fi
    done
    if [ "$ft_n" -gt 1 ]; then
        echo "icm: $ft_n candidate transcripts; picked newest: $ft_found" >&2
        echo "Pass --transcript <path> if this is the wrong session." >&2
    fi
    [ -z "$ft_found" ] || printf '%s\t%s\n' "$ft_found" "$ft_src"
}

# Print deduped usage events from transcript $1 within window [$2, $3] as
# compact JSONL: {ts, model, tokens_in, cache_creation, cache_read, tokens_out}.
# Accepts flat events ({ts, usage}) and Claude Code session format
# ({timestamp, message: {model, usage}}). Claude Code logs the same API message
# several times as content streams; dedup by message.id keeping the last
# occurrence, else counts inflate 2-3x. Requires jq; silent without it.
transcript_usage() {
    jq -c -s --arg start "$2" --arg end "$3" '
        [ to_entries[]
          | .key as $i | .value
          | (.ts // .timestamp // empty) as $t
          | select($t >= $start and $t <= $end)
          | (.usage // .message.usage // empty) as $u
          | select((($u.input_tokens // 0) + ($u.output_tokens // 0)) > 0)
          | {dedup: (.message.id // "line-\($i)"),
             ts: $t,
             model: (.model // .message.model // null),
             tokens_in: ($u.input_tokens // 0),
             cache_creation: ($u.cache_creation_input_tokens // 0),
             cache_read: ($u.cache_read_input_tokens // 0),
             tokens_out: ($u.output_tokens // 0)} ]
        | group_by(.dedup) | map(last) | sort_by(.ts) | .[]
        | del(.dedup)
    ' "$1" 2>/dev/null || true
}

# Sum a transcript_usage stream into the four token fields, space-separated:
# "tokens_in cache_creation cache_read tokens_out" (or "null null null null").
# tokens_in is the NEW-input slice only; cache reads/writes are kept separate so
# cost (cache reads are ~10x cheaper) is computable downstream.
usage_sums4() {
    jq -r '"\(.tokens_in) \(.cache_creation) \(.cache_read) \(.tokens_out)"' 2>/dev/null \
        | awk '{ti+=$1; cc+=$2; cr+=$3; to+=$4} END {if (NR==0) print "null null null null"; else print ti, cc, cr, to}'
}

# Emit the effective per-stage telemetry record per stage from a run's
# events.jsonl ($1): the last "reify" event for a stage if present, else the last
# "stage_done". Stage names are zero-padded (01-, 02-) so group_by sorts them in
# stage order. Output is compact JSONL, oldest stage first. Requires jq.
_run_stage_records() {
    [ -f "$1" ] || return 0
    command -v jq >/dev/null 2>&1 || return 0
    jq -c -s '
        [ .[] | select(.type == "stage_done" or .type == "reify") ]
        | group_by(.stage)
        | map( (map(select(.type == "reify")) | last) // (map(select(.type == "stage_done")) | last) )
        | .[]
    ' "$1" 2>/dev/null || true
}

# Extract a double-quoted attribute value from an ICM-GATE line. $1=line $2=attr name.
# Values must be double-quoted, single-line, with no embedded double quotes.
gate_attr() {
    printf '%s\n' "$1" | sed -n "s/.*$2=\"\([^\"]*\)\".*/\1/p"
}

# Cross-harness tool-name normalization. The same tool is named differently per
# harness (Claude Code: mcp__claude_ai_Notion__notion-fetch, WebSearch; pi/Codex:
# notion-fetch, search_web). Print a canonical form so a gate or ICM-TOOLS pattern
# written once binds in every harness:
#   - strip an MCP wrapper prefix: mcp__<server>__<tool> -> <tool>
#   - fold known built-in aliases to a canonical token.
# Gate/audit matching tries the raw name AND this normalized name, so existing
# patterns (raw mcp__ names or hand-written alternations) keep matching too.
_normalize_tool() {
    nt=$1
    case "$nt" in
        mcp__*__*) nt=${nt##*__} ;;
    esac
    case "$nt" in
        WebSearch|search_web|web_search) nt="web_search" ;;
        WebFetch|fetch_url|web_fetch) nt="web_fetch" ;;
    esac
    printf '%s\n' "$nt"
}

# Print the latest run dir per workspace under ./.icm. Handles both layouts
# (.icm/<ws>/<ts> and namespaced .icm/<ns>/<ws>/<ts>) by matching the timestamp
# format cmd_init writes, then keeping the lexically newest child per parent. The
# trailing '*' also matches a collision-suffixed id (<ts>.2) from a same-second
# init; the suffix sorts after the bare timestamp, so "newest" stays correct.
latest_runs() {
    [ -d .icm ] || return 0
    find .icm -mindepth 2 -maxdepth 3 -type d \
        -name '[0-9][0-9][0-9][0-9]-[0-9][0-9]-[0-9][0-9]_[0-9][0-9]-[0-9][0-9]-[0-9][0-9]*' \
        2>/dev/null | sort | {
        lr_prev_parent=""
        lr_prev=""
        while IFS= read -r lr_path; do
            lr_parent=${lr_path%/*}
            if [ -n "$lr_prev" ] && [ "$lr_parent" != "$lr_prev_parent" ]; then
                printf '%s\n' "$lr_prev"
            fi
            lr_prev_parent=$lr_parent
            lr_prev=$lr_path
        done
        if [ -n "$lr_prev" ]; then
            printf '%s\n' "$lr_prev"
        fi
    }
}

# Batch-verify checksums read from stdin in "<hash>  <path>" format.
sha_check() {
    if command -v sha256sum >/dev/null 2>&1; then
        sha256sum -c -
    else
        shasum -a 256 -c -
    fi
}

# Verify every entry of a run's .manifest. Prints the first bad relpath and
# returns 1 on hash mismatch or missing file. One checksum process for the
# whole manifest: this runs on every hooked tool call, per-file forks were
# the dominant gate-check cost.
verify_manifest() {
    vm_run=$1
    [ -s "$vm_run/.manifest" ] || return 0
    if vm_out=$( (cd "$vm_run" && sha_check < .manifest) 2>&1 ); then
        return 0
    fi
    vm_bad=$(printf '%s\n' "$vm_out" | awk -F': ' '/: FAILED/ {print $1; exit}')
    if [ -z "$vm_bad" ]; then
        vm_bad=$(printf '%s\n' "$vm_out" | head -1)
    fi
    echo "$vm_bad"
    return 1
}

# Print the active stage of run $1: the first stage (in order) with no stage_done
# event in events.jsonl, i.e. entered but not yet closed. Empty when every stage
# is closed (a finished run has no active gate). Gates are scoped to this stage so
# a later stage's gate cannot deny a tool the active stage legitimately calls, and
# a completed run in another workspace cannot tax the current one. Runs on the gate
# hot path: grep + a short loop, no jq, no fork per gate.
_active_stage() {
    as_events="$1/telemetry/events.jsonl"
    for as_dir in "$1"/[0-9]*/; do
        [ -f "$as_dir/CONTEXT.md" ] || continue
        as_name=$(basename "$as_dir")
        grep -q "\"type\":\"stage_done\",\"stage\":\"$as_name\"" "$as_events" 2>/dev/null || { printf '%s\n' "$as_name"; return 0; }
    done
    return 0
}

# Print the caller link ("<ws>/<run_id>/<stage>") recorded in run $1's run.json,
# or nothing for a standalone run. Used to scope gate evaluation across nested
# runs: a parent that invoked an open child suspends its own gates while the
# child runs (see cmd_gate_check).
_caller_of() {
    co_json="$1/telemetry/run.json"
    [ -f "$co_json" ] || return 0
    sed -n 's/.*"caller"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/p' "$co_json" | head -1
}

# Evaluate one run's frozen gates. $1=run dir, $2=tool name ("" = evaluate every
# gate regardless of its tools regex, used by gate-status). Prints DENY lines on
# stdout (first line is the headline); silent when nothing matches or all pass.
# Fails closed: tampered/missing manifest, malformed gate lines, and invalid
# regexes all deny. Gates are evaluated ONLY for the run's active stage (see
# _active_stage); manifest tamper-evidence is checked first, before any scoping.
check_run() {
    cr_run=$1
    cr_tool=$2
    cr_suspend=${3:-}
    cr_path=${4:-}
    cr_ws=${cr_run%/*}
    cr_ws=${cr_ws#.icm/}
    cr_ts=${cr_run##*/}

    if [ -f "$cr_run/.manifest" ]; then
        if ! vm_bad=$(verify_manifest "$cr_run"); then
            echo "DENY $cr_ws $cr_ts $vm_bad: contract tampered (sha256 mismatch with .manifest)"
            return 0
        fi
    fi

    # Caller-scoping: this run's gates are suspended because an open child run it
    # invoked is doing the work. The tamper check above still ran (fail-closed),
    # but evaluate no gates - the parent is not the one making this tool call.
    [ "$cr_suspend" = "suspend" ] && return 0

    # Scope gates to the active stage: a gate fires only while its owning stage is
    # the run's active (entered-but-not-closed) stage. A later stage's gate cannot
    # deny an earlier stage's tool, and a completed run (no active stage) denies
    # nothing. Computed once per run, after the tamper check.
    cr_active=$(_active_stage "$cr_run")

    # One grep across all frozen contracts (runs on every hooked tool call).
    # /dev/null forces the "path:" prefix even with a single match file.
    grep -F '<!-- ICM-GATE ' "$cr_run"/[0-9]*/CONTEXT.md /dev/null 2>/dev/null \
        | while IFS= read -r cr_hit; do
            cr_ctx=${cr_hit%%:*}
            cr_line=${cr_hit#*:}
            cr_stage_dir=${cr_ctx%/CONTEXT.md}
            cr_stage=${cr_stage_dir##*/}
            [ "$cr_stage" = "$cr_active" ] || continue
            cr_tools=$(gate_attr "$cr_line" tools)
            cr_runcmd=$(gate_attr "$cr_line" run)
            if [ -z "$cr_tools" ] || [ -z "$cr_runcmd" ]; then
                echo "DENY $cr_ws $cr_ts $cr_stage: malformed ICM-GATE line (need tools=\"...\" and run=\"...\")"
                continue
            fi
            if [ -n "$cr_tool" ]; then
                cr_rc=0
                { printf '%s\n' "$cr_tool"; _normalize_tool "$cr_tool"; } | grep -Eq -- "$cr_tools" || cr_rc=$?
                if [ "$cr_rc" -ge 2 ]; then
                    echo "DENY $cr_ws $cr_ts $cr_stage: invalid tools regex: $cr_tools"
                    continue
                fi
                [ "$cr_rc" -eq 0 ] || continue
            fi
            # Path scoping: a file-write tool call (Write/Edit) carries a target
            # path. A run's gate governs ONLY writes INTO that run's own tree
            # (stage output) - a write to an unrelated file is not this run's
            # concern, so an orphaned/incomplete run cannot deny every Write in
            # the session. Writes inside the run dir stay gated; path-less tool
            # calls (fetch/bash activity gates) carry no cr_path and keep global
            # scope, unchanged.
            if [ -n "$cr_path" ]; then
                case "$cr_path" in
                    *"$cr_run"/*) : ;;
                    *) continue ;;
                esac
            fi
            if [ ! -f "$cr_run/.manifest" ]; then
                echo "DENY $cr_ws $cr_ts $cr_stage: no .manifest in run, cannot verify frozen contract (re-init the run)"
                continue
            fi
            # Resolve a checker frozen at the run root (e.g. run="checks/x.sh"),
            # then execute from the stage dir.
            cr_first=${cr_runcmd%% *}
            cr_rest=""
            case "$cr_runcmd" in
                *' '*) cr_rest=" ${cr_runcmd#* }" ;;
            esac
            cr_root_abs=$(cd "$cr_run" && pwd -P)
            cr_exec=$cr_runcmd
            if [ -f "$cr_root_abs/$cr_first" ]; then
                cr_exec="'$cr_root_abs/$cr_first'$cr_rest"
            fi
            if cr_out=$( (cd "$cr_stage_dir" && sh -c "$cr_exec") 2>&1 ); then
                :
            else
                echo "DENY $cr_ws $cr_ts $cr_stage: checker failed: $cr_runcmd"
                if [ -n "$cr_out" ]; then
                    printf '%s\n' "$cr_out" | head -10
                fi
            fi
        done
}

# A run is "open" - a fresh init would silently orphan it - when it is incomplete
# (at least one stage has no output yet) and has not been explicitly superseded.
# Mirrors the completion idiom used by next/clean (a stage is done when its
# output/ is non-empty). Cold path only (init), never the gate hot path.
_run_is_open() {
    _rio_dir=$1
    [ -d "$_rio_dir" ] || return 1
    if [ -f "$_rio_dir/telemetry/events.jsonl" ] \
        && grep -q '"type":"run_superseded"' "$_rio_dir/telemetry/events.jsonl" 2>/dev/null; then
        return 1
    fi
    for _rio_sd in "$_rio_dir"/[0-9]*/; do
        [ -d "$_rio_sd" ] || continue
        _rio_out="${_rio_sd}output"
        if [ ! -d "$_rio_out" ] || is_empty_dir "$_rio_out"; then
            return 0
        fi
    done
    return 1
}

# ---- init ----
cmd_init() {
    ws=""; caller=""; force=0
    while [ $# -gt 0 ]; do
        case "$1" in
            --caller) caller="$2"; shift 2 ;;
            --force) force=1; shift ;;
            *) ws="$1"; shift ;;
        esac
    done
    [ -n "$ws" ] || usage
    ws_dir=$(find_workspace "$ws")
    stages_dir="$ws_dir/stages"

    # Open-run guard: a second init while a run is still open silently orphans it
    # (the newer timestamp dir shadows the old one for every command - the
    # 2026-07-02 incident). Refuse unless --force (supersede the old run) or
    # --caller (nested runs are cross-workspace; the child never shadows a parent).
    if [ -z "$caller" ]; then
        _prev=$(latest_run "$ws")
        if [ -n "$_prev" ] && _run_is_open ".icm/$ws/$_prev"; then
            if [ "$force" -eq 0 ]; then
                echo "init: an open run already exists for $ws: $_prev" >&2
                echo "  resume it:    icm.sh next $ws" >&2
                echo "  or supersede: icm.sh init $ws --force" >&2
                exit 1
            fi
            # --force: tombstone the open run so it stops shadowing and its gates
            # close; the marker also makes the supersede visible to audit.
            _prev_ev=".icm/$ws/$_prev/telemetry/events.jsonl"
            if [ -f "$_prev_ev" ]; then
                printf '{"ts":"%s","type":"run_superseded","workspace":"%s","run_id":"%s"}\n' \
                    "$(date -u +%Y-%m-%dT%H:%M:%SZ)" "$ws" "$_prev" >> "$_prev_ev"
            fi
            echo "init: superseded open run $_prev (--force)" >&2
        fi
    fi

    ts=$(date -u +%Y-%m-%d_%H-%M-%S)
    # Same-second collision guard: two runs created in the same second (e.g. a
    # parent skill invoking a child via --caller) would otherwise share a run dir.
    # date is only 1s-resolution here (no portable sub-second: %N is GNU-only,
    # bash 3.2 has no $EPOCHREALTIME), so bump a numeric suffix until the dir is
    # free. The suffix sorts after the bare timestamp, so chronological ordering
    # holds, and latest_runs' glob tolerates it.
    run_dir=".icm/$ws/$ts"
    if [ -e "$run_dir" ]; then
        _ic_n=2
        while [ -e ".icm/$ws/$ts.$_ic_n" ]; do _ic_n=$((_ic_n + 1)); done
        ts="$ts.$_ic_n"
        run_dir=".icm/$ws/$ts"
    fi

    mkdir -p "$run_dir"

    # Create telemetry directories (per-run + global tool-calls.jsonl)
    mkdir -p "$run_dir/telemetry"
    mkdir -p ".icm/telemetry"

    # Sanctioned scratch area for heavy verification state (throwaway worktrees,
    # probe specs, extracted files). Seal-invisible by construction (_seal_files
    # digests only .manifest, telemetry/, and stage output/), and pruned with the
    # run by `clean`. A worktree created here must be `git worktree remove`d
    # before clean deletes the dir, or git leaves a stale registration.
    mkdir -p "$run_dir/work"

    for stage_file in "$stages_dir"/*.md; do
        [ -f "$stage_file" ] || continue
        stage_name=$(basename "$stage_file" .md)
        stage_dir="$run_dir/$stage_name"
        mkdir -p "$stage_dir/output"
        cp "$stage_file" "$stage_dir/CONTEXT.md"
    done

    # Freeze checker scripts and write the tamper-evidence manifest. gate-check
    # verifies these hashes before honoring any frozen gate.
    if [ -d "$ws_dir/checks" ]; then
        cp -R "$ws_dir/checks" "$run_dir/checks"
    fi
    # Freeze deterministic tools and add to manifest
    if [ -d "$ws_dir/tools" ]; then
        cp -R "$ws_dir/tools" "$run_dir/tools"
    fi
    # Freeze static reference assets (e.g. a frozen spec/lens the stages read), so
    # they are tamper-evident like checks/ and tools/. Read-only inputs to a run.
    if [ -d "$ws_dir/references" ]; then
        cp -R "$ws_dir/references" "$run_dir/references"
    fi
    (
        cd "$run_dir"
        for ctx in [0-9]*/CONTEXT.md; do
            [ -f "$ctx" ] || continue
            sha_file "$ctx"
        done
        for frozen_dir in checks tools references; do
            [ -d "$frozen_dir" ] || continue
            find "$frozen_dir" -type f | sort | while IFS= read -r ff; do
                sha_file "$ff"
            done
        done
    ) > "$run_dir/.manifest"

    # Write run metadata with stage list
    _stage_names=""
    for _sf in "$stages_dir"/*.md; do
        [ -f "$_sf" ] || continue
        _sn=$(basename "$_sf" .md)
        if [ -z "$_stage_names" ]; then
            _stage_names="\"$_sn\""
        else
            _stage_names="$_stage_names, \"$_sn\""
        fi
    done
    # Optional caller link, recorded on the CHILD so the child's own seal
    # (run.json is in _seal_files) makes "who invoked me" tamper-evident.
    # Omitted entirely for standalone runs so their run.json is unchanged.
    if [ -n "$caller" ]; then
        _caller_field=",
  \"caller\": \"$caller\""
    else
        _caller_field=""
    fi
    cat > "$run_dir/telemetry/run.json" <<ICM_RUN_EOF
{
  "workspace": "$ws",
  "run_id": "$ts",
  "created": "$(date -u +%Y-%m-%dT%H:%M:%SZ)",
  "stages": [$_stage_names],
  "cwd": "$PWD"$_caller_field
}
ICM_RUN_EOF

    # events.jsonl: the single per-run append-only telemetry stream. run.json
    # stays the static, sealed header; this stream carries run_init, usage,
    # stage_done and reify events. tool_call/gate stay per-project (hot path) and
    # are projected into the run view at read time.
    if [ -n "$caller" ]; then _ri_caller="\"$caller\""; else _ri_caller="null"; fi
    printf '{"ts":"%s","type":"run_init","workspace":"%s","run_id":"%s","stages":[%s],"cwd":"%s","caller":%s}\n' \
        "$(date -u +%Y-%m-%dT%H:%M:%SZ)" "$ws" "$ts" "$_stage_names" "$PWD" "$_ri_caller" \
        > "$run_dir/telemetry/events.jsonl"

    echo "$run_dir"

    # gitignore check (stderr so stdout stays clean for PI parsing)
    if [ ! -f ".gitignore" ]; then
        echo "WARNING: no .gitignore found. Add '.icm/' to keep state out of version control." >&2
    elif ! grep -q '^\.icm/' .gitignore 2>/dev/null; then
        echo "WARNING: .icm/ not found in .gitignore. Add '.icm/' to keep state out of version control." >&2
    fi
}

# ---- next ----
cmd_next() {
    ws=$1
    latest=$(latest_run "$ws")
    if [ -z "$latest" ]; then
        _cwd_hint "$ws"
        echo "Error: no runs found for workspace '$ws'" >&2
        exit 1
    fi
    run_dir=".icm/$ws/$latest"

    for stage_dir in "$run_dir"/[0-9]*/; do
        [ -d "$stage_dir" ] || continue
        output_dir="${stage_dir}output"
        if [ ! -d "$output_dir" ] || is_empty_dir "$output_dir"; then
            # Remove trailing slash
            echo "${stage_dir%/}"
            exit 0
        fi
    done

    echo "done"
    exit 0
}

# ---- list ----
cmd_list() {
    ws=$1
    icm_dir=".icm/$ws"
    if [ ! -d "$icm_dir" ]; then
        echo "No runs for workspace '$ws'."
        exit 0
    fi

    for run_dir in "$icm_dir"/*/; do
        [ -d "$run_dir" ] || continue
        run_name=$(basename "$run_dir")
        echo "--- $run_name ---"
        for stage_dir in "$run_dir"/[0-9]*/; do
            [ -d "$stage_dir" ] || continue
            stage_name=$(basename "$stage_dir")
            output_dir="${stage_dir}output"
            if [ -d "$output_dir" ] && [ -n "$(ls -A "$output_dir" 2>/dev/null)" ]; then
                status="✓"
            else
                status="✗"
            fi
            echo "  $status $stage_name"
        done
    done
}

# ---- diff ----
cmd_diff() {
    ws=$1
    icm_dir=".icm/$ws"
    if [ ! -d "$icm_dir" ]; then
        echo "No runs for workspace '$ws'." >&2
        exit 1
    fi

    # Find complete runs (all stages have output)
    complete=""
    for run_dir in $(cd "$icm_dir" && ls -1 2>/dev/null | sort); do
        all_done=true
        for stage_dir in "$icm_dir/$run_dir"/[0-9]*/; do
            [ -d "$stage_dir" ] || continue
            output_dir="${stage_dir}output"
            if [ ! -d "$output_dir" ] || is_empty_dir "$output_dir"; then
                all_done=false
                break
            fi
        done
        if [ "$all_done" = true ]; then
            complete="$complete $run_dir"
        fi
    done

    set -- $complete
    count=$#
    if [ "$count" -lt 2 ]; then
        echo "Need at least 2 complete runs to diff. Found $count." >&2
        exit 1
    fi

    # Last two complete runs
    prev_run=""
    last_run=""
    for run in $complete; do
        prev_run=$last_run
        last_run=$run
    done

    echo "Diffing:"
    echo "  Old: $prev_run"
    echo "  New: $last_run"
    echo ""

    for stage_dir in "$icm_dir/$last_run"/[0-9]*/; do
        [ -d "$stage_dir" ] || continue
        stage_name=$(basename "$stage_dir")
        old_stage="$icm_dir/$prev_run/$stage_name"
        if [ ! -d "$old_stage" ]; then
            echo "[$stage_name] only in new run (skipping)"
            continue
        fi
        for out_file in "$stage_dir/output"/*.md; do
            [ -f "$out_file" ] || continue
            fname=$(basename "$out_file")
            old_file="$old_stage/output/$fname"
            if [ -f "$old_file" ]; then
                if diff -q "$old_file" "$out_file" >/dev/null 2>&1; then
                    echo "[$stage_name/$fname] no change"
                else
                    echo "[$stage_name/$fname] changed"
                    diff -u "$old_file" "$out_file" || true
                fi
            else
                echo "[$stage_name/$fname] new file"
            fi
        done
    done
}

# ---- clean ----
cmd_clean() {
    ws=$1
    keep=5
    shift
    while [ $# -gt 0 ]; do
        case "$1" in
            --keep) keep=$2; shift 2 ;;
            *) shift ;;
        esac
    done

    icm_dir=".icm/$ws"
    if [ ! -d "$icm_dir" ]; then
        echo "No runs for workspace '$ws'." >&2
        exit 0
    fi

    # Classify runs: complete vs incomplete
    complete_runs=""
    incomplete_runs=""
    for run_dir in $(cd "$icm_dir" && ls -1 2>/dev/null | sort -r); do
        all_done=true
        for stage_dir in "$icm_dir/$run_dir"/[0-9]*/; do
            [ -d "$stage_dir" ] || continue
            output_dir="${stage_dir}output"
            if [ ! -d "$output_dir" ] || is_empty_dir "$output_dir"; then
                all_done=false
                break
            fi
        done
        if [ "$all_done" = true ]; then
            complete_runs="$complete_runs $run_dir"
        else
            incomplete_runs="$incomplete_runs $run_dir"
        fi
    done

    # Delete old complete runs, keeping the N most recent
    count=0
    removed=0
    for run in $complete_runs; do
        count=$((count + 1))
        if [ "$count" -gt "$keep" ]; then
            rm -rf "$icm_dir/$run"
            removed=$((removed + 1))
        fi
    done

    # Rotate the shared per-project logs: the wide hook matcher writes one line
    # per tool call (tool-calls.jsonl) and one per call's args (tool-args.jsonl),
    # both unbounded in long-lived projects. Audit pruned runs before cleaning;
    # rotation drops their actual-tool / args records.
    for _tc_log in ".icm/telemetry/tool-calls.jsonl" ".icm/telemetry/tool-args.jsonl"; do
        [ -f "$_tc_log" ] || continue
        _tc_lines=$(wc -l < "$_tc_log" | tr -d ' ')
        if [ "$_tc_lines" -gt 10000 ]; then
            tail -n 10000 "$_tc_log" > "$_tc_log.tmp" && mv "$_tc_log.tmp" "$_tc_log"
            echo "Rotated $(basename "$_tc_log"): kept last 10000 of $_tc_lines lines."
        fi
    done

    echo "Cleaned $removed complete run(s). Kept up to $keep most recent. Incomplete runs preserved."
}

# ---- stages ----
cmd_stages() {
    ws=$1
    ws_dir=$(find_workspace "$ws")
    stages_dir="$ws_dir/stages"

    for stage_file in "$stages_dir"/*.md; do
        [ -f "$stage_file" ] || continue
        stage_name=$(basename "$stage_file" .md)
        echo "$stage_name"
    done
}

# ---- catalog ----
# Discoverability index of installed skills: scan SKILLS_DIR for <ns>/<skill>/
# SKILL.md, read name + description from the YAML front-matter, print a markdown
# table. The runtime's own icm/SKILL.md (one level deep) is excluded. Regenerate
# the repo index with `icm.sh catalog > SKILLS.md`.
cmd_catalog() {
    echo "| Skill | Description |"
    echo "|-------|-------------|"
    for cat_md in "$SKILLS_DIR"/*/*/SKILL.md; do
        [ -f "$cat_md" ] || continue
        cat_dir=${cat_md%/SKILL.md}
        cat_slug=${cat_dir#"$SKILLS_DIR"/}
        cat_name=$(sed -n 's/^name:[[:space:]]*//p' "$cat_md" | head -1)
        [ -n "$cat_name" ] || cat_name=${cat_slug##*/}
        cat_desc=$(awk '
            /^description:/ {
                sub(/^description:[[:space:]]*/, "")
                if ($0 == ">" || $0 == "|" || $0 == "") { getline; sub(/^[[:space:]]+/, "") }
                gsub(/\|/, "\\|")
                print; exit
            }' "$cat_md")
        printf '| `%s` | %s |\n' "$cat_slug" "$cat_desc"
    done
}

# ---- new-skill (scaffolder) ----
# Emit a new skill skeleton so skills are not made by copy-pasting another one.
# The SKILL.md carries skill-specific content plus a Runtime POINTER to the
# canonical contract (the ICM README), not copied boilerplate, so the runtime
# command surface lives in one place and cannot go stale across skills (DRY).
# Usage: icm.sh new-skill <ns>/<name> --stages a,b,c [--desc "one-liner"]
cmd_new_skill() {
    ns_name=""; ns_stages=""; ns_desc="One-line description (replace me)."
    while [ $# -gt 0 ]; do
        case "$1" in
            --stages) ns_stages="$2"; shift 2 ;;
            --desc) ns_desc="$2"; shift 2 ;;
            *) ns_name="$1"; shift ;;
        esac
    done
    case "$ns_name" in
        */*) : ;;
        *) echo "new-skill requires <namespace>/<name>" >&2; exit 1 ;;
    esac
    [ -n "$ns_stages" ] || { echo "new-skill requires --stages a,b,c" >&2; exit 1; }
    ns_dir="$SKILLS_DIR/$ns_name"
    [ -e "$ns_dir" ] && { echo "new-skill: $ns_dir already exists" >&2; exit 1; }
    ns_slug=${ns_name##*/}
    mkdir -p "$ns_dir/stages" "$ns_dir/tools" "$ns_dir/eval"

    {
        printf -- '---\nname: %s\ndescription: >\n  %s\n---\n\n' "$ns_slug" "$ns_desc"
        printf '# %s\n\n' "$ns_slug"
        printf '## Runtime\n'
        printf 'Drive everything through `icm.sh` (never create state dirs or format timestamps\n'
        printf 'by hand). Init a run, then execute and CLOSE each stage in real time with\n'
        printf '`stage-done`; audit and seal at the end. The full runtime contract -- telemetry,\n'
        printf 'audit, seal, gates -- lives in the ICM runtime README, not in this file.\n\n'
        printf '## Stages\n'
        ns_i=0; ns_old_ifs=$IFS; IFS=,
        for ns_st in $ns_stages; do
            IFS=$ns_old_ifs
            ns_i=$((ns_i + 1))
            ns_num=$(printf '%02d' "$ns_i")
            printf -- '- `%s-%s`\n' "$ns_num" "$ns_st"
            IFS=,
        done
        IFS=$ns_old_ifs
    } > "$ns_dir/SKILL.md"

    ns_i=0; ns_old_ifs=$IFS; IFS=,
    for ns_st in $ns_stages; do
        IFS=$ns_old_ifs
        ns_i=$((ns_i + 1))
        ns_num=$(printf '%02d' "$ns_i")
        {
            printf '# %s-%s\n\n' "$ns_num" "$ns_st"
            printf '## Process\n1. Describe the deterministic steps for this stage. Push bash-reachable\n'
            printf '   work into `tools/` scripts; leave only judgement/summarization to the model.\n\n'
            printf '## Inputs\n- (prior stage output this stage reads)\n\n'
            printf '## Outputs\n- `output/<file>` (what this stage writes)\n\n'
            printf '## After Output (MANDATORY)\n```bash\n'
            printf 'bash ~/.agents/skills/icm/runtime/icm.sh stage-done %s --stage %s-%s\n' "$ns_name" "$ns_num" "$ns_st"
            printf '```\n'
        } > "$ns_dir/stages/${ns_num}-${ns_st}.md"
        IFS=,
    done
    IFS=$ns_old_ifs

    {
        printf '# Eval: %s\n\n' "$ns_slug"
        printf 'Holds `*.test.sh` checks run by `icm.sh eval %s` (each runs from the skill\n' "$ns_name"
        printf 'dir and exits 0 on pass). Test the deterministic surface -- tools/, receipts,\n'
        printf 'gate outcomes; model-mediated stages need a fixture/replay. Replace the stub.\n'
    } > "$ns_dir/eval/README.md"
    {
        printf '#!/bin/sh\n# Smoke eval for %s. Runs from the skill dir; exit 0 = pass.\n' "$ns_slug"
        printf 'set -eu\n'
        printf 'test -f SKILL.md || { echo "FAIL: SKILL.md missing"; exit 1; }\n'
        printf 'echo ok\n'
    } > "$ns_dir/eval/smoke.test.sh"
    chmod +x "$ns_dir/eval/smoke.test.sh" 2>/dev/null || :
    printf '.gitkeep\n' > "$ns_dir/tools/.gitkeep" 2>/dev/null || :

    echo "created skill $ns_name at $ns_dir"
    echo "  stages: $ns_stages"
    echo "  next: fill SKILL.md description, each stage's Process, and the eval"
}

# ---- eval ----
# Run a skill's eval suite: each eval/*.test.sh executes from the skill dir and
# exits 0 on pass. Tests the deterministic surface (tools/, contracts, receipts)
# without a live model -- the build/execute split is unverifiable otherwise.
# Reports pass/fail; exits 1 if any test fails.
cmd_eval() {
    ev_wsdir=$(find_workspace "$1")
    ev_dir="$ev_wsdir/eval"
    if [ ! -d "$ev_dir" ]; then
        echo "no eval/ dir for $1" >&2
        exit 1
    fi
    ev_pass=0; ev_fail=0
    for ev_t in "$ev_dir"/*.test.sh; do
        [ -f "$ev_t" ] || continue
        ev_name=$(basename "$ev_t")
        if ev_out=$( (cd "$ev_wsdir" && sh "$ev_t") 2>&1 ); then
            echo "  PASS $ev_name"
            ev_pass=$((ev_pass + 1))
        else
            echo "  FAIL $ev_name"
            if [ -n "$ev_out" ]; then printf '%s\n' "$ev_out" | sed 's/^/      /'; fi
            ev_fail=$((ev_fail + 1))
        fi
    done
    echo "eval $1: $ev_pass passed, $ev_fail failed"
    [ "$ev_fail" -eq 0 ]
}

# ---- telemetry ----
# Append a one-line global index record for a run to skill-runs.jsonl. Token
# totals are DERIVED from the run's per-stage telemetry (the model cannot
# self-estimate them); cost is intentionally not stored - downstream readers
# price the tokens from a rate table they own. Records accrete append-only; a
# reader takes the last per (skill, run_id). A "provisional" record is written
# at each stage-done so an abandoned (never closed) run stays visible; reify and
# telemetry upgrade it to "final".
# $1=workspace  $2=run_id  $3=status (provisional|final)
_global_upsert() {
    gu_ws=$1; gu_run=$2; gu_status=$3
    gu_rd=".icm/$gu_ws/$gu_run"
    [ -d "$gu_rd" ] || return 0
    gu_dir="${HOME}/.icm/telemetry"
    mkdir -p "$gu_dir"
    gu_ev="$gu_rd/telemetry/events.jsonl"
    gu_ti="null"; gu_to="null"; gu_model=""
    if [ -f "$gu_ev" ] && command -v jq >/dev/null 2>&1; then
        gu_recs=$(_run_stage_records "$gu_ev")
        if [ -n "$gu_recs" ]; then
            gu_ti=$(printf '%s\n' "$gu_recs" | jq -s '[.[].tokens_in | numbers] | if length==0 then null else add end' 2>/dev/null || echo null)
            gu_to=$(printf '%s\n' "$gu_recs" | jq -s '[.[].tokens_out | numbers] | if length==0 then null else add end' 2>/dev/null || echo null)
            gu_model=$(printf '%s\n' "$gu_recs" | jq -rs '[.[].model | strings | select(. != "(from transcript)" and . != "")] | last // ""' 2>/dev/null || echo "")
        fi
    fi
    [ -n "$gu_ti" ] || gu_ti="null"
    [ -n "$gu_to" ] || gu_to="null"
    gu_cwd=$(grep '"cwd"' "$gu_rd/telemetry/run.json" 2>/dev/null | sed 's/.*"cwd": "\(.*\)".*/\1/' || echo "$PWD")
    gu_caller=$(grep '"caller"' "$gu_rd/telemetry/run.json" 2>/dev/null | sed 's/.*"caller": *"\([^"]*\)".*/\1/' || echo "")
    if [ -n "$gu_caller" ]; then gu_caller_json="\"$gu_caller\""; else gu_caller_json="null"; fi
    printf '{"ts":"%s","status":"%s","skill":"%s","run_id":"%s","model":"%s","tokens_in":%s,"tokens_out":%s,"cwd":"%s","caller":%s,"log_dir":".icm/%s/%s/telemetry"}\n' \
        "$(date -u +%Y-%m-%dT%H:%M:%SZ)" "$gu_status" "$gu_ws" "$gu_run" "$gu_model" "$gu_ti" "$gu_to" "$gu_cwd" "$gu_caller_json" "$gu_ws" "$gu_run" \
        >> "$gu_dir/skill-runs.jsonl"
}

# Write a completed-run summary to the global telemetry file.
# Called by workspace skills after all stages complete. --model/--tokens-in/
# --tokens-out/--cost are accepted for backward compatibility but ignored:
# totals are derived from per-stage telemetry, cost is not stored.
cmd_telemetry() {
    ws=""
    while [ $# -gt 0 ]; do
        case "$1" in
            --model) shift 2 ;;
            --tokens-in) shift 2 ;;
            --tokens-out) shift 2 ;;
            --cost) shift 2 ;;
            --cwd) cd "$2"; shift 2 ;;
            *) ws="$1"; shift ;;
        esac
    done
    if [ -z "$ws" ]; then
        echo "telemetry requires workspace name" >&2
        exit 1
    fi
    latest=$(latest_run "$ws")
    if [ -z "$latest" ]; then
        _cwd_hint "$ws"
        echo "no runs for $ws" >&2
        exit 1
    fi
    _global_upsert "$ws" "$latest" final
    echo "${HOME}/.icm/telemetry/skill-runs.jsonl"
}

# ---- stage-done ----
# Record a stage boundary marker. Token counts are OPTIONAL (the model
# cannot access them programmatically; Tier 2 reify-telemetry fills them
# in post-hoc from the conversation transcript).
# MANDATORY after every completed stage.
cmd_stage_done() {
    ws=""; stage=""; model=""; tokens_in="null"; tokens_out="null"; full=0; transcript=""
    while [ $# -gt 0 ]; do
        case "$1" in
            --stage) stage="$2"; shift 2 ;;
            --model) model="$2"; shift 2 ;;
            --tokens-in) tokens_in="$2"; shift 2 ;;
            --tokens-out) tokens_out="$2"; shift 2 ;;
            --full) full=1; shift ;;
            --transcript) transcript="$2"; shift 2 ;;
            --cwd) cd "$2"; shift 2 ;;
            *) ws="$1"; shift ;;
        esac
    done
    if [ -z "$ws" ]; then
        echo "stage-done requires workspace name" >&2
        exit 1
    fi
    if [ -z "$stage" ]; then
        echo "stage-done requires --stage <name>" >&2
        exit 1
    fi

    latest=$(latest_run "$ws")
    if [ -z "$latest" ]; then
        echo "no active run for $ws" >&2
        exit 1
    fi

    run_dir=".icm/$ws/$latest"
    telemetry_dir="$run_dir/telemetry"
    mkdir -p "$telemetry_dir"

    _now=$(date -u +%Y-%m-%dT%H:%M:%SZ)
    _events="$telemetry_dir/events.jsonl"
    # Stage window: previous stage_done boundary in events.jsonl, else run creation.
    _prev_ts=$(grep '"type":"stage_done"' "$_events" 2>/dev/null | tail -1 | grep -o '"ts":"[^"]*"' | head -1 | sed 's/"ts":"//;s/"$//' || :)
    if [ -z "$_prev_ts" ]; then
        _prev_ts=$(grep '"created"' "$telemetry_dir/run.json" 2>/dev/null | sed 's/.*"created": "\(.*\)".*/\1/' || :)
    fi
    [ -n "$_prev_ts" ] || _prev_ts="1970-01-01T00:00:00Z"

    # Snapshot the session transcript usage for this window while it still exists,
    # appending one "usage" event per deduped API call to events.jsonl; --full also
    # freezes the raw window into the stage dir. Transcript-derived counts and model
    # are authoritative; hand-passed --tokens-in/--tokens-out/--model are a
    # no-transcript fallback. All four token fields are carried (new input, cache
    # creation, cache read, output) so cost is computable.
    _counts="estimated"
    _cc_val="null"; _cr_val="null"
    if [ -n "$transcript" ]; then _transcript_src="manual"; else _transcript_src="none"; fi
    if command -v jq >/dev/null 2>&1; then
        if [ -z "$transcript" ]; then
            _ft=$(find_transcript "$run_dir")
            transcript=$(printf '%s' "$_ft" | cut -f1)
            _transcript_src=$(printf '%s' "$_ft" | cut -s -f2)
            [ -n "$_transcript_src" ] || _transcript_src="none"
        fi
        if [ -n "$transcript" ] && [ -f "$transcript" ]; then
            _snap=$(mktemp)
            transcript_usage "$transcript" "$_prev_ts" "$_now" \
                | jq -c --arg stage "$stage" '{type:"usage", stage:$stage} + .' 2>/dev/null > "$_snap" || true
            if [ -s "$_snap" ]; then
                cat "$_snap" >> "$_events"
                # Transcript counts win; hand-passed values only survive when no
                # transcript usage was captured for the window.
                _sums=$(usage_sums4 < "$_snap")
                if [ "${_sums%% *}" != "null" ]; then
                    tokens_in=${_sums%% *}; _rest=${_sums#* }
                    _cc_val=${_rest%% *}; _rest=${_rest#* }
                    _cr_val=${_rest%% *}; tokens_out=${_rest#* }
                    _counts="transcript"
                fi
                # Auto-detect the model from the window (last call naming one),
                # overriding an error-prone hand-passed --model.
                _tmodel=$(jq -r 'select(.model != null) | .model' "$_snap" 2>/dev/null | tail -1 || :)
                if [ -n "$_tmodel" ]; then model="$_tmodel"; fi
            fi
            rm -f "$_snap"
            if [ "$full" -eq 1 ]; then
                mkdir -p "$run_dir/$stage"
                jq -c --arg start "$_prev_ts" --arg end "$_now" '
                    (.ts // .timestamp // empty) as $t
                    | select($t >= $start and $t <= $end)
                ' "$transcript" 2>/dev/null > "$run_dir/$stage/transcript.jsonl" || true
            fi
        elif [ "$full" -eq 1 ]; then
            echo "stage-done: --full requested but no transcript found; nothing snapshotted" >&2
        fi
    elif [ "$full" -eq 1 ]; then
        echo "stage-done: --full requires jq; nothing snapshotted" >&2
    fi

    # Duplicate-closure visibility: re-closing a stage appends a second boundary
    # (tolerated - audit downgrades attribution on non-monotonic boundaries), but
    # a silent re-close hides a re-run. Warn so the operator notices (no behavior
    # change).
    if [ -f "$_events" ] && grep -Eq '"type":"stage_done","stage":"'"$stage"'"' "$_events" 2>/dev/null; then
        echo "stage-done: WARNING - $stage already has a stage-done; appending another (re-run?)." >&2
    fi

    # Write the stage_done boundary event (replaces stages.jsonl + the per-stage
    # .stage-telemetry marker). tokens_in/tokens_out default to null.
    _ti_val="$tokens_in"
    _to_val="$tokens_out"
    case "$_ti_val" in ''|null) _ti_val="null" ;; esac
    case "$_to_val" in ''|null) _to_val="null" ;; esac
    printf '{"ts":"%s","type":"stage_done","stage":"%s","model":"%s","tokens_in":%s,"cache_creation":%s,"cache_read":%s,"tokens_out":%s,"counts":"%s","transcript_source":"%s"}\n' \
        "$_now" "$stage" "$model" "$_ti_val" "$_cc_val" "$_cr_val" "$_to_val" "$_counts" "$_transcript_src" \
        >> "$_events"

    # Refresh the provisional global index entry so an abandoned (never closed)
    # run stays visible with its completed-so-far totals; reify/telemetry finalize.
    _global_upsert "$ws" "$latest" provisional

    echo "OK: $stage boundary recorded for $ws/$latest"
}

# ---- reify-telemetry ----
# Post-hoc: read the conversation transcript and append exact per-stage token
# counts as "reify" events to the latest run's events.jsonl (last reify wins over
# the original stage_done; nothing is rewritten, so an earlier seal stays valid).
# Harness auto-detection: checks CLAUDECODE env var, then ~/.pi existence.
# --transcript overrides the auto-detected path.
cmd_reify_telemetry() {
    ws=""; transcript=""
    while [ $# -gt 0 ]; do
        case "$1" in
            --cwd) cd "$2"; shift 2 ;;
            --transcript) transcript="$2"; shift 2 ;;
            *) ws="$1"; shift ;;
        esac
    done
    if [ -z "$ws" ]; then
        echo "reify-telemetry requires workspace name" >&2
        exit 1
    fi

    latest=$(latest_run "$ws")
    if [ -z "$latest" ]; then
        _cwd_hint "$ws"
        echo "no runs for $ws" >&2
        exit 1
    fi
    run_dir=".icm/$ws/$latest"
    _events="$run_dir/telemetry/events.jsonl"
    if [ ! -f "$_events" ]; then
        echo "no events.jsonl -- run stage-done first" >&2
        exit 1
    fi

    _reify_src="manual"
    if [ -z "$transcript" ]; then
        _ft=$(find_transcript "$run_dir")
        transcript=$(printf '%s' "$_ft" | cut -f1)
        _reify_src=$(printf '%s' "$_ft" | cut -s -f2)
        [ -n "$_reify_src" ] || _reify_src="none"
    fi

    if [ -z "$transcript" ] || [ ! -f "$transcript" ]; then
        echo "reify-telemetry: cannot find conversation transcript" >&2
        echo "Pass --transcript <path> to specify it manually." >&2
        echo "Skipping -- stage markers are still valid, token counts remain as-is." >&2
        exit 0
    fi

    echo "reify-telemetry: reading transcript: $transcript"

    if command -v jq >/dev/null 2>&1; then
        _tmp=$(mktemp)
        _prev_ts="1970-01-01T00:00:00Z"
        # Iterate the original stage_done boundaries in ts order; recompute each
        # window's four-field counts and emit a reify event carrying them.
        jq -rs '[.[] | select(.type == "stage_done")] | sort_by(.ts) | .[] | [.ts, .stage] | @tsv' "$_events" 2>/dev/null \
            | while IFS='	' read -r _ts _stage; do
                [ -n "$_ts" ] || continue
                _wsnap=$(transcript_usage "$transcript" "$_prev_ts" "$_ts")
                _sums=$(printf '%s\n' "$_wsnap" | usage_sums4)
                _r_ti=${_sums%% *}; _r_rest=${_sums#* }
                _r_cc=${_r_rest%% *}; _r_rest=${_r_rest#* }
                _r_cr=${_r_rest%% *}; _r_to=${_r_rest#* }
                _r_model=$(printf '%s\n' "$_wsnap" | jq -r 'select(.model != null) | .model' 2>/dev/null | tail -1 || :)
                [ -n "$_r_model" ] || _r_model="(from transcript)"
                printf '{"ts":"%s","type":"reify","stage":"%s","model":"%s","tokens_in":%s,"cache_creation":%s,"cache_read":%s,"tokens_out":%s,"counts":"transcript","transcript_source":"%s"}\n' \
                    "$_ts" "$_stage" "$_r_model" "$_r_ti" "$_r_cc" "$_r_cr" "$_r_to" "$_reify_src"
                _prev_ts="$_ts"
            done > "$_tmp"
        if [ -s "$_tmp" ]; then
            cat "$_tmp" >> "$_events"
            rm -f "$_tmp"
            _global_upsert "$ws" "$latest" final
            echo "reify-telemetry: appended transcript token counts to $_events"
            return 0
        fi
        rm -f "$_tmp"
    fi

    echo "reify-telemetry: cannot reify token counts from transcript." >&2
    echo "Install jq for transcript parsing, or pass --transcript <path>." >&2
    echo "Stage markers are still valid; token counts remain as estimated." >&2
    exit 0
}

# ---- audit ----
# Compare expected tool calls (from frozen stage contracts) against
# actual tool invocations (from .icm/telemetry/tool-calls.jsonl).
# Also verifies that every completed stage has per-stage token telemetry
# (stage-done was called). Produces a deviation report on stdout.
# Read the stage-done boundary ts for a stage from events.jsonl ($1) by stage
# name ($2). Empty if the stage was never closed. Considers only boundary events
# (stage_done/reify), not intra-window usage events. Last match wins (re-runs and
# reify append; a reify event carries the same ts as the stage_done it refines).
_audit_stage_ts() {
    [ -f "$1" ] || return 0
    grep -E '"type":"(stage_done|reify)"' "$1" 2>/dev/null | grep "\"stage\":\"$2\"" | tail -1 \
        | grep -o '"ts":"[^"]*"' | sed 's/"ts":"//;s/"$//' || true
}

# gate-check --tool names from tool-calls.jsonl ($1) whose ts is in the window
# ($2=lo, $3=hi, $4=1 to include the lower bound). Drives per-stage attribution.
_audit_tools_in_window() {
    [ -f "$1" ] || return 0
    _aw=$(awk -v lo="$2" -v hi="$3" -v li="$4" -F '"' '
        /"ts":"/ { t=$4; if ((li==1 ? t>=lo : t>lo) && t<=hi) print }' "$1" 2>/dev/null || true)
    { printf '%s\n' "$_aw" | grep -o '"--tool","[^"]*"' | sed 's/"--tool","//;s/"$//' || true; \
      printf '%s\n' "$_aw" | grep -o -- '--tool [^" ]*' | sed 's/--tool //' || true; } | sort -u
}

# True (0) if ISO-Z ts $1 is strictly chronologically less than $2. POSIX sh has
# no string "<" in test, so compare via sort. Same-format ISO-Z strings sort
# lexicographically == chronologically.
_ts_lt() {
    [ "$1" != "$2" ] || return 1
    [ "$(printf '%s\n%s\n' "$1" "$2" | LC_ALL=C sort | head -1)" = "$1" ]
}

cmd_audit() {
    ws=""
    strict=0
    while [ $# -gt 0 ]; do
        case "$1" in
            --strict) strict=1; shift ;;
            --cwd) cd "$2"; shift 2 ;;
            *) ws="$1"; shift ;;
        esac
    done
    if [ -z "$ws" ]; then
        echo "audit requires workspace name" >&2
        exit 1
    fi

    latest=$(latest_run "$ws")
    if [ -z "$latest" ]; then
        _cwd_hint "$ws"
        echo "No runs for workspace '$ws'." >&2
        exit 1
    fi
    run_dir=".icm/$ws/$latest"

    # Check if run is complete (all stages have output)
    complete=true
    completed_stages=""
    for stage_dir in "$run_dir"/[0-9]*/; do
        [ -d "$stage_dir" ] || continue
        output_dir="${stage_dir}output"
        stage_name=$(basename "$stage_dir")
        if [ ! -d "$output_dir" ] || [ -z "$(ls -A "$output_dir" 2>/dev/null)" ]; then
            complete=false
        else
            completed_stages="$completed_stages $stage_name"
        fi
    done

    audit_header="AUDIT: $ws / $latest"
    if [ "$complete" = false ]; then
        echo "$audit_header (INCOMPLETE -- audit may be incomplete)"
    else
        echo "$audit_header"
    fi
    echo "=========================================="
    echo ""

    deviations=0
    events_log="$run_dir/telemetry/events.jsonl"

    # --- Check 1: per-stage telemetry completeness ---
    if [ "$complete" = true ]; then
        echo "STAGE TELEMETRY CHECK"
        echo "──────────────────────────────────────"
        for sn in $completed_stages; do
            if [ -n "$(_audit_stage_ts "$events_log" "$sn")" ]; then
                echo "  ✓ $sn -- telemetry reported"
            else
                echo "  ✗ $sn -- MISSING stage-done telemetry"
                deviations=$((deviations + 1))
            fi
        done
        # Duplicate closures: >1 stage_done boundary for a stage is a silent
        # re-run (attribution is already downgraded on non-monotonic boundaries;
        # surface the duplicate itself as a deviation).
        for sn in $completed_stages; do
            _dups=$(grep -Ec '"type":"stage_done","stage":"'"$sn"'"' "$events_log" 2>/dev/null || true)
            if [ "${_dups:-0}" -gt 1 ]; then
                echo "  ! $sn -- $_dups stage-done boundaries (duplicate closure / re-run)"
                deviations=$((deviations + 1))
            fi
        done
        if [ -f "$events_log" ] && command -v jq >/dev/null 2>&1; then
            echo ""
            echo "Per-stage token usage:"
            _run_stage_records "$events_log" | while IFS= read -r line; do
                _s=$(printf '%s' "$line" | grep -o '"stage":"[^"]*"' | sed 's/"stage":"//;s/"$//' 2>/dev/null || echo "?")
                _ti=$(printf '%s' "$line" | grep -o '"tokens_in":[0-9null]*' | sed 's/"tokens_in"://' 2>/dev/null || echo "?")
                _to=$(printf '%s' "$line" | grep -o '"tokens_out":[0-9null]*' | sed 's/"tokens_out"://' 2>/dev/null || echo "?")
                _m=$(printf '%s' "$line" | grep -o '"model":"[^"]*"' | sed 's/"model":"//;s/"$//' 2>/dev/null || echo "?")
                _src=$(printf '%s' "$line" | grep -o '"counts":"[^"]*"' | sed 's/"counts":"//;s/"$//' 2>/dev/null || echo "?")
                echo "  $_s: in=$_ti out=$_to model=$_m [$_src]"
            done
        elif [ ! -f "$events_log" ]; then
            echo "  No events.jsonl -- stage-done was never called for any stage"
            deviations=$((deviations + 1))
        fi
        echo ""
    fi

    # --- Check 2: expected tools vs actual tool calls ---
    # Expected side: an explicit <!-- ICM-TOOLS expect="..." --> declaration in the
    # frozen contract. Each whitespace-separated token is an ERE matched unanchored
    # against actual harness tool names (same semantics as ICM-GATE tools=).
    # Contracts without the declaration fall back to scraping `tools/...` mentions
    # from prose. Actual side: harness tool names recorded by gate-check --tool
    # invocations in tool-calls.jsonl; scripts run directly via bash are not logged.
    telemetry_log="$run_dir/../../../telemetry/tool-calls.jsonl"
    # Run id 2026-06-15_08-18-37 -> ISO-Z 2026-06-15T08:18:37Z so string compares
    # against event ts (all written with a trailing Z) are value-based, not reliant
    # on length sorting. The old form left HH-MM dashed and dropped the Z.
    run_start=$(printf '%s' "$latest" | sed 's/_/T/; s/\([0-9][0-9]\)-\([0-9][0-9]\)-\([0-9][0-9]\)$/\1:\2:\3Z/')
    # Run-wide tools only tell "adapter recorded nothing" (cannot verify) apart
    # from "tool genuinely absent from this stage". Per-stage matching uses the
    # windowed sets below.
    actual_tools=""
    if [ -f "$telemetry_log" ]; then
        _allwin=$(awk -v start="$run_start" -F '"' '/"ts":"/ { if ($4 >= start) print }' "$telemetry_log" 2>/dev/null || true)
        actual_tools=$( { printf '%s\n' "$_allwin" | grep -o '"--tool","[^"]*"' | sed 's/"--tool","//;s/"$//' || true; \
                          printf '%s\n' "$_allwin" | grep -o -- '--tool [^" ]*' | sed 's/--tool //' || true; } | sort -u)
    fi

    # Per-stage attribution is trustworthy only when every stage has a stage-done
    # boundary AND the boundaries strictly increase in stage order. A skipped
    # stage-done (gap) or a re-run (duplicate, non-monotonic) makes the windows
    # ambiguous and could silently mis-credit a tool to the wrong stage, so we
    # detect that here and downgrade ICM-TOOLS to "unreliable, not counted" rather
    # than risk a false pass/fail. Clean monotonic runs keep the strict check.
    attr_reliable=1
    attr_reason=""
    _pp_prev=""
    for stage_dir in "$run_dir"/[0-9]*/; do
        [ -d "$stage_dir" ] || continue
        [ -f "$stage_dir/CONTEXT.md" ] || continue
        _pp_ts=$(_audit_stage_ts "$events_log" "$(basename "$stage_dir")")
        if [ -z "$_pp_ts" ]; then
            attr_reliable=0; attr_reason="a stage has no stage-done boundary"
        elif [ -n "$_pp_prev" ] && ! _ts_lt "$_pp_prev" "$_pp_ts"; then
            attr_reliable=0; attr_reason="stage-done boundaries are non-monotonic (stage re-run?)"
        fi
        [ -n "$_pp_ts" ] && _pp_prev="$_pp_ts"
    done

    _prev_ts="$run_start"
    _stage_idx=0
    _enforce_expected=""
    for stage_dir in "$run_dir"/[0-9]*/; do
        [ -d "$stage_dir" ] || continue
        stage_name=$(basename "$stage_dir")
        ctx="$stage_dir/CONTEXT.md"
        [ -f "$ctx" ] || continue
        _stage_idx=$((_stage_idx + 1))

        icm_tools=$(grep -o '<!-- ICM-TOOLS expect="[^"]*"' "$ctx" 2>/dev/null | head -1 | sed 's/.*expect="//;s/"$//' || true)
        legacy=""
        if [ -z "$icm_tools" ]; then
            legacy=$(grep -Eo '`?(bash )?tools/[^`" ]+(\.sh)?`?' "$ctx" 2>/dev/null | tr -d '`' | sort -u || true)
        fi
        gates=$(grep -Eo 'run="(tools/)?[^"]+"' "$ctx" 2>/dev/null | sed 's/run="//;s/"$//' | sort -u || true)
        if [ -n "$icm_tools" ] || [ -n "$gates" ]; then _enforce_expected=1; fi

        # Per-stage window (prev boundary, this stage-done ts]; lower bound is
        # inclusive only for the first stage (absorbs same-second init).
        _this_ts=$(_audit_stage_ts "$events_log" "$stage_name")
        stage_tools=""
        win_note=""
        if [ -z "$_this_ts" ]; then
            win_note="no stage-done -- cannot attribute tools to this stage"
        else
            _li=0; [ "$_stage_idx" -eq 1 ] && _li=1
            [ "$_prev_ts" = "$_this_ts" ] && win_note="zero-width window (stage-done same second as previous) -- attribution unreliable"
            stage_tools=$(_audit_tools_in_window "$telemetry_log" "$_prev_ts" "$_this_ts" "$_li")
            _prev_ts="$_this_ts"
        fi

        if [ -n "$icm_tools" ] || [ -n "$legacy" ] || [ -n "$gates" ]; then
            echo "STAGE $stage_name -- TOOL CALL CHECK"
            echo "──────────────────────────────────────"

            if [ -n "$icm_tools" ]; then
                echo "Expected tools (ICM-TOOLS):"
                for tool in $icm_tools; do
                    if [ -z "$actual_tools" ]; then
                        echo "  ? $tool -- no gate-check records in run (enforcement adapter not registered?)"
                    elif [ "$attr_reliable" -eq 0 ]; then
                        echo "  ? $tool -- per-stage attribution unreliable ($attr_reason); not counted"
                    elif { printf '%s\n' "$stage_tools"; printf '%s\n' "$stage_tools" | while IFS= read -r _nt; do [ -n "$_nt" ] || continue; _normalize_tool "$_nt"; done; } | grep -Eq -- "$tool"; then
                        echo "  ✓ $tool"
                    else
                        echo "  ✗ $tool -- not seen in this stage's window"
                        deviations=$((deviations + 1))
                    fi
                done
            fi

            if [ -n "$legacy" ]; then
                echo "Expected tools (prose scrape, declare ICM-TOOLS instead):"
                printf '%s\n' "$legacy" | while IFS= read -r tool; do
                    echo "  $tool"
                done
            fi

            if [ -n "$gates" ]; then
                echo "Gate checkers:"
                printf '%s\n' "$gates" | while IFS= read -r gate; do
                    echo "  $gate"
                done
            fi

            [ -n "$win_note" ] && echo "  ! $win_note"

            if [ -f "$telemetry_log" ]; then
                echo "Actual tools in stage window:"
                if [ -n "$stage_tools" ]; then
                    printf '%s\n' "$stage_tools" | while IFS= read -r t; do
                        echo "  $t"
                    done
                else
                    echo "  (none in this stage's window)"
                fi
            else
                echo "No telemetry available (tool-calls.jsonl not found)"
                deviations=$((deviations + 1))
            fi
            echo ""
        fi
    done

    # Trailing gate-check calls after the last stage-done boundary (informational;
    # e.g. post-run tool use). Not attributed to any stage, not a deviation.
    if [ -f "$telemetry_log" ] && [ -n "$actual_tools" ]; then
        trailing=$(_audit_tools_in_window "$telemetry_log" "$_prev_ts" "9999-12-31T23:59:59Z" 0)
        if [ -n "$trailing" ]; then
            echo "Trailing tools (after last stage-done; not attributed to any stage):"
            printf '%s\n' "$trailing" | while IFS= read -r t; do
                echo "  $t"
            done
            echo ""
        fi
    fi

    # --- Check 3: fail-open gate events (gate-hook could not run icm.sh) ---
    # Calls where gates were NOT enforced because gate-check crashed. A silent
    # fail-open is enforcement theater, so surface it always; under --strict it
    # counts as a deviation. run_start was computed in Check 2.
    hook_errors_log="$run_dir/../../../telemetry/hook-errors.jsonl"
    if [ -f "$hook_errors_log" ] && [ -n "${run_start:-}" ]; then
        fo_count=$(awk -v start="$run_start" -F '"' '/"event":"gate-check-error"/ { if ($4 >= start) c++ } END { print c+0 }' "$hook_errors_log" 2>/dev/null || echo 0)
        if [ "$fo_count" -gt 0 ]; then
            echo "FAIL-OPEN EVENTS"
            echo "──────────────────────────────────────"
            echo "  ! $fo_count gate-check error(s) in run window -- gates were NOT enforced on those calls"
            echo "  (see .icm/telemetry/hook-errors.jsonl)"
            echo ""
            deviations=$((deviations + fo_count))
        fi
    fi

    # --- Check 4: gates/expected tools declared but no enforcement records ---
    # An empty actual_tools means no gate-check --tool record exists in the run
    # window, i.e. no enforcement adapter (hook / pi extension) fired. If the run
    # also declares ICM-GATE gates or ICM-TOOLS expectations, those were advisory
    # only -- surface it loudly and count it so the summary cannot read as a pass.
    if [ -n "${_enforce_expected:-}" ] && [ -z "$actual_tools" ]; then
        echo "GATES NOT ENFORCED"
        echo "──────────────────────────────────────"
        echo "  ! run declares gates / expected tools but no gate-check records exist"
        echo "  ! enforcement hook is not installed -- gates were ADVISORY ONLY, not enforced"
        echo "  (install: installer.sh --hooks)"
        echo ""
        deviations=$((deviations + 1))
    fi

    # --- Check 5: execution-spec (ICM-CALL) verification ---
    # A stage may declare <!-- ICM-CALL tool="T" args="a,b,c" -->: the tool T (its
    # mcp__ wrapper stripped for matching) must have been called within the stage
    # window with every named arg field present in its input. Verifies the small
    # executor actually filled the spec, not just that some tool ran. Reads the
    # captured args from tool-args.jsonl. An "args" entry of the form "field@path"
    # additionally requires that arg's value to equal the run-root-relative file's
    # content -- verifying the executor glued the right prior-stage output into the
    # call, not just that the field is present.
    args_log="$run_dir/../../../telemetry/tool-args.jsonl"
    if command -v jq >/dev/null 2>&1; then
        _ec_prev="$run_start"
        for stage_dir in "$run_dir"/[0-9]*/; do
            [ -d "$stage_dir" ] || continue
            ec_ctx="$stage_dir/CONTEXT.md"
            [ -f "$ec_ctx" ] || continue
            ec_stage=$(basename "$stage_dir")
            ec_this=$(_audit_stage_ts "$events_log" "$ec_stage")
            ec_line=$(grep -o '<!-- ICM-CALL [^>]*-->' "$ec_ctx" 2>/dev/null | head -1 || true)
            if [ -z "$ec_line" ]; then
                if [ -n "$ec_this" ]; then _ec_prev="$ec_this"; fi
                continue
            fi
            ec_tool=$(gate_attr "$ec_line" tool)
            ec_args=$(gate_attr "$ec_line" args)
            echo "STAGE $ec_stage -- EXECUTION SPEC (ICM-CALL)"
            echo "──────────────────────────────────────"
            if [ -z "$ec_tool" ]; then
                echo "  ✗ malformed ICM-CALL (need tool=\"...\")"
                deviations=$((deviations + 1))
            elif [ -z "$ec_this" ]; then
                echo "  ? $ec_tool -- stage not closed, cannot verify"
            elif [ ! -f "$args_log" ]; then
                echo "  ✗ $ec_tool -- no tool-args.jsonl (enforcement adapter not registered?)"
                deviations=$((deviations + 1))
            else
                # The matching call: last record for this tool (mcp__ wrapper
                # stripped) within the stage window, or empty.
                ec_rec=$(jq -cs --arg tool "$ec_tool" --arg lo "$_ec_prev" --arg hi "$ec_this" '
                    [ .[] | select(.ts > $lo and .ts <= $hi)
                          | select(.tool == $tool or (.tool | gsub("^mcp__.*__"; "")) == $tool) ]
                    | last // empty
                ' "$args_log" 2>/dev/null || echo "")
                if [ -z "$ec_rec" ]; then
                    echo "  ✗ $ec_tool -- not called in this stage's window"
                    deviations=$((deviations + 1))
                else
                    ec_bad=""
                    ec_oldifs=$IFS; IFS=,
                    for ec_a in $ec_args; do
                        IFS=$ec_oldifs
                        ec_field=$(printf '%s' "${ec_a%%@*}" | sed 's/^[[:space:]]*//;s/[[:space:]]*$//')
                        if [ -z "$ec_field" ]; then IFS=,; continue; fi
                        if ! printf '%s' "$ec_rec" | jq -e --arg f "$ec_field" '(.input // {}) | has($f)' >/dev/null 2>&1; then
                            ec_bad="$ec_bad missing:$ec_field"
                        elif [ "$ec_a" != "${ec_a%%@*}" ]; then
                            ec_path=$(printf '%s' "${ec_a#*@}" | sed 's/^[[:space:]]*//;s/[[:space:]]*$//')
                            ec_actual=$(printf '%s' "$ec_rec" | jq -r --arg f "$ec_field" '.input[$f] // ""')
                            if [ ! -f "$run_dir/$ec_path" ]; then
                                ec_bad="$ec_bad nofile:$ec_path"
                            else
                                ec_want=$(cat "$run_dir/$ec_path")
                                if [ "$ec_actual" != "$ec_want" ]; then ec_bad="$ec_bad value:$ec_field"; fi
                            fi
                        fi
                        IFS=,
                    done
                    IFS=$ec_oldifs
                    if [ -z "$ec_bad" ]; then
                        echo "  ✓ $ec_tool called with args: $ec_args"
                    else
                        echo "  ✗ $ec_tool --$ec_bad"
                        deviations=$((deviations + 1))
                    fi
                fi
            fi
            echo ""
            if [ -n "$ec_this" ]; then _ec_prev="$ec_this"; fi
        done
    fi

    echo "──────────────────────────────────────"
    echo "Deviations: $deviations (review manually for false positives)"
    if [ "$complete" = false ]; then
        echo "Run is incomplete -- audit may be partial."
    fi
    if [ "$strict" -eq 1 ] && [ "$deviations" -gt 0 ]; then
        echo "STRICT: $deviations deviation(s) -- failing." >&2
        exit 1
    fi
}

# ---- cost ----
# Per-stage token summary for a run: the four fields stage_done/reify carry
# (new-input / output / cache-creation / cache-read), plus totals. Cost itself is
# intentionally NOT computed (downstream prices the tokens); this sums what
# telemetry already has, so stage 06 can print one calibration line in the report.
cmd_cost() {
    ws=""
    while [ $# -gt 0 ]; do
        case "$1" in
            --cwd) cd "$2"; shift 2 ;;
            *) ws="$1"; shift ;;
        esac
    done
    [ -n "$ws" ] || { echo "cost requires workspace name" >&2; exit 1; }
    latest=$(latest_run "$ws")
    if [ -z "$latest" ]; then
        _cwd_hint "$ws"
        echo "no runs for $ws" >&2
        exit 1
    fi
    _cost_ev=".icm/$ws/$latest/telemetry/events.jsonl"
    if [ ! -f "$_cost_ev" ]; then
        echo "no events for $ws/$latest" >&2
        exit 1
    fi
    echo "COST: $ws / $latest"
    echo "=========================================="
    _run_stage_records "$_cost_ev" | awk '
      function val(key,   p, i, s){
        p = "\"" key "\":"
        i = index($0, p); if (i == 0) return "null"
        s = substr($0, i + length(p)); sub(/[,}].*/, "", s); gsub(/"/, "", s)
        return s
      }
      function n(s){ return (s=="null"||s=="") ? 0 : s+0 }
      BEGIN{ printf "  %-22s %9s %9s %10s %10s  %s\n","stage","in","out","cache_cr","cache_rd","counts" }
      {
        st=val("stage"); ti=val("tokens_in"); to=val("tokens_out")
        cc=val("cache_creation"); cr=val("cache_read"); ct=val("counts")
        printf "  %-22s %9s %9s %10s %10s  %s\n", st, ti, to, cc, cr, ct
        TI+=n(ti); TO+=n(to); CC+=n(cc); CR+=n(cr)
      }
      END{ printf "  %-22s %9d %9d %10d %10d\n","TOTAL",TI,TO,CC,CR }'
}

# ---- seal / verify-seal ----
# Seal: append a digest line for the latest run's evidence files to
# .icm-seals.log at the project root, which is committable while .icm/ stays
# gitignored. Tamper EVIDENCE, not prevention: the log is a plain file until
# committed, and local git history is rewritable. Trust comes from committing
# the log and pushing; after that, tampering means a visible diff.
_seal_files() {
    for sf in .manifest telemetry/run.json telemetry/events.jsonl; do
        [ -f "$1/$sf" ] && echo "$sf"
    done
    # Stage output artifacts: the work product. Sealing these anchors a graded
    # or reviewed output to a tamper-evident digest, not just the contract and
    # telemetry. Sorted per stage so the seal-log line is deterministic.
    for sd in "$1"/[0-9]*/; do
        [ -d "$sd"output ] || continue
        find "$sd"output -type f 2>/dev/null | LC_ALL=C sort | while IFS= read -r of; do
            printf '%s\n' "${of#"$1"/}"
        done
    done
    return 0
}

cmd_seal() {
    ws=""; force=0
    while [ $# -gt 0 ]; do
        case "$1" in
            --cwd) cd "$2"; shift 2 ;;
            --force) force=1; shift ;;
            *) ws="$1"; shift ;;
        esac
    done
    if [ -z "$ws" ]; then
        echo "seal requires workspace name" >&2
        exit 1
    fi
    latest=$(latest_run "$ws")
    if [ -z "$latest" ]; then
        _cwd_hint "$ws"
        echo "no runs for $ws" >&2
        exit 1
    fi
    run_dir=".icm/$ws/$latest"

    # Seal integrity: a seal is the tamper-evidence capstone, so refuse to
    # notarize a run that is incomplete or carries fabricated progress markers -
    # the 2026-07-02 premature seal notarized 05/06 stage_dones that were
    # estimated with an empty model. Refusals: (a) a declared stage with no
    # stage-done/reify boundary; (b) a stage-done with an empty model; (c) a
    # stage-done with estimated (non-transcript) counts. --force overrides and
    # the seal line records "forced":true so the override is itself auditable.
    _events="$run_dir/telemetry/events.jsonl"
    if [ "$force" -eq 0 ]; then
        _seal_refuse=""
        for _sd in "$run_dir"/[0-9]*/; do
            [ -d "$_sd" ] || continue
            _sn=$(basename "$_sd")
            if ! grep -Eq '"type":"(stage_done|reify)","stage":"'"$_sn"'"' "$_events" 2>/dev/null; then
                _seal_refuse="$_seal_refuse\n  - stage $_sn has no stage-done (run incomplete)"
            fi
        done
        if grep '"type":"stage_done"' "$_events" 2>/dev/null | grep -q '"model":""'; then
            _seal_refuse="$_seal_refuse\n  - a stage-done has an empty model (fabricated marker)"
        fi
        if grep '"type":"stage_done"' "$_events" 2>/dev/null | grep -q '"counts":"estimated"'; then
            _seal_refuse="$_seal_refuse\n  - a stage-done has estimated (non-transcript) token counts"
        fi
        if [ -n "$_seal_refuse" ]; then
            printf 'seal: refusing to seal %s/%s:%b\n' "$ws" "$latest" "$_seal_refuse" >&2
            echo "  resolve the transcript, or re-seal with --force (records forced:true)." >&2
            exit 1
        fi
    fi

    entries=""
    for sf in $(_seal_files "$run_dir"); do
        h=$( (cd "$run_dir" && sha_file "$sf") | awk '{print $1}')
        if [ -z "$entries" ]; then
            entries="\"$sf\":\"$h\""
        else
            entries="$entries,\"$sf\":\"$h\""
        fi
    done
    if [ -z "$entries" ]; then
        echo "seal: no evidence files in $run_dir" >&2
        exit 1
    fi
    # "forced":true goes BEFORE "sealed" so verify-seal's `s/.*"sealed":{//;s/}}$//`
    # parse is untouched (a trailing field would break the `}}$` anchor).
    _forced_field=""
    [ "$force" -eq 1 ] && _forced_field='"forced":true,'
    printf '{"ts":"%s","workspace":"%s","run_id":"%s",%s"sealed":{%s}}\n' \
        "$(date -u +%Y-%m-%dT%H:%M:%SZ)" "$ws" "$latest" "$_forced_field" "$entries" >> .icm-seals.log
    _forced_note=""
    [ "$force" -eq 1 ] && _forced_note=" (forced)"
    echo "sealed $ws/$latest -> .icm-seals.log (commit this file)$_forced_note"
}

# Verify one seal-log line. $1=line $2=workspace $3=run_id. Prints SEAL OK
# or SEAL MISMATCH lines; returns 1 on any mismatch.
_verify_seal_line() {
    vs_line=$1
    vs_ws=$2
    vs_run_id=$3
    vs_run_dir=".icm/$vs_ws/$vs_run_id"
    vs_sealed=$(printf '%s' "$vs_line" | sed 's/.*"sealed":{//;s/}}$//')
    vs_bad=0
    for vs_pair in $(printf '%s' "$vs_sealed" | tr ',' '\n'); do
        vs_f=$(printf '%s' "$vs_pair" | sed 's/^"//;s/":".*//')
        vs_want=$(printf '%s' "$vs_pair" | sed 's/.*":"//;s/"$//')
        if [ ! -f "$vs_run_dir/$vs_f" ]; then
            echo "SEAL MISMATCH $vs_ws/$vs_run_id $vs_f: file missing"
            vs_bad=1
            continue
        fi
        vs_got=$( (cd "$vs_run_dir" && sha_file "$vs_f") | awk '{print $1}')
        if [ "$vs_got" != "$vs_want" ]; then
            echo "SEAL MISMATCH $vs_ws/$vs_run_id $vs_f: sha256 differs from sealed digest"
            vs_bad=1
        fi
    done
    if [ "$vs_bad" -eq 0 ]; then
        echo "SEAL OK $vs_ws/$vs_run_id"
        return 0
    fi
    return 1
}

cmd_verify_seal() {
    ws=""
    all=0
    while [ $# -gt 0 ]; do
        case "$1" in
            --all) all=1; shift ;;
            --cwd) cd "$2"; shift 2 ;;
            *) ws="$1"; shift ;;
        esac
    done
    if [ ! -f .icm-seals.log ]; then
        echo "verify-seal: no .icm-seals.log in $PWD" >&2
        exit 1
    fi

    if [ "$all" -eq 1 ]; then
        # Verify the last seal of every (workspace, run) in the log. Runs
        # pruned by clean are reported as skipped, not failed: deleting old
        # evidence is normal lifecycle, altering surviving evidence is not.
        _vs_keys=$(sed -n 's/.*"workspace":"\([^"]*\)","run_id":"\([^"]*\)".*/\1 \2/p' .icm-seals.log | awk '!seen[$0]++')
        if [ -z "$_vs_keys" ]; then
            echo "verify-seal: no seals in .icm-seals.log" >&2
            exit 1
        fi
        _vs_status=0
        while IFS=' ' read -r _vs_w _vs_r; do
            [ -n "$_vs_w" ] || continue
            if [ ! -d ".icm/$_vs_w/$_vs_r" ]; then
                echo "SEAL SKIP $_vs_w/$_vs_r: run pruned"
                continue
            fi
            _vs_l=$(grep "\"workspace\":\"$_vs_w\",\"run_id\":\"$_vs_r\"" .icm-seals.log | tail -1)
            _verify_seal_line "$_vs_l" "$_vs_w" "$_vs_r" || _vs_status=1
        done <<ICM_VS_EOF
$_vs_keys
ICM_VS_EOF
        exit "$_vs_status"
    fi

    if [ -z "$ws" ]; then
        echo "verify-seal requires workspace name (or --all)" >&2
        exit 1
    fi
    latest=$(latest_run "$ws")
    if [ -z "$latest" ]; then
        _cwd_hint "$ws"
        echo "no runs for $ws" >&2
        exit 1
    fi
    line=$(grep "\"workspace\":\"$ws\",\"run_id\":\"$latest\"" .icm-seals.log 2>/dev/null | tail -1 || :)
    if [ -z "$line" ]; then
        echo "verify-seal: no seal recorded for $ws/$latest" >&2
        exit 1
    fi
    if _verify_seal_line "$line" "$ws" "$latest"; then
        exit 0
    fi
    exit 1
}

# ---- gate-check ----
# Print the set of run ids ("<ws>/<run_id>") whose gates are SUSPENDED because an
# open run names them as its --caller parent: the child run is doing the work, so
# the parent's still-open gates must not deny the child's tool calls. Shared by
# gate-check (enforcement) and gate-status (diagnostic) so the two agree.
_suspended_runs() {
    latest_runs | while IFS= read -r sr_r; do
        [ -n "$(_active_stage "$sr_r")" ] || continue
        sr_c=$(_caller_of "$sr_r")
        [ -n "$sr_c" ] || continue
        printf '%s\n' "${sr_c%/*}"
    done | sort -u
}

cmd_gate_check() {
    gc_tool=""
    gc_path=""
    while [ $# -gt 0 ]; do
        case "$1" in
            --tool) gc_tool=$2; shift 2 ;;
            --path) gc_path=$2; shift 2 ;;
            --cwd)  cd "$2"; shift 2 ;;
            *) echo "Unknown gate-check option: $1" >&2; usage ;;
        esac
    done
    if [ -z "$gc_tool" ]; then
        echo "gate-check requires --tool <tool-name>" >&2
        usage
    fi
    [ -d .icm ] || exit 0

    # Caller-scoping for nested runs: a parent run that invoked an open child has
    # its gates suspended (the child does the work). The tamper check still runs
    # for every latest run; only gate evaluation is scoped. See _suspended_runs.
    gc_suspended=$(_suspended_runs)

    gc_out=$(latest_runs | while IFS= read -r gc_run; do
        if [ -n "$gc_suspended" ] && printf '%s\n' "$gc_suspended" | grep -Fxq "${gc_run#.icm/}"; then
            check_run "$gc_run" "$gc_tool" suspend "$gc_path"
        else
            check_run "$gc_run" "$gc_tool" "" "$gc_path"
        fi
    done)
    if [ -n "$gc_out" ]; then
        printf '%s\n' "$gc_out"
        exit 1
    fi
    exit 0
}

# ---- gate-status ----
# Exit 1 iff active runs in cwd declare gates but the hook is registered in no scope.
cmd_gate_status() {
    while [ $# -gt 0 ]; do
        case "$1" in
            --cwd) cd "$2"; shift 2 ;;
            *) echo "Unknown gate-status option: $1" >&2; usage ;;
        esac
    done

    echo "== Gates declared by installed skills ($SKILLS_DIR) =="
    gs_installed=$(find "$SKILLS_DIR" -maxdepth 4 -path '*/stages/*.md' 2>/dev/null | sort | while IFS= read -r gs_md; do
        grep -F '<!-- ICM-GATE ' "$gs_md" 2>/dev/null | while IFS= read -r gs_line; do
            echo "$gs_md"
            echo "  tools: $(gate_attr "$gs_line" tools)"
            echo "  run:   $(gate_attr "$gs_line" run)"
        done
    done)
    if [ -n "$gs_installed" ]; then
        printf '%s\n' "$gs_installed"
    else
        echo "(none)"
    fi

    echo ""
    echo "== Gates in active runs ($PWD/.icm) =="
    gs_gates=$(latest_runs | while IFS= read -r gs_run; do
        for gs_ctx in "$gs_run"/[0-9]*/CONTEXT.md; do
            [ -f "$gs_ctx" ] || continue
            if grep -Fq '<!-- ICM-GATE ' "$gs_ctx" 2>/dev/null; then
                echo "$gs_ctx"
            fi
        done
    done)
    if [ -n "$gs_gates" ]; then
        printf '%s\n' "$gs_gates"
        # Same caller-scoping as enforcement: a parent suspended by an open child
        # is not reported as blocking, so STATE matches what gate-check would do.
        gs_suspended=$(_suspended_runs)
        gs_denies=$(latest_runs | while IFS= read -r gs_run; do
            if [ -n "$gs_suspended" ] && printf '%s\n' "$gs_suspended" | grep -Fxq "${gs_run#.icm/}"; then
                check_run "$gs_run" "" suspend
            else
                check_run "$gs_run" ""
            fi
        done)
        if [ -n "$gs_denies" ]; then
            echo "STATE: BLOCKING"
            printf '%s\n' "$gs_denies"
        else
            echo "STATE: all gates passing"
        fi
    else
        echo "(none)"
    fi

    echo ""
    echo "== Enforcement registration =="
    gs_registered=0
    gs_claude_reg=0
    for gs_settings in "${HOME:-}/.claude/settings.json" ".claude/settings.json" ".claude/settings.local.json"; do
        if [ -f "$gs_settings" ] && grep -q 'gate-hook\.sh' "$gs_settings" 2>/dev/null; then
            echo "REGISTERED      $gs_settings"
            gs_registered=1
            gs_claude_reg=1
        else
            echo "NOT REGISTERED  $gs_settings"
        fi
    done
    for gs_ext in "${HOME:-}/.pi/agent/extensions/icm-gate.ts" ".pi/extensions/icm-gate.ts"; do
        if [ -e "$gs_ext" ]; then
            echo "REGISTERED      $gs_ext"
            gs_registered=1
        else
            echo "NOT REGISTERED  $gs_ext"
        fi
    done

    if [ -n "$gs_gates" ]; then
        if [ "$gs_registered" -eq 0 ]; then
            echo ""
            echo "RESULT: FAIL - active runs declare gates but enforcement is not registered in any scope"
            exit 1
        fi
        # Registration in another harness is not enforcement in this one.
        if [ -n "${CLAUDECODE:-}" ] && [ "$gs_claude_reg" -eq 0 ]; then
            echo ""
            echo "RESULT: FAIL - running in Claude Code but gate-hook.sh is not registered in any Claude scope"
            exit 1
        fi
    fi
    exit 0
}

# ---- children ----
# List runs whose run.json records <ws>/<run_id> as their --caller. Read-only,
# top-down view of the explicit links recorded on each child. Direct children
# only (a grandchild's caller is its parent, not this run).
cmd_children() {
    cc_ws=""; cc_run=""
    while [ $# -gt 0 ]; do
        case "$1" in
            --cwd) cd "$2"; shift 2 ;;
            *) if [ -z "$cc_ws" ]; then cc_ws="$1"; else cc_run="$1"; fi; shift ;;
        esac
    done
    if [ -z "$cc_ws" ]; then
        echo "children requires workspace name" >&2
        exit 1
    fi
    [ -n "$cc_run" ] || cc_run=$(latest_run "$cc_ws")
    if [ -z "$cc_run" ]; then
        echo "no runs for $cc_ws" >&2
        exit 1
    fi
    cc_parent="$cc_ws/$cc_run"
    cc_out=""
    if [ -d .icm ]; then
        cc_out=$(find .icm -path '*/telemetry/run.json' 2>/dev/null | while IFS= read -r cc_rj; do
            cc_caller=$(grep '"caller"' "$cc_rj" 2>/dev/null | sed 's/.*"caller": *"\([^"]*\)".*/\1/')
            case "$cc_caller" in
                ("$cc_parent"/*)
                    cc_child=${cc_rj%/telemetry/run.json}
                    cc_child=${cc_child#.icm/}
                    printf '  %s (from stage: %s)\n' "$cc_child" "${cc_caller##*/}" ;;
            esac
        done)
    fi
    if [ -z "$cc_out" ]; then
        echo "no children for $cc_parent"
    else
        echo "Children of $cc_parent:"
        printf '%s\n' "$cc_out"
    fi
}

# ---- main ----
if [ $# -lt 1 ]; then
    usage
fi

_log_start "$0" "$@"

cmd=$1
shift

_trap_exit() {
    _log_end $?
}
trap _trap_exit EXIT

case "$cmd" in
    gate-check)  cmd_gate_check "$@" ;;
    gate-status) cmd_gate_status "$@" ;;
    init)   [ $# -ge 1 ] || usage; cmd_init "$@" ;;
    next)   [ $# -ge 1 ] || usage; cmd_next "$1" ;;
    list)   [ $# -ge 1 ] || usage; cmd_list "$1" ;;
    diff)   [ $# -ge 1 ] || usage; cmd_diff "$1" ;;
    stages) [ $# -ge 1 ] || usage; cmd_stages "$1" ;;
    catalog) cmd_catalog ;;
    new-skill) cmd_new_skill "$@" ;;
    eval) [ $# -ge 1 ] || usage; cmd_eval "$1" ;;
    clean)  [ $# -ge 1 ] || usage; ws=$1; shift; cmd_clean "$ws" "$@" ;;
    telemetry) cmd_telemetry "$@" ;;
    stage-done) cmd_stage_done "$@" ;;
    reify-telemetry) cmd_reify_telemetry "$@" ;;
    audit) cmd_audit "$@" ;;
    cost) [ $# -ge 1 ] || usage; cmd_cost "$@" ;;
    seal) cmd_seal "$@" ;;
    verify-seal) cmd_verify_seal "$@" ;;
    children) cmd_children "$@" ;;
    version|--version|-v) echo "icm.sh $ICM_VERSION" ;;
    help|--help|-h) usage ;;
    *)
        echo "Unknown command: $cmd" >&2
        usage
        ;;
esac
