#!/usr/bin/env bash
# icm-improve: deterministic plumbing for the ICM self-improvement loop.
#
# The model drives the three agent steps (executor, grader, improver) described
# in SKILL.md. This script never calls a model. It owns the auditable, on-disk
# scaffolding: per-phase candidate copies, the invariant guard, the held-out
# check, and the results roll-up. Every intermediate lands under .icm-improve/
# so the whole loop is inspectable after the fact.
#
# Parses under bash 3.2 / POSIX sh. No associative arrays, mapfile, or ${v^^}.
set -eu

ICM_SH="${ICM_SH:-$HOME/.agents/skills/icm/runtime/icm.sh}"
SKILLS_DIR="${ICM_SKILLS_DIR:-$HOME/.agents/skills}"
IMPROVE_ROOT="${ICM_IMPROVE_ROOT:-.icm-improve}"

die() { echo "icm-improve: $*" >&2; exit 1; }

# Copy the parts of a skill a candidate needs. Only what exists is copied.
cp_skill() {
    for item in SKILL.md stages checks tools eval references; do
        [ -e "$1/$item" ] && cp -R "$1/$item" "$2/"
    done
    return 0
}

# ---- start: open a session, seed phase-1 candidate from canonical source ----
cmd_start() {
    is_ws=""; is_phases=3; is_session=""
    while [ $# -gt 0 ]; do
        case "$1" in
            --phases) is_phases=$2; shift 2 ;;
            --session) is_session=$2; shift 2 ;;
            *) is_ws=$1; shift ;;
        esac
    done
    [ -n "$is_ws" ] || die "start requires <ns>/<skill>"
    is_src="$SKILLS_DIR/$is_ws"
    [ -d "$is_src" ] || die "skill source not found: $is_src"
    [ -n "$is_session" ] || is_session=$(date -u +%Y-%m-%d_%H-%M-%S)
    is_sdir="$IMPROVE_ROOT/$is_ws/$is_session"
    [ -e "$is_sdir" ] && die "session dir already exists: $is_sdir"
    mkdir -p "$is_sdir/phase-1/candidate"
    cp_skill "$is_src" "$is_sdir/phase-1/candidate"
    printf '%s\n' "$is_phases" > "$is_sdir/phases"
    echo "$is_sdir"
}

# ---- next-phase: clone the current candidate forward so the improver edits it ----
cmd_next_phase() {
    [ $# -ge 2 ] || die "next-phase requires <session-dir> <from-phase-number>"
    np_sdir=$1; np_from=$2
    np_next=$((np_from + 1))
    [ -d "$np_sdir/phase-$np_from/candidate" ] || die "no candidate at phase-$np_from"
    [ -e "$np_sdir/phase-$np_next" ] && die "phase-$np_next already exists"
    mkdir -p "$np_sdir/phase-$np_next"
    cp -R "$np_sdir/phase-$np_from/candidate" "$np_sdir/phase-$np_next/candidate"
    echo "$np_sdir/phase-$np_next/candidate"
}

# Protected regions of a stage file: the ICM declaration lines (gates, expected
# tools, call specs) plus the `## Outputs` section body. These are the rubric
# and the enforcement surface; the improver must not touch them.
protected_fingerprint() {
    grep -E '<!-- ICM-(GATE|TOOLS|CALL)' "$1" 2>/dev/null || true
    awk '
        /^##[[:space:]]+Outputs/ { p = 1; print; next }
        /^##[[:space:]]/ { p = 0 }
        p { print }
    ' "$1" 2>/dev/null || true
}

# ---- guard: invariant 1. Fail if the improver changed anything but stage prose ----
# $1 = previous candidate dir, $2 = new candidate dir. Exit 0 only when the only
# differences are stage prose OUTSIDE the protected regions.
cmd_guard() {
    [ $# -ge 2 ] || die "guard requires <prev-candidate-dir> <new-candidate-dir>"
    g_a=$1; g_b=$2
    { [ -d "$g_a" ] && [ -d "$g_b" ]; } || die "guard requires two candidate dirs"

    # (a) Nothing outside stages/ may change: checks/, tools/, SKILL.md, eval/,
    # references/ are frozen relative to the improver.
    g_out=$(diff -rq -x stages "$g_a" "$g_b" 2>&1 || true)
    [ -z "$g_out" ] || die "FORBIDDEN: change outside stages/ (checks, tools, SKILL.md, eval are frozen to the improver):
$g_out"

    # (b) The stage file set must be identical (no stage added or removed).
    g_la=$( (cd "$g_a/stages" 2>/dev/null && ls -1 2>/dev/null | LC_ALL=C sort) || true)
    g_lb=$( (cd "$g_b/stages" 2>/dev/null && ls -1 2>/dev/null | LC_ALL=C sort) || true)
    [ "$g_la" = "$g_lb" ] || die "FORBIDDEN: stage files added or removed"

    # (c) Protected regions (gates, ICM-TOOLS, ICM-CALL, ## Outputs) per stage
    # must be byte-identical. Prose outside them may change freely.
    for g_f in $g_la; do
        g_fa=$(protected_fingerprint "$g_a/stages/$g_f")
        g_fb=$(protected_fingerprint "$g_b/stages/$g_f")
        [ "$g_fa" = "$g_fb" ] || die "FORBIDDEN: protected region (gate / ICM-TOOLS / ICM-CALL / ## Outputs) changed in stages/$g_f"
    done

    echo "GUARD OK: only stage prose changed; rubric, gates, checks, tools intact"
}

# ---- held-out: run the candidate's eval/*.test.sh (the canary the improver never sees) ----
# $1 = candidate dir, $2 = phase dir to write heldout.txt into.
cmd_heldout() {
    [ $# -ge 2 ] || die "held-out requires <candidate-dir> <phase-dir>"
    ho_cand=$1; ho_out=$2
    ho_pass=0; ho_fail=0
    if [ -d "$ho_cand/eval" ]; then
        for ho_t in "$ho_cand"/eval/*.test.sh; do
            [ -f "$ho_t" ] || continue
            if (cd "$ho_cand" && sh "$ho_t") >/dev/null 2>&1; then
                ho_pass=$((ho_pass + 1))
            else
                ho_fail=$((ho_fail + 1))
            fi
        done
    fi
    printf 'held-out eval: %s passed, %s failed\n' "$ho_pass" "$ho_fail" > "$ho_out/heldout.txt"
    cat "$ho_out/heldout.txt"
    [ "$ho_fail" -eq 0 ]
}

# Read summary.pass_rate from a grading.json (jq if present, else grep).
_passrate() {
    [ -f "$1" ] || { echo "n/a"; return 0; }
    if command -v jq >/dev/null 2>&1; then
        jq -r '.summary.pass_rate // "n/a"' "$1" 2>/dev/null || echo "n/a"
    else
        grep -o '"pass_rate":[ ]*[0-9.]*' "$1" 2>/dev/null | head -1 | sed 's/.*://;s/ //g' || echo "n/a"
    fi
}

# ---- results: roll up the trajectory for human review ----
cmd_results() {
    [ $# -ge 1 ] || die "results requires <session-dir>"
    r_sdir=$1
    [ -d "$r_sdir" ] || die "no session dir: $r_sdir"
    r_rf="$r_sdir/results.md"
    {
        echo "# Improvement results"
        echo
        echo "Session: \`$r_sdir\`"
        echo
        echo "| phase | held-out | grading pass_rate |"
        echo "|---|---|---|"
        for r_p in "$r_sdir"/phase-*/; do
            [ -d "$r_p" ] || continue
            r_name=$(basename "$r_p")
            r_ho=$(head -1 "$r_p/heldout.txt" 2>/dev/null || echo "n/a")
            r_pr=$(_passrate "$r_p/grading.json")
            echo "| $r_name | $r_ho | $r_pr |"
        done
        echo
        echo "## Reward-hacking check"
        echo
        echo "If grading pass_rate rises while held-out passed-count falls, the improver"
        echo "gamed the rubric. Promote a candidate ONLY when both move together."
        echo
        echo "## Candidate prose diffs"
        r_prev=""
        for r_p in "$r_sdir"/phase-*/; do
            [ -d "$r_p/candidate/stages" ] || continue
            r_name=$(basename "$r_p")
            if [ -n "$r_prev" ]; then
                echo
                echo "### $r_prev -> $r_name"
                echo '```diff'
                diff -ru "$r_sdir/$r_prev/candidate/stages" "$r_p/candidate/stages" 2>&1 || true
                echo '```'
            fi
            r_prev=$r_name
        done
    } > "$r_rf"
    echo "$r_rf"
}

# ---- install-candidate: stage a candidate as a scratch skill icm.sh can init ----
# $1 = candidate dir, $2 = scratch workspace name (must end in __improve). Lets
# the usage step run the candidate through icm.sh without mutating the canonical
# skill source.
cmd_install_candidate() {
    [ $# -ge 2 ] || die "install-candidate requires <candidate-dir> <scratch-ws>"
    ic_cand=$1; ic_ws=$2
    [ -d "$ic_cand" ] || die "no candidate dir: $ic_cand"
    case "$ic_ws" in
        *__improve) : ;;
        *) die "scratch workspace must end in __improve (got: $ic_ws)" ;;
    esac
    ic_dest="$SKILLS_DIR/$ic_ws"
    [ -e "$ic_dest" ] && die "scratch skill already exists: $ic_dest"
    mkdir -p "$ic_dest"
    cp_skill "$ic_cand" "$ic_dest"
    echo "$ic_dest"
}

# ---- uninstall-candidate: remove a scratch skill (only __improve names) ----
cmd_uninstall_candidate() {
    [ $# -ge 1 ] || die "uninstall-candidate requires <scratch-ws>"
    uc_ws=$1
    case "$uc_ws" in
        *__improve) : ;;
        *) die "refusing to remove a non-scratch skill: $uc_ws" ;;
    esac
    uc_dest="$SKILLS_DIR/$uc_ws"
    [ -d "$uc_dest" ] || die "no scratch skill: $uc_dest"
    rm -rf "$uc_dest"
    echo "removed $uc_dest"
}

usage() {
    cat >&2 <<'EOF'
icm-improve <command> [args]   (deterministic plumbing; agents are driven by SKILL.md)

  start <ns>/<skill> [--phases N] [--session ID]   open a session, seed phase-1 candidate
  next-phase <session-dir> <from-phase-number>     clone current candidate forward to edit
  guard <prev-candidate-dir> <new-candidate-dir>   invariant 1: only stage prose may change
  install-candidate <candidate-dir> <scratch-ws>   stage candidate as a scratch skill (__improve)
  uninstall-candidate <scratch-ws>                 remove a scratch skill (__improve only)
  held-out <candidate-dir> <phase-dir>             run the candidate's eval/*.test.sh canary
  results <session-dir>                            roll up trajectory + diffs to results.md
EOF
    exit 1
}

[ $# -ge 1 ] || usage
cmd=$1; shift
case "$cmd" in
    start)               cmd_start "$@" ;;
    next-phase)          cmd_next_phase "$@" ;;
    guard)               cmd_guard "$@" ;;
    install-candidate)   cmd_install_candidate "$@" ;;
    uninstall-candidate) cmd_uninstall_candidate "$@" ;;
    held-out)            cmd_heldout "$@" ;;
    results)             cmd_results "$@" ;;
    *)                   echo "Unknown command: $cmd" >&2; usage ;;
esac
