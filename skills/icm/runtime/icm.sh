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

set -eu
SCRIPT_DIR=$(cd "$(dirname "$0")" && pwd -P)
SKILLS_DIR=$(cd "$SCRIPT_DIR/../.." && pwd)

usage() {
    echo "Usage: icm.sh <init|next|list|diff|stages|clean> <workspace-name> [--keep N]" >&2
    echo "       icm.sh gate-check --tool <tool-name> [--cwd <dir>]" >&2
    echo "       icm.sh gate-status [--cwd <dir>]" >&2
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
    ) > "$run_dir/.manifest"

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

# ---- gate-check ----
# Called by the PreToolUse hook (gate-hook.sh) on every mcp__* tool call.
# Exit 0 silent: no gate matched or all matching gates pass.
# Exit 1 + DENY lines on stdout: a matching gate failed or integrity failed.
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
    echo "== Hook registration (gate-hook.sh) =="
    gs_registered=0
    for gs_settings in "${HOME:-}/.claude/settings.json" ".claude/settings.json" ".claude/settings.local.json"; do
        if [ -f "$gs_settings" ] && grep -q 'gate-hook\.sh' "$gs_settings" 2>/dev/null; then
            echo "REGISTERED      $gs_settings"
            gs_registered=1
        else
            echo "NOT REGISTERED  $gs_settings"
        fi
    done

    if [ -n "$gs_gates" ] && [ "$gs_registered" -eq 0 ]; then
        echo ""
        echo "RESULT: FAIL - active runs declare gates but the hook is not registered in any scope"
        exit 1
    fi
    exit 0
}

# ---- main ----
if [ $# -lt 1 ]; then
    usage
fi

cmd=$1
shift

case "$cmd" in
    gate-check)  cmd_gate_check "$@" ;;
    gate-status) cmd_gate_status "$@" ;;
    init)   [ $# -ge 1 ] || usage; cmd_init "$1" ;;
    next)   [ $# -ge 1 ] || usage; cmd_next "$1" ;;
    list)   [ $# -ge 1 ] || usage; cmd_list "$1" ;;
    diff)   [ $# -ge 1 ] || usage; cmd_diff "$1" ;;
    stages) [ $# -ge 1 ] || usage; cmd_stages "$1" ;;
    clean)  [ $# -ge 1 ] || usage; ws=$1; shift; cmd_clean "$ws" "$@" ;;
    *)
        echo "Unknown command: $cmd" >&2
        usage
        ;;
esac
