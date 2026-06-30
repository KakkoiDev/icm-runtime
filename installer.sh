#!/bin/bash
# icm-runtime installer - installs skill directories into ~/.agents/skills/
# (pi/Codex, namespaced) and ~/.claude/skills/ (Claude Code, flattened).
#
# Usage:
#   ./installer.sh                      Symlink ALL skills (default, single source of truth)
#   ./installer.sh <skill>...           Granular: link only the named skills as Claude Code
#                                        /commands (e.g. ./installer.sh pr-review grade-output).
#                                        The ~/.agents namespace links (runtime) are kept for all.
#   ./installer.sh --copy               Copy skills (safer if agent doesn't follow symlinks)
#   ./installer.sh --remove [<skill>...] Remove all installed skills, or only the named /commands
#   ./installer.sh --hooks              Register gate enforcement (Claude Code hook + pi extension)

set -eu

# Optional skill-name filter (positional args). Empty = act on all skills. Controls
# which skills are exposed as Claude Code /commands (the ~/.claude/skills flat links).
SELECT=()
# True when no filter is set, or when $1 is one of the named skills.
selected() {
    [ ${#SELECT[@]} -eq 0 ] && return 0
    local s
    for s in "${SELECT[@]}"; do [ "$s" = "$1" ] && return 0; done
    return 1
}

SKILLS_DIR="$HOME/.agents/skills"
CLAUDE_SKILLS_DIR="$HOME/.claude/skills"
SOURCE_DIR="$(cd "$(dirname "$0")" && pwd)/skills"

GREEN='\033[0;32m'
RED='\033[0;31m'
NC='\033[0m'

ok()  { echo -e "${GREEN}[ok]${NC} $1"; }
err() { echo -e "${RED}[err]${NC} $1"; }
info() { echo -e "     $1"; }

# Gitignore a created symlink in its repo-root .gitignore (repo-relative path), so
# machine-specific links are not committed. No-op outside a git repo or if tracked.
ensure_ignored() {
    local link="$1" base dir top real_link rel gi
    base=$(basename "$link")
    dir=$(cd -P "$(dirname "$link")" && pwd -P)
    top=$(git -C "$dir" rev-parse --show-toplevel 2>/dev/null) || return 0
    real_link="$dir/$base"
    git -C "$dir" ls-files --error-unmatch "$real_link" >/dev/null 2>&1 && return 0
    rel="${real_link#"$top"/}"
    gi="$top/.gitignore"
    if ! grep -qxF "$rel" "$gi" 2>/dev/null; then
        printf '%s\n' "$rel" >> "$gi"
        info "ignored: $rel"
    fi
}

install_symlink() {
    for skill_dir in "$SOURCE_DIR"/*/; do
        [ -d "$skill_dir" ] || continue
        skill_name=$(basename "$skill_dir")
        target="$SKILLS_DIR/$skill_name"

        if [ -L "$target" ]; then
            current=$(readlink "$target")
            if [ "$current" = "$skill_dir" ]; then
                ok "$skill_name (already linked)"
            else
                err "$skill_name symlink exists but points elsewhere: $current"
                exit 1
            fi
        elif [ -d "$target" ]; then
            err "$skill_name is a directory (not a symlink). Remove manually first."
            exit 1
        else
            ln -s "$skill_dir" "$target"
            ok "$skill_name -> $skill_dir"
        fi
        ensure_ignored "$target"
    done
    info "Symlink mode: edit files in ~/Code/icm-runtime/, changes propagate immediately."
}

# Claude Code discovers skills only one level deep, so flatten namespaced skills
# (e.g. jake-van-clief/ai-folder-research -> ai-folder-research) into ~/.claude/skills/.
install_claude_symlink() {
    mkdir -p "$CLAUDE_SKILLS_DIR"
    while IFS= read -r skill_md; do
        skill_dir=$(cd "$(dirname "$skill_md")" && pwd)
        skill_name=$(basename "$skill_dir")
        selected "$skill_name" || continue
        target="$CLAUDE_SKILLS_DIR/$skill_name"

        if [ -L "$target" ]; then
            if [ "$(readlink "$target")" = "$skill_dir" ]; then
                ok "claude: $skill_name (already linked)"
            else
                err "claude: $skill_name symlink exists but points elsewhere: $(readlink "$target")"
                exit 1
            fi
        elif [ -e "$target" ]; then
            err "claude: $skill_name exists and is not our symlink. Remove manually first."
            exit 1
        else
            ln -s "$skill_dir" "$target"
            ok "claude: $skill_name -> $skill_dir"
        fi
        ensure_ignored "$target"
    done < <(find "$SOURCE_DIR" -name SKILL.md)
}

install_copy() {
    for skill_dir in "$SOURCE_DIR"/*/; do
        [ -d "$skill_dir" ] || continue
        skill_name=$(basename "$skill_dir")
        target="$SKILLS_DIR/$skill_name"

        if [ -L "$target" ]; then
            rm "$target"
        fi

        rm -rf "$target"
        cp -R "$skill_dir" "$target"
        ok "$skill_name (copied)"
    done
    info "Copy mode: re-run installer to pick up changes from ~/Code/icm-runtime/."
}

install_claude_copy() {
    mkdir -p "$CLAUDE_SKILLS_DIR"
    while IFS= read -r skill_md; do
        skill_dir=$(cd "$(dirname "$skill_md")" && pwd)
        skill_name=$(basename "$skill_dir")
        selected "$skill_name" || continue
        target="$CLAUDE_SKILLS_DIR/$skill_name"

        if [ -L "$target" ]; then
            rm "$target"
        fi

        rm -rf "$target"
        cp -R "$skill_dir" "$target"
        ok "claude: $skill_name (copied)"
    done < <(find "$SOURCE_DIR" -name SKILL.md)
}

remove() {
    # Full uninstall (no name filter) removes the ~/.agents namespace links and
    # the gate hooks. A granular remove (named skills) only unlinks those skills
    # as Claude Code /commands, leaving the runtime namespace links and hooks intact
    # - e.g. ./installer.sh --remove nest-demo-child drops one stray /command.
    if [ ${#SELECT[@]} -eq 0 ]; then
        for skill_dir in "$SOURCE_DIR"/*/; do
            [ -d "$skill_dir" ] || continue
            skill_name=$(basename "$skill_dir")
            target="$SKILLS_DIR/$skill_name"

            if [ -L "$target" ]; then
                rm "$target"
                ok "$skill_name (symlink removed)"
            elif [ -d "$target" ]; then
                rm -rf "$target"
                ok "$skill_name (copy removed)"
            else
                ok "$skill_name (not installed)"
            fi
        done
    fi

    while IFS= read -r skill_md; do
        skill_dir=$(cd "$(dirname "$skill_md")" && pwd)
        skill_name=$(basename "$skill_dir")
        selected "$skill_name" || continue
        target="$CLAUDE_SKILLS_DIR/$skill_name"

        if [ -L "$target" ]; then
            case "$(readlink "$target")" in
                "$SOURCE_DIR"/*)
                    rm "$target"
                    ok "claude: $skill_name (symlink removed)"
                    ;;
                *)
                    info "claude: $skill_name points elsewhere, leaving it"
                    ;;
            esac
        elif [ -d "$target" ]; then
            rm -rf "$target"
            ok "claude: $skill_name (copy removed)"
        else
            ok "claude: $skill_name (not installed)"
        fi
    done < <(find "$SOURCE_DIR" -name SKILL.md)

    [ ${#SELECT[@]} -eq 0 ] && unregister_hooks
}

# Remove enforcement adapter registrations. A dangling gate-hook with the
# wide ".*" matcher would error on every tool call once the skill files are
# gone, so --remove must unregister, not just delete symlinks.
unregister_hooks() {
    local settings="$HOME/.claude/settings.json"
    if [ -f "$settings" ] && command -v jq >/dev/null 2>&1 \
        && jq -e '[.hooks.PreToolUse[]?.hooks[]?.command // empty] | any(contains("gate-hook.sh"))' "$settings" >/dev/null 2>&1; then
        local tmp
        tmp=$(mktemp)
        jq '.hooks.PreToolUse = [(.hooks.PreToolUse // [])[] | select(([.hooks[]?.command // empty] | any(contains("gate-hook.sh"))) | not)]
            | if .hooks.PreToolUse == [] then del(.hooks.PreToolUse) else . end
            | if .hooks == {} then del(.hooks) else . end' "$settings" > "$tmp"
        write_settings "$tmp" "$settings"
        ok "claude: gate-hook unregistered from $settings"
    fi

    local ext="$HOME/.pi/agent/extensions/icm-gate.ts"
    if [ -L "$ext" ] || [ -f "$ext" ]; then
        rm -f "$ext"
        ok "pi: icm-gate extension removed"
    fi
}

# Write $1 over $2 in place (cat, not mv): mv swaps the inode, which silently
# breaks setups where settings.json is a hardlink or symlink into a dotfiles
# repo. cat preserves the existing inode and any links to it.
write_settings() {
    cat "$1" > "$2"
    rm -f "$1"
}

# Register ICM gate enforcement in every supported harness on this machine:
# Claude Code (PreToolUse hook in ~/.claude/settings.json) and pi (tool_call
# extension symlinked into ~/.pi/agent/extensions/). Idempotent. The absolute
# path is written at install time so expansion quirks cannot break it.
install_pi_extension() {
    local ext_src="$SKILLS_DIR/icm/runtime/icm-gate.ts"
    local ext_dir="$HOME/.pi/agent/extensions"
    local target="$ext_dir/icm-gate.ts"

    if [ ! -d "$HOME/.pi" ]; then
        info "pi: ~/.pi not found, skipping pi extension"
        return 0
    fi
    if [ ! -e "$ext_src" ]; then
        err "pi: icm-gate.ts not installed at $ext_src. Run ./installer.sh first."
        exit 1
    fi

    mkdir -p "$ext_dir"
    if [ -L "$target" ]; then
        if [ "$(readlink "$target")" = "$ext_src" ]; then
            ok "pi: icm-gate.ts already registered"
        else
            err "pi: $target exists but points elsewhere: $(readlink "$target")"
            exit 1
        fi
    elif [ -e "$target" ]; then
        err "pi: $target exists and is not our symlink. Remove manually first."
        exit 1
    else
        ln -s "$ext_src" "$target"
        ok "pi: registered icm-gate.ts -> $ext_src"
        info "pi: takes effect on next pi start (or /reload)"
    fi
}

install_hooks() {
    if ! command -v jq >/dev/null 2>&1; then
        err "--hooks requires jq (brew install jq / apt install jq)"
        exit 1
    fi

    local hook_cmd="$SKILLS_DIR/icm/runtime/gate-hook.sh"
    local settings="$HOME/.claude/settings.json"

    if [ ! -e "$hook_cmd" ]; then
        err "gate-hook.sh not installed at $hook_cmd. Run ./installer.sh first."
        exit 1
    fi

    mkdir -p "$HOME/.claude"
    if [ ! -f "$settings" ]; then
        echo '{}' > "$settings"
        info "created $settings"
    fi

    if jq -e '[.hooks.PreToolUse[]?.hooks[]?.command // empty] | any(contains("gate-hook.sh"))' "$settings" >/dev/null; then
        # Migrate pre-0.6 registrations from "mcp__.*" to ".*" so built-in
        # tools (WebSearch, Bash, ...) are gated and logged too.
        if jq -e '[.hooks.PreToolUse[]? | select([.hooks[]?.command // empty] | any(contains("gate-hook.sh"))) | .matcher] | any(. == "mcp__.*")' "$settings" >/dev/null 2>&1; then
            local mig
            mig=$(mktemp)
            jq '(.hooks.PreToolUse[]? | select([.hooks[]?.command // empty] | any(contains("gate-hook.sh"))) | .matcher) |= ".*"' \
                "$settings" > "$mig"
            write_settings "$mig" "$settings"
            ok "claude: widened gate-hook matcher to .* in $settings"
        else
            ok "claude: gate-hook already registered in $settings"
        fi
        install_pi_extension
        return 0
    fi

    local backup="$settings.bak-$$"
    cp "$settings" "$backup"
    local tmp
    tmp=$(mktemp)
    jq --arg cmd "$hook_cmd" \
        '.hooks.PreToolUse = ((.hooks.PreToolUse // []) + [{"matcher": ".*", "hooks": [{"type": "command", "command": $cmd, "timeout": 15}]}])' \
        "$settings" > "$tmp"
    write_settings "$tmp" "$settings"
    ok "claude: registered gate-hook in $settings"
    info "matcher: .* -> $hook_cmd"
    info "backup: $backup"
    install_pi_extension
}

mkdir -p "$SKILLS_DIR"
mkdir -p "$CLAUDE_SKILLS_DIR"

usage() {
    echo "Usage: $0 [--symlink|--copy|--remove|--hooks] [skill...]" >&2
    echo "  (no args)          symlink ALL skills (default)" >&2
    echo "  skill...           link only the named skills as Claude Code /commands" >&2
    echo "  --remove           full uninstall (namespace links + /commands + hooks)" >&2
    echo "  --remove skill...  unlink only the named /commands (keeps namespace + hooks)" >&2
    echo "  --copy             copy instead of symlink   --hooks  register gate enforcement" >&2
}

# Parse: one optional action flag, then any number of skill names (the filter).
ACTION=install
while [ $# -gt 0 ]; do
    case "$1" in
        --symlink|-s)  ACTION=install ;;
        --copy|-c)     ACTION=copy ;;
        --remove|-r)   ACTION=remove ;;
        --hooks)       ACTION=hooks ;;
        -h|--help)     usage; exit 0 ;;
        --*)           err "unknown option: $1"; usage; exit 1 ;;
        *)             SELECT+=("$1") ;;
    esac
    shift
done

# Typo protection: every named skill must exist as skills/*/<name>/SKILL.md.
if [ ${#SELECT[@]} -gt 0 ]; then
    for s in "${SELECT[@]}"; do
        found=0
        while IFS= read -r skill_md; do
            [ "$(basename "$(dirname "$skill_md")")" = "$s" ] && { found=1; break; }
        done < <(find "$SOURCE_DIR" -name SKILL.md)
        if [ "$found" -ne 1 ]; then
            err "unknown skill: $s (no skills/*/$s/SKILL.md)"
            exit 1
        fi
    done
fi

case "$ACTION" in
    install) install_symlink; install_claude_symlink ;;
    copy)    install_copy; install_claude_copy ;;
    remove)  remove ;;
    hooks)   install_hooks ;;
esac

echo ""
echo "Done. Restart your coding agent to pick up changes."
