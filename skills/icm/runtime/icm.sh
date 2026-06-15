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
#   icm.sh telemetry <workspace> --model <m> --tokens-in <n> --tokens-out <n> --cost <c> [--cwd <dir>]
#   icm.sh stage-done <workspace> --stage <name> --model <m> [--tokens-in <n> --tokens-out <n>] [--full] [--transcript <path>] [--cwd <dir>]
#   icm.sh reify-telemetry <workspace> [--cwd <dir>] [--transcript <path>]
#   icm.sh audit <workspace> [--strict] [--cwd <dir>]  --strict exits 1 if deviations>0
#   icm.sh seal <workspace> [--cwd <dir>]         Append run evidence digests to .icm-seals.log
#   icm.sh verify-seal <workspace>|--all [--cwd <dir>]  Recompute digests against last seal(s); exit 1 on mismatch

set -eu

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
    echo "       icm.sh children <workspace> [<run_id>]" >&2
    echo "       icm.sh gate-check --tool <tool-name> [--cwd <dir>]" >&2
    echo "       icm.sh gate-status [--cwd <dir>]" >&2
    echo "       icm.sh telemetry <workspace> --model <m> --tokens-in <n> --tokens-out <n> --cost <c> [--cwd <dir>]" >&2
    echo "       icm.sh stage-done <workspace> --stage <name> --model <m> [--tokens-in <n> --tokens-out <n>] [--full] [--transcript <path>] [--cwd <dir>]" >&2
    echo "       icm.sh reify-telemetry <workspace> [--cwd <dir>] [--transcript <path>]" >&2
    echo "       icm.sh audit <workspace> [--strict] [--cwd <dir>]" >&2
    echo "       icm.sh seal <workspace> [--cwd <dir>]" >&2
    echo "       icm.sh verify-seal <workspace>|--all [--cwd <dir>]" >&2
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
# Preference: path recorded by gate-hook.sh (authoritative, from the harness),
# then harness session dirs. Claude Code encodes the project cwd into the
# transcript dir name (/ and . become -), so prefer that dir when it exists;
# otherwise scan all sessions. Pick the newest candidate by mtime, not find
# order: with parallel sessions the first hit is arbitrary. Prints the path,
# or nothing when no transcript is found. Warnings go to stderr.
find_transcript() {
    ft_run=$1
    if [ -f ".icm/telemetry/transcript-path" ]; then
        ft_p=$(head -1 ".icm/telemetry/transcript-path" 2>/dev/null || :)
        if [ -n "$ft_p" ] && [ -f "$ft_p" ]; then
            echo "$ft_p"
            return 0
        fi
    fi
    ft_search=""
    if [ -n "${CLAUDECODE:-}" ]; then
        ft_munged=$(pwd | sed 's,[/.],-,g')
        if [ -d "${HOME}/.claude/projects/$ft_munged" ]; then
            ft_search="${HOME}/.claude/projects/$ft_munged"
        else
            ft_search="${HOME}/.claude/projects"
        fi
    elif [ -d "${HOME}/.pi" ]; then
        ft_search="${HOME}/.pi/agent/sessions"
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
    [ -z "$ft_found" ] || echo "$ft_found"
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

# Sum a transcript_usage stream into "tokens_in tokens_out" (or "null null").
# tokens_in includes cache reads/writes: it is the context actually fed to the
# model, not just the uncached slice.
usage_sums() {
    jq -r '"\(.tokens_in + .cache_creation + .cache_read) \(.tokens_out)"' 2>/dev/null \
        | awk '{i+=$1; o+=$2} END {if (NR==0) print "null null"; else print i, o}'
}

# Extract a double-quoted attribute value from an ICM-GATE line. $1=line $2=attr name.
# Values must be double-quoted, single-line, with no embedded double quotes.
gate_attr() {
    printf '%s\n' "$1" | sed -n "s/.*$2=\"\([^\"]*\)\".*/\1/p"
}

# Print the latest run dir per workspace under ./.icm. Handles both layouts
# (.icm/<ws>/<ts> and namespaced .icm/<ns>/<ws>/<ts>) by matching the timestamp
# format cmd_init writes, then keeping the lexically newest child per parent.
latest_runs() {
    [ -d .icm ] || return 0
    find .icm -mindepth 2 -maxdepth 3 -type d \
        -name '[0-9][0-9][0-9][0-9]-[0-9][0-9]-[0-9][0-9]_[0-9][0-9]-[0-9][0-9]-[0-9][0-9]' \
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

# Evaluate one run's frozen gates. $1=run dir, $2=tool name ("" = evaluate every
# gate regardless of its tools regex, used by gate-status). Prints DENY lines on
# stdout (first line is the headline); silent when nothing matches or all pass.
# Fails closed: tampered/missing manifest, malformed gate lines, and invalid
# regexes all deny.
check_run() {
    cr_run=$1
    cr_tool=$2
    cr_ws=${cr_run%/*}
    cr_ws=${cr_ws#.icm/}
    cr_ts=${cr_run##*/}

    if [ -f "$cr_run/.manifest" ]; then
        if ! vm_bad=$(verify_manifest "$cr_run"); then
            echo "DENY $cr_ws $cr_ts $vm_bad: contract tampered (sha256 mismatch with .manifest)"
            return 0
        fi
    fi

    # One grep across all frozen contracts (runs on every hooked tool call).
    # /dev/null forces the "path:" prefix even with a single match file.
    grep -F '<!-- ICM-GATE ' "$cr_run"/[0-9]*/CONTEXT.md /dev/null 2>/dev/null \
        | while IFS= read -r cr_hit; do
            cr_ctx=${cr_hit%%:*}
            cr_line=${cr_hit#*:}
            cr_stage_dir=${cr_ctx%/CONTEXT.md}
            cr_stage=${cr_stage_dir##*/}
            cr_tools=$(gate_attr "$cr_line" tools)
            cr_runcmd=$(gate_attr "$cr_line" run)
            if [ -z "$cr_tools" ] || [ -z "$cr_runcmd" ]; then
                echo "DENY $cr_ws $cr_ts $cr_stage: malformed ICM-GATE line (need tools=\"...\" and run=\"...\")"
                continue
            fi
            if [ -n "$cr_tool" ]; then
                cr_rc=0
                printf '%s\n' "$cr_tool" | grep -Eq -- "$cr_tools" || cr_rc=$?
                if [ "$cr_rc" -ge 2 ]; then
                    echo "DENY $cr_ws $cr_ts $cr_stage: invalid tools regex: $cr_tools"
                    continue
                fi
                [ "$cr_rc" -eq 0 ] || continue
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

# ---- init ----
cmd_init() {
    ws=""; caller=""
    while [ $# -gt 0 ]; do
        case "$1" in
            --caller) caller="$2"; shift 2 ;;
            *) ws="$1"; shift ;;
        esac
    done
    [ -n "$ws" ] || usage
    ws_dir=$(find_workspace "$ws")
    stages_dir="$ws_dir/stages"

    ts=$(date -u +%Y-%m-%d_%H-%M-%S)
    run_dir=".icm/$ws/$ts"

    mkdir -p "$run_dir"

    # Create telemetry directories (per-run + global tool-calls.jsonl)
    mkdir -p "$run_dir/telemetry"
    mkdir -p ".icm/telemetry"

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
    (
        cd "$run_dir"
        for ctx in [0-9]*/CONTEXT.md; do
            [ -f "$ctx" ] || continue
            sha_file "$ctx"
        done
        if [ -d checks ]; then
            find checks -type f | sort | while IFS= read -r cf; do
                sha_file "$cf"
            done
        fi
        if [ -d tools ]; then
            find tools -type f | sort | while IFS= read -r tf; do
                sha_file "$tf"
            done
        fi
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

    # Rotate the shared tool-call log: the wide hook matcher writes one line
    # per tool call, which is unbounded in long-lived projects. Audit pruned
    # runs before cleaning; rotation drops their actual-tool records.
    _tc_log=".icm/telemetry/tool-calls.jsonl"
    if [ -f "$_tc_log" ]; then
        _tc_lines=$(wc -l < "$_tc_log" | tr -d ' ')
        if [ "$_tc_lines" -gt 10000 ]; then
            tail -n 10000 "$_tc_log" > "$_tc_log.tmp" && mv "$_tc_log.tmp" "$_tc_log"
            echo "Rotated tool-calls.jsonl: kept last 10000 of $_tc_lines lines."
        fi
    fi

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

# ---- telemetry ----
# Write a completed-run summary to the global telemetry file.
# Called by workspace skills after all stages complete.
cmd_telemetry() {
    ws=""; model=""; tokens_in=""; tokens_out=""; cost=""
    while [ $# -gt 0 ]; do
        case "$1" in
            --model) model="$2"; shift 2 ;;
            --tokens-in) tokens_in="$2"; shift 2 ;;
            --tokens-out) tokens_out="$2"; shift 2 ;;
            --cost) cost="$2"; shift 2 ;;
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
        echo "no runs for $ws" >&2
        exit 1
    fi
    local global_dir="${HOME}/.icm/telemetry"
    mkdir -p "$global_dir"
    local global_file="$global_dir/skill-runs.jsonl"
    local run_cwd
    run_cwd=$(grep '"cwd"' ".icm/$ws/$latest/telemetry/run.json" 2>/dev/null | sed 's/.*"cwd": "\(.*\)".*/\1/' || echo "$PWD")
    local run_caller caller_json
    run_caller=$(grep '"caller"' ".icm/$ws/$latest/telemetry/run.json" 2>/dev/null | sed 's/.*"caller": *"\([^"]*\)".*/\1/' || echo "")
    if [ -n "$run_caller" ]; then caller_json="\"$run_caller\""; else caller_json="null"; fi
    printf '{"ts":"%s","skill":"%s","run_id":"%s","model":"%s","tokens_in":%s,"tokens_out":%s,"cost_est":%s,"cwd":"%s","caller":%s,"log_dir":".icm/%s/%s/telemetry"}\n' \
        "$(date -u +%Y-%m-%dT%H:%M:%SZ)" "$ws" "$latest" "$model" "$tokens_in" "$tokens_out" "$cost" "$run_cwd" "$caller_json" "$ws" "$latest" \
        >> "$global_file"
    echo "$global_file"
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
    # Stage window: previous boundary in stages.jsonl, else run creation.
    _prev_ts=$(tail -1 "$telemetry_dir/stages.jsonl" 2>/dev/null | grep -o '"ts":"[^"]*"' | head -1 | sed 's/"ts":"//;s/"$//' || :)
    if [ -z "$_prev_ts" ]; then
        _prev_ts=$(grep '"created"' "$telemetry_dir/run.json" 2>/dev/null | sed 's/.*"created": "\(.*\)".*/\1/' || :)
    fi
    [ -n "$_prev_ts" ] || _prev_ts="1970-01-01T00:00:00Z"

    # Snapshot the session transcript for this window while it still exists.
    # Default keeps usage events only (counts, no conversation content) in
    # telemetry/usage.jsonl; --full additionally freezes the raw window into
    # the stage dir. Token counts are computed here when not passed explicitly.
    _counts="estimated"
    if command -v jq >/dev/null 2>&1; then
        [ -n "$transcript" ] || transcript=$(find_transcript "$run_dir")
        if [ -n "$transcript" ] && [ -f "$transcript" ]; then
            _snap=$(mktemp)
            transcript_usage "$transcript" "$_prev_ts" "$_now" \
                | jq -c --arg stage "$stage" '. + {stage: $stage}' 2>/dev/null > "$_snap" || true
            if [ -s "$_snap" ]; then
                cat "$_snap" >> "$telemetry_dir/usage.jsonl"
            fi
            if [ "$tokens_in" = "null" ] && [ "$tokens_out" = "null" ]; then
                _sums=$(usage_sums < "$_snap")
                tokens_in=${_sums% *}
                tokens_out=${_sums#* }
                [ "$tokens_in" = "null" ] || _counts="transcript"
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

    # Write stage boundary. tokens_in/tokens_out default to null.
    _ti_val="$tokens_in"
    _to_val="$tokens_out"
    case "$_ti_val" in ''|null) _ti_val="null" ;; esac
    case "$_to_val" in ''|null) _to_val="null" ;; esac
    printf '{"ts":"%s","stage":"%s","model":"%s","tokens_in":%s,"tokens_out":%s,"counts":"%s"}\n' \
        "$_now" "$stage" "$model" "$_ti_val" "$_to_val" "$_counts" \
        >> "$telemetry_dir/stages.jsonl"

    # Drop a marker so audit can verify this stage boundary was recorded
    mkdir -p "$run_dir/$stage"
    printf '{"stage":"%s","reported_at":"%s"}\n' \
        "$stage" "$(date -u +%Y-%m-%dT%H:%M:%SZ)" \
        > "$run_dir/$stage/.stage-telemetry"

    echo "OK: $stage boundary recorded for $ws/$latest"
}

# ---- reify-telemetry ----
# Post-hoc: read the conversation transcript and fill in exact token
# counts for each stage in the latest run's stages.jsonl.
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
        echo "no runs for $ws" >&2
        exit 1
    fi
    run_dir=".icm/$ws/$latest"
    stages_jsonl="$run_dir/telemetry/stages.jsonl"
    if [ ! -f "$stages_jsonl" ]; then
        echo "no stages.jsonl -- run stage-done first" >&2
        exit 1
    fi

    if [ -z "$transcript" ]; then
        transcript=$(find_transcript "$run_dir")
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
        jq -r '[.ts, .stage] | @tsv' "$stages_jsonl" 2>/dev/null | while IFS='	' read -r _ts _stage; do
            [ -n "$_ts" ] || continue
            _sums=$(transcript_usage "$transcript" "$_prev_ts" "$_ts" | usage_sums)
            _tokens_in=${_sums% *}
            _tokens_out=${_sums#* }
            printf '{"ts":"%s","stage":"%s","model":"(from transcript)","tokens_in":%s,"tokens_out":%s,"counts":"transcript"}\n' \
                "$_ts" "$_stage" "$_tokens_in" "$_tokens_out"
            _prev_ts="$_ts"
        done > "$_tmp"
        if [ -s "$_tmp" ]; then
            mv "$_tmp" "$stages_jsonl"
            echo "reify-telemetry: updated $stages_jsonl with transcript token counts"
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
# Read the stage-done ts for a stage from stages.jsonl ($1) by stage name ($2).
# Empty if the stage was never closed. Last match wins (re-runs append).
_audit_stage_ts() {
    [ -f "$1" ] || return 0
    grep "\"stage\":\"$2\"" "$1" 2>/dev/null | tail -1 \
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

    # --- Check 1: per-stage telemetry completeness ---
    if [ "$complete" = true ]; then
        echo "STAGE TELEMETRY CHECK"
        echo "──────────────────────────────────────"
        stages_jsonl="$run_dir/telemetry/stages.jsonl"
        for sn in $completed_stages; do
            if [ -f "$run_dir/$sn/.stage-telemetry" ]; then
                echo "  ✓ $sn -- telemetry reported"
            else
                echo "  ✗ $sn -- MISSING stage-done telemetry"
                deviations=$((deviations + 1))
            fi
        done
        if [ -f "$stages_jsonl" ]; then
            echo ""
            echo "Per-stage token usage:"
            while IFS= read -r line; do
                _s=$(printf '%s' "$line" | grep -o '"stage":"[^"]*"' | sed 's/"stage":"//;s/"$//' 2>/dev/null || echo "?")
                _ti=$(printf '%s' "$line" | grep -o '"tokens_in":[0-9null]*' | sed 's/"tokens_in"://' 2>/dev/null || echo "?")
                _to=$(printf '%s' "$line" | grep -o '"tokens_out":[0-9null]*' | sed 's/"tokens_out"://' 2>/dev/null || echo "?")
                _m=$(printf '%s' "$line" | grep -o '"model":"[^"]*"' | sed 's/"model":"//;s/"$//' 2>/dev/null || echo "?")
                _src=$(printf '%s' "$line" | grep -o '"counts":"[^"]*"' | sed 's/"counts":"//;s/"$//' 2>/dev/null || echo "?")
                echo "  $_s: in=$_ti out=$_to model=$_m [$_src]"
            done < "$stages_jsonl"
        else
            echo "  No stages.jsonl -- stage-done was never called for any stage"
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
    stages_jsonl="$run_dir/telemetry/stages.jsonl"
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
        _pp_ts=$(_audit_stage_ts "$stages_jsonl" "$(basename "$stage_dir")")
        if [ -z "$_pp_ts" ]; then
            attr_reliable=0; attr_reason="a stage has no stage-done boundary"
        elif [ -n "$_pp_prev" ] && ! _ts_lt "$_pp_prev" "$_pp_ts"; then
            attr_reliable=0; attr_reason="stage-done boundaries are non-monotonic (stage re-run?)"
        fi
        [ -n "$_pp_ts" ] && _pp_prev="$_pp_ts"
    done

    _prev_ts="$run_start"
    _stage_idx=0
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

        # Per-stage window (prev boundary, this stage-done ts]; lower bound is
        # inclusive only for the first stage (absorbs same-second init).
        _this_ts=$(_audit_stage_ts "$stages_jsonl" "$stage_name")
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
                    elif printf '%s\n' "$stage_tools" | grep -Eq -- "$tool"; then
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

# ---- seal / verify-seal ----
# Seal: append a digest line for the latest run's evidence files to
# .icm-seals.log at the project root, which is committable while .icm/ stays
# gitignored. Tamper EVIDENCE, not prevention: the log is a plain file until
# committed, and local git history is rewritable. Trust comes from committing
# the log and pushing; after that, tampering means a visible diff.
_seal_files() {
    for sf in .manifest telemetry/run.json telemetry/stages.jsonl telemetry/usage.jsonl; do
        [ -f "$1/$sf" ] && echo "$sf"
    done
    return 0
}

cmd_seal() {
    ws=""
    while [ $# -gt 0 ]; do
        case "$1" in
            --cwd) cd "$2"; shift 2 ;;
            *) ws="$1"; shift ;;
        esac
    done
    if [ -z "$ws" ]; then
        echo "seal requires workspace name" >&2
        exit 1
    fi
    latest=$(latest_run "$ws")
    if [ -z "$latest" ]; then
        echo "no runs for $ws" >&2
        exit 1
    fi
    run_dir=".icm/$ws/$latest"
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
    printf '{"ts":"%s","workspace":"%s","run_id":"%s","sealed":{%s}}\n' \
        "$(date -u +%Y-%m-%dT%H:%M:%SZ)" "$ws" "$latest" "$entries" >> .icm-seals.log
    echo "sealed $ws/$latest -> .icm-seals.log (commit this file)"
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
cmd_gate_check() {
    gc_tool=""
    while [ $# -gt 0 ]; do
        case "$1" in
            --tool) gc_tool=$2; shift 2 ;;
            --cwd)  cd "$2"; shift 2 ;;
            *) echo "Unknown gate-check option: $1" >&2; usage ;;
        esac
    done
    if [ -z "$gc_tool" ]; then
        echo "gate-check requires --tool <tool-name>" >&2
        usage
    fi
    [ -d .icm ] || exit 0

    gc_out=$(latest_runs | while IFS= read -r gc_run; do
        check_run "$gc_run" "$gc_tool"
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
        gs_denies=$(latest_runs | while IFS= read -r gs_run; do
            check_run "$gs_run" ""
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
    clean)  [ $# -ge 1 ] || usage; ws=$1; shift; cmd_clean "$ws" "$@" ;;
    telemetry) cmd_telemetry "$@" ;;
    stage-done) cmd_stage_done "$@" ;;
    reify-telemetry) cmd_reify_telemetry "$@" ;;
    audit) cmd_audit "$@" ;;
    seal) cmd_seal "$@" ;;
    verify-seal) cmd_verify_seal "$@" ;;
    children) cmd_children "$@" ;;
    *)
        echo "Unknown command: $cmd" >&2
        usage
        ;;
esac
