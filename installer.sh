#!/bin/bash
# icm-runtime installer - installs skill directories into ~/.agents/skills/
# (pi/Codex, namespaced) and ~/.claude/skills/ (Claude Code, flattened).
#
# Usage:
#   ./installer.sh            Symlink skills (default, single source of truth)
#   ./installer.sh --copy     Copy skills (safer if agent doesn't follow symlinks)
#   ./installer.sh --remove   Remove installed skills

set -eu

SKILLS_DIR="$HOME/.agents/skills"
CLAUDE_SKILLS_DIR="$HOME/.claude/skills"
SOURCE_DIR="$(cd "$(dirname "$0")" && pwd)/skills"

GREEN='\033[0;32m'
RED='\033[0;31m'
NC='\033[0m'

ok()  { echo -e "${GREEN}[ok]${NC} $1"; }
err() { echo -e "${RED}[err]${NC} $1"; }
info() { echo -e "     $1"; }

install_symlink() {
    for skill_dir in "$SOURCE_DIR"/*/; do
        [ -d "$skill_dir" ] || continue
        skill_name=$(basename "$skill_dir")
        target="$SKILLS_DIR/$skill_name"

        if [ -L "$target" ]; then
            current=$(readlink "$target")
            if [ "$current" = "$skill_dir" ]; then
                ok "$skill_name (already linked)"
                continue
            fi
            err "$skill_name symlink exists but points elsewhere: $current"
            exit 1
        elif [ -d "$target" ]; then
            err "$skill_name is a directory (not a symlink). Remove manually first."
            exit 1
        fi

        ln -s "$skill_dir" "$target"
        ok "$skill_name $(basename "$skill_dir") -> $skill_dir"
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
        target="$CLAUDE_SKILLS_DIR/$skill_name"

        if [ -L "$target" ]; then
            if [ "$(readlink "$target")" = "$skill_dir" ]; then
                ok "claude: $skill_name (already linked)"
                continue
            fi
            err "claude: $skill_name symlink exists but points elsewhere: $(readlink "$target")"
            exit 1
        elif [ -e "$target" ]; then
            err "claude: $skill_name exists and is not our symlink. Remove manually first."
            exit 1
        fi

        ln -s "$skill_dir" "$target"
        ok "claude: $skill_name -> $skill_dir"
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

    while IFS= read -r skill_md; do
        skill_dir=$(cd "$(dirname "$skill_md")" && pwd)
        skill_name=$(basename "$skill_dir")
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
}

mkdir -p "$SKILLS_DIR"
mkdir -p "$CLAUDE_SKILLS_DIR"

case "${1:-install}" in
    --symlink|-s) install_symlink; install_claude_symlink ;;
    --copy|-c)    install_copy; install_claude_copy ;;
    --remove|-r)  remove ;;
    install)      install_symlink; install_claude_symlink ;;  # default
    *)
        echo "Usage: $0 [--symlink|--copy|--remove]" >&2
        echo "  Default (no flag): symlink" >&2
        exit 1
        ;;
esac

echo ""
echo "Done. Restart your coding agent to pick up changes."
