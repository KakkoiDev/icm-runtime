#!/bin/sh
# ICM Runtime — POSIX-compatible (macOS, Linux, WSL)
# Usage:
#   icm.sh init   <workspace-name>          Create new timestamped run, freeze contracts
#   icm.sh next   <workspace-name>          Print path to next empty stage, or "done"
#   icm.sh list   <workspace-name>          List all runs with stage completion status
#   icm.sh diff   <workspace-name>          Diff output files of last two completed runs
#   icm.sh stages <workspace-name>          Print stage names in order
#   icm.sh clean  <workspace-name> [--keep N]  Remove old completed runs, keep N most recent

set -eu
SCRIPT_DIR=$(cd "$(dirname "$0")" && pwd -P)
SKILLS_DIR=$(cd "$SCRIPT_DIR/../.." && pwd)

usage() {
    echo "Usage: icm.sh <init|next|list|diff|stages|clean> <workspace-name> [--keep N]" >&2
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
            # Bare name: recursive find (backward compatible)
            found=$(find "$SKILLS_DIR" -maxdepth 4 -type d -name "$ws" 2>/dev/null | head -1)
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

# ---- init ----
cmd_init() {
    ws=$1
    ws_dir=$(find_workspace "$ws")
    stages_dir="$ws_dir/stages"

    ts=$(date -u +%Y-%m-%d_%H-%M-%S)
    run_dir=".icm/$ws/$ts"

    mkdir -p "$run_dir"

    for stage_file in "$stages_dir"/*.md; do
        [ -f "$stage_file" ] || continue
        stage_name=$(basename "$stage_file" .md)
        stage_dir="$run_dir/$stage_name"
        mkdir -p "$stage_dir/output"
        cp "$stage_file" "$stage_dir/CONTEXT.md"
    done

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

# ---- main ----
if [ $# -lt 2 ]; then
    usage
fi

cmd=$1
ws=$2

case "$cmd" in
    init)   cmd_init "$ws" ;;
    next)   cmd_next "$ws" ;;
    list)   cmd_list "$ws" ;;
    diff)   cmd_diff "$ws" ;;
    stages) cmd_stages "$ws" ;;
    clean) shift 2; cmd_clean "$ws" "$@" ;;
    *)
        echo "Unknown command: $cmd" >&2
        usage
        ;;
esac
