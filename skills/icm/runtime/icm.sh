#!/bin/sh
# ICM Runtime — POSIX-compatible (macOS, Linux, WSL)
# Usage:
#   icm.sh init   <workspace-name>          Create new timestamped run, freeze contracts
#   icm.sh next   <workspace-name>          Print path to next empty stage, or "done"
#   icm.sh list   <workspace-name>          List all runs with stage completion status
#   icm.sh diff   <workspace-name>          Diff output files of last two completed runs
#   icm.sh stages <workspace-name>          Print stage names in order
#   icm.sh clean  <workspace-name> [--keep N]  Remove old completed runs, keep N most recent
#   icm.sh gate-check --tool <tool-name> [--cwd DIR]  Evaluate frozen ICM-GATE lines; exit 1 + DENY on failure
#   icm.sh gate-status [--cwd DIR]           List declared gates and hook registration per scope
#   icm.sh telemetry <workspace> --model <m> --tokens-in <n> --tokens-out <n> --cost <c> [--cwd <dir>]
#   icm.sh stage-done <workspace> --stage <name> --model <m> [--tokens-in <n> --tokens-out <n>] [--cwd <dir>]
#   icm.sh reify-telemetry <workspace> [--cwd <dir>] [--transcript <path>]
#   icm.sh audit <workspace> [--cwd <dir>]

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
    local _ts _ec _args_json
    _ts=$(date -u +%Y-%m-%dT%H:%M:%SZ)
    _ec=${1:-0}
    if command -v jq >/dev/null 2>&1; then
        # -c is load-bearing: without it jq pretty-prints and the log entry
        # spans multiple physical lines, breaking every JSONL consumer.
        _args_json=$(printf '%s' "$ICM_LOG_CMD" | jq -R -s -c 'split(" ")')
    else
        _args_json="\"$ICM_LOG_CMD\""
    fi
    printf '{"ts":"%s","tool":"icm.sh","cmd":"%s","args":%s,"cwd":"%s","ec":%s}\n' \
        "$ICM_LOG_START" "$(printf '%s' "$ICM_LOG_CMD" | cut -d' ' -f1)" \
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
    echo "       icm.sh gate-check --tool <tool-name> [--cwd <dir>]" >&2
    echo "       icm.sh gate-status [--cwd <dir>]" >&2
    echo "       icm.sh telemetry <workspace> --model <m> --tokens-in <n> --tokens-out <n> --cost <c> [--cwd <dir>]" >&2
    echo "       icm.sh stage-done <workspace> --stage <name> --model <m> [--tokens-in <n> --tokens-out <n>] [--cwd <dir>]" >&2
    echo "       icm.sh reify-telemetry <workspace> [--cwd <dir>] [--transcript <path>]" >&2
    echo "       icm.sh audit <workspace> [--cwd <dir>]" >&2
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
            lr_parent=$(dirname "$lr_path")
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

# Verify every entry of a run's .manifest. Prints the first bad relpath and
# returns 1 on hash mismatch or missing file.
verify_manifest() {
    vm_run=$1
    while IFS= read -r vm_line; do
        [ -n "$vm_line" ] || continue
        vm_want=${vm_line%% *}
        vm_rel=${vm_line#* }
        vm_rel=${vm_rel# }
        vm_rel=${vm_rel#\*}
        if [ ! -f "$vm_run/$vm_rel" ]; then
            echo "$vm_rel"
            return 1
        fi
        vm_got=$( (cd "$vm_run" && sha_file "$vm_rel") )
        vm_got=${vm_got%% *}
        if [ "$vm_got" != "$vm_want" ]; then
            echo "$vm_rel"
            return 1
        fi
    done < "$vm_run/.manifest"
    return 0
}

# Evaluate one run's frozen gates. $1=run dir, $2=tool name ("" = evaluate every
# gate regardless of its tools regex, used by gate-status). Prints DENY lines on
# stdout (first line is the headline); silent when nothing matches or all pass.
# Fails closed: tampered/missing manifest, malformed gate lines, and invalid
# regexes all deny.
check_run() {
    cr_run=$1
    cr_tool=$2
    cr_ws=$(dirname "$cr_run")
    cr_ws=${cr_ws#.icm/}
    cr_ts=$(basename "$cr_run")

    if [ -f "$cr_run/.manifest" ]; then
        if ! vm_bad=$(verify_manifest "$cr_run"); then
            echo "DENY $cr_ws $cr_ts $vm_bad: contract tampered (sha256 mismatch with .manifest)"
            return 0
        fi
    fi

    for cr_ctx in "$cr_run"/[0-9]*/CONTEXT.md; do
        [ -f "$cr_ctx" ] || continue
        cr_stage_dir=$(dirname "$cr_ctx")
        cr_stage=$(basename "$cr_stage_dir")
        grep -F '<!-- ICM-GATE ' "$cr_ctx" 2>/dev/null | while IFS= read -r cr_line; do
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
    done
}

# ---- init ----
cmd_init() {
    ws=$1
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
    cat > "$run_dir/telemetry/run.json" <<ICM_RUN_EOF
{
  "workspace": "$ws",
  "run_id": "$ts",
  "created": "$(date -u +%Y-%m-%dT%H:%M:%SZ)",
  "stages": [$_stage_names],
  "cwd": "$PWD"
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
    printf '{"ts":"%s","skill":"%s","run_id":"%s","model":"%s","tokens_in":%s,"tokens_out":%s,"cost_est":%s,"cwd":"%s","log_dir":".icm/%s/%s/telemetry"}\n' \
        "$(date -u +%Y-%m-%dT%H:%M:%SZ)" "$ws" "$latest" "$model" "$tokens_in" "$tokens_out" "$cost" "$run_cwd" "$ws" "$latest" \
        >> "$global_file"
    echo "$global_file"
}

# ---- stage-done ----
# Record a stage boundary marker. Token counts are OPTIONAL (the model
# cannot access them programmatically; Tier 2 reify-telemetry fills them
# in post-hoc from the conversation transcript).
# MANDATORY after every completed stage.
cmd_stage_done() {
    ws=""; stage=""; model=""; tokens_in="null"; tokens_out="null"
    while [ $# -gt 0 ]; do
        case "$1" in
            --stage) stage="$2"; shift 2 ;;
            --model) model="$2"; shift 2 ;;
            --tokens-in) tokens_in="$2"; shift 2 ;;
            --tokens-out) tokens_out="$2"; shift 2 ;;
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

    # Write stage boundary. tokens_in/tokens_out default to null.
    _ti_val="$tokens_in"
    _to_val="$tokens_out"
    case "$_ti_val" in ''|null) _ti_val="null" ;; esac
    case "$_to_val" in ''|null) _to_val="null" ;; esac
    printf '{"ts":"%s","stage":"%s","model":"%s","tokens_in":%s,"tokens_out":%s,"counts":"estimated"}\n' \
        "$(date -u +%Y-%m-%dT%H:%M:%SZ)" "$stage" "$model" "$_ti_val" "$_to_val" \
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

    # Auto-detect transcript path. Claude Code encodes the project cwd into the
    # transcript dir name (/ and . become -), so prefer that dir when it exists;
    # otherwise scan all sessions. Pick the newest candidate by mtime, not find
    # order: with parallel sessions the first hit is arbitrary.
    if [ -z "$transcript" ]; then
        _search_dir=""
        if [ -n "${CLAUDECODE:-}" ]; then
            _munged=$(pwd | sed 's,[/.],-,g')
            if [ -d "${HOME}/.claude/projects/$_munged" ]; then
                _search_dir="${HOME}/.claude/projects/$_munged"
            else
                _search_dir="${HOME}/.claude/projects"
            fi
        elif [ -d "${HOME}/.pi" ]; then
            _search_dir="${HOME}/.pi/agent/sessions"
        fi
        if [ -n "$_search_dir" ]; then
            _n=0
            for _c in $(find "$_search_dir" -name '*.jsonl' -newer "$run_dir/.manifest" 2>/dev/null); do
                _n=$((_n + 1))
                if [ -z "$transcript" ] || [ "$_c" -nt "$transcript" ]; then
                    transcript=$_c
                fi
            done
            if [ "$_n" -gt 1 ]; then
                echo "reify-telemetry: $_n candidate transcripts; picked newest: $transcript" >&2
                echo "Pass --transcript <path> if this is the wrong session." >&2
            fi
        fi
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
            _tokens_in=$(jq --arg start "$_prev_ts" --arg end "$_ts" '
                select(.ts >= $start and .ts < $end and .usage.input_tokens)
                | .usage.input_tokens
            ' "$transcript" 2>/dev/null | awk '{s+=$1} END {if (NR==0) print "null"; else print s}')
            _tokens_out=$(jq --arg start "$_prev_ts" --arg end "$_ts" '
                select(.ts >= $start and .ts < $end and .usage.output_tokens)
                | .usage.output_tokens
            ' "$transcript" 2>/dev/null | awk '{s+=$1} END {if (NR==0) print "null"; else print s}')
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
cmd_audit() {
    ws=""
    while [ $# -gt 0 ]; do
        case "$1" in
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
    run_start=$(printf '%s' "$latest" | sed 's/_/T/' | sed 's/-\([0-9][0-9]\)$/:\1/')
    actual_tools=""
    if [ -f "$telemetry_log" ]; then
        _window=$(awk -v start="$run_start" -F '"' '/"ts":"/ { if ($4 >= start) print }' "$telemetry_log" 2>/dev/null || true)
        actual_tools=$( { printf '%s\n' "$_window" | grep -o '"--tool","[^"]*"' | sed 's/"--tool","//;s/"$//' || true; \
                          printf '%s\n' "$_window" | grep -o -- '--tool [^" ]*' | sed 's/--tool //' || true; } | sort -u)
    fi

    for stage_dir in "$run_dir"/[0-9]*/; do
        [ -d "$stage_dir" ] || continue
        stage_name=$(basename "$stage_dir")
        ctx="$stage_dir/CONTEXT.md"
        [ -f "$ctx" ] || continue

        icm_tools=$(grep -o '<!-- ICM-TOOLS expect="[^"]*"' "$ctx" 2>/dev/null | head -1 | sed 's/.*expect="//;s/"$//' || true)
        legacy=""
        if [ -z "$icm_tools" ]; then
            legacy=$(grep -Eo '\x60?(bash )?tools/[^\x60" ]+(\.sh)?\x60?' "$ctx" 2>/dev/null | tr -d '\x60' | sort -u || true)
        fi
        gates=$(grep -Eo 'run="(tools/)?[^"]+"' "$ctx" 2>/dev/null | sed 's/run="//;s/"$//' | sort -u || true)

        if [ -n "$icm_tools" ] || [ -n "$legacy" ] || [ -n "$gates" ]; then
            echo "STAGE $stage_name -- TOOL CALL CHECK"
            echo "──────────────────────────────────────"

            if [ -n "$icm_tools" ]; then
                echo "Expected tools (ICM-TOOLS):"
                for tool in $icm_tools; do
                    if [ -z "$actual_tools" ]; then
                        echo "  ? $tool -- no harness tool-call records in run window"
                    elif printf '%s\n' "$actual_tools" | grep -Eq -- "$tool"; then
                        echo "  ✓ $tool"
                    else
                        echo "  ✗ $tool -- not seen in telemetry"
                        deviations=$((deviations + 1))
                    fi
                done
                if [ -z "$actual_tools" ]; then
                    echo "  (no gate-check records; enforcement adapter likely not registered -- cannot verify)"
                fi
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

            if [ -f "$telemetry_log" ]; then
                echo "Actual harness tools during run window:"
                if [ -n "$actual_tools" ]; then
                    printf '%s\n' "$actual_tools" | while IFS= read -r t; do
                        echo "  $t"
                    done
                else
                    echo "  (none recorded)"
                fi
            else
                echo "No telemetry available (tool-calls.jsonl not found)"
                deviations=$((deviations + 1))
            fi
            echo ""
        fi
    done

    echo "──────────────────────────────────────"
    echo "Deviations: $deviations (review manually for false positives)"
    if [ "$complete" = false ]; then
        echo "Run is incomplete -- audit may be partial."
    fi
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
    init)   [ $# -ge 1 ] || usage; cmd_init "$1" ;;
    next)   [ $# -ge 1 ] || usage; cmd_next "$1" ;;
    list)   [ $# -ge 1 ] || usage; cmd_list "$1" ;;
    diff)   [ $# -ge 1 ] || usage; cmd_diff "$1" ;;
    stages) [ $# -ge 1 ] || usage; cmd_stages "$1" ;;
    clean)  [ $# -ge 1 ] || usage; ws=$1; shift; cmd_clean "$ws" "$@" ;;
    telemetry) cmd_telemetry "$@" ;;
    stage-done) cmd_stage_done "$@" ;;
    reify-telemetry) cmd_reify_telemetry "$@" ;;
    audit) cmd_audit "$@" ;;
    *)
        echo "Unknown command: $cmd" >&2
        usage
        ;;
esac
