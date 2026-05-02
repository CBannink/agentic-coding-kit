#!/usr/bin/env bash
# install.sh -- Caspar Bannink Agentic Coding Kit installer (Mac/Linux/WSL).
#
# Usage:
#   ./install.sh                                    # global install only
#   ./install.sh -t /path/to/repo -r                # + repo template
#   ./install.sh -t /path/to/repo -r -a claude      # + Claude Code adapter
#   ./install.sh -t /path/to/repo -r -a all         # + all adapters
#
# Adapters: claude | codex | copilot | opencode | kilocode | generic | all
# Requires PowerShell 7+ (`pwsh`) for the runtime tools. Installer itself is bash.

set -euo pipefail

HOME_ROOT="${HOME}"
TARGET_REPO=""
INSTALL_REPO_TEMPLATE=0
INSTALL_ADAPTER=""

while getopts "h:t:ra:" opt; do
    case $opt in
        h) HOME_ROOT="$OPTARG" ;;
        t) TARGET_REPO="$OPTARG" ;;
        r) INSTALL_REPO_TEMPLATE=1 ;;
        a) INSTALL_ADAPTER="$OPTARG" ;;
        *) echo "Usage: $0 [-h home] [-t target-repo] [-r] [-a adapter]"; exit 1 ;;
    esac
done

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
BUNDLE_GLOBAL="$REPO_ROOT/bundle/global"
BUNDLE_REPO="$REPO_ROOT/bundle/repo-template"
ADAPTERS_ROOT="$REPO_ROOT/bundle/adapters"

AGENTS_ROOT="$HOME_ROOT/.agents"

copy_tree() {
    local src="$1" dst="$2"
    [[ -d "$src" ]] || return 0
    mkdir -p "$dst"
    # Copy contents (including dotfiles) without preserving an extra layer
    cp -R "$src/." "$dst/"
}

render_template() {
    local src="$1" dst="$2" agents_root="$3"
    [[ -f "$src" ]] || return 0
    mkdir -p "$(dirname "$dst")"
    sed "s|__AGENTS_ROOT__|$agents_root|g" "$src" > "$dst"
}

install_adapter() {
    local name="$1" target="$2"
    local src="$ADAPTERS_ROOT/$name"
    if [[ ! -d "$src" ]]; then
        echo "  Adapter '$name' not found at $src -- skipping"
        return
    fi
    copy_tree "$src" "$target"
    echo "  Installed '$name' adapter into $target"
}

resolve_adapter() {
    case "$1" in
        claude)   echo "claude-code" ;;
        codex)    echo "codex-cli" ;;
        copilot)  echo "copilot-cli" ;;
        opencode) echo "opencode" ;;
        kilocode|kilo) echo "kilocode" ;;
        *)        echo "$1" ;;
    esac
}

# Global install
copy_tree "$BUNDLE_GLOBAL/.agents" "$AGENTS_ROOT"
copy_tree "$BUNDLE_GLOBAL/.codex"  "$HOME_ROOT/.codex"

# Render skill-memory-index.json from template with absolute paths
TMPL="$AGENTS_ROOT/context/skill-memory-index.json.tmpl"
OUT="$AGENTS_ROOT/context/skill-memory-index.json"
if [[ -f "$TMPL" ]]; then
    render_template "$TMPL" "$OUT" "$AGENTS_ROOT"
    rm -f "$TMPL"
    echo "  Rendered skill-memory-index.json with AGENTS_ROOT=$AGENTS_ROOT"
fi

echo "Installed global assets into $HOME_ROOT"

# Repo template
if [[ -n "$TARGET_REPO" && "$INSTALL_REPO_TEMPLATE" -eq 1 ]]; then
    copy_tree "$BUNDLE_REPO" "$TARGET_REPO"
    echo "Installed repo template into $TARGET_REPO"
fi

# Adapters
if [[ -n "$TARGET_REPO" && -n "$INSTALL_ADAPTER" ]]; then
    if [[ "$INSTALL_ADAPTER" == "all" ]]; then
        adapters=(claude-code codex-cli copilot-cli opencode kilocode generic)
    else
        adapters=("$(resolve_adapter "$INSTALL_ADAPTER")")
    fi
    for a in "${adapters[@]}"; do
        install_adapter "$a" "$TARGET_REPO"
    done
fi

if [[ -z "$TARGET_REPO" ]]; then
    echo
    echo "Global install complete."
    echo "Next: bootstrap a repo with:"
    echo "  ./install.sh -t <path> -r -a all"
fi
