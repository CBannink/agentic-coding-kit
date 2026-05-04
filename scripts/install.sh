#!/usr/bin/env bash
# install.sh -- Caspar Bannink Agentic Coding Kit installer (Mac/Linux/WSL).
#
# This is the bootstrap path for systems that don't have pwsh yet.
# Once pwsh is installed, prefer install.ps1's cleaner -For / -Auto API:
#   pwsh ./install.ps1 -For claude
#   pwsh ./install.ps1 -For all
#   pwsh ./install.ps1 -Auto
#
# Bash version usage:
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

# ── Pre-flight: PowerShell host detection ────────────────────────────────────
# The kit's runtime scripts require pwsh (or fall back to powershell.exe on
# Windows). Without one of them, lifecycle scripts silently no-op and the
# self-improvement loop breaks. Detect early and walk the user through install.
detect_powershell() {
    if command -v pwsh >/dev/null 2>&1; then
        echo "pwsh"
        return 0
    fi
    if command -v powershell.exe >/dev/null 2>&1; then
        echo "powershell.exe"
        return 0
    fi
    if command -v powershell >/dev/null 2>&1; then
        echo "powershell"
        return 0
    fi
    return 1
}

if ! PS_HOST=$(detect_powershell); then
    echo ""
    echo "######################################################################"
    echo "# Pre-flight FAIL: no PowerShell host detected                       #"
    echo "######################################################################"
    echo "# The kit's lifecycle scripts (state-init, workflow-evidence,        #"
    echo "# post-session, verify-writeback, hooks) all require pwsh.           #"
    echo "# Installing the kit without pwsh produces a silently-degraded      #"
    echo "# setup where the self-improvement loop is broken.                   #"
    echo "#                                                                     #"
    echo "# Install PowerShell 7+ first, then re-run this installer:           #"
    echo "#                                                                     #"
    case "$(uname -s)" in
        MINGW*|MSYS*|CYGWIN*) echo "#   Windows:  winget install Microsoft.PowerShell                    #" ;;
        Darwin)               echo "#   macOS:    brew install --cask powershell                         #" ;;
        Linux)
            echo "#   Linux:    https://learn.microsoft.com/en-us/powershell/                #"
            echo "#             scripting/install/installing-powershell-on-linux               #"
            ;;
        *) echo "#   See https://learn.microsoft.com/en-us/powershell/scripting/install/      #" ;;
    esac
    echo "#                                                                     #"
    echo "# After installing, verify with:  pwsh --version                     #"
    echo "# Then re-run:  ./scripts/install.sh $@                              #"
    echo "######################################################################"
    echo ""
    echo "To proceed in degraded mode anyway (lifecycle disabled), set"
    echo "  KIT_ALLOW_NO_PWSH=1"
    echo "and re-run. Not recommended."
    echo ""
    if [ "${KIT_ALLOW_NO_PWSH:-}" != "1" ]; then
        exit 1
    fi
    echo "KIT_ALLOW_NO_PWSH=1 set -- continuing in degraded mode."
    PS_HOST="(none)"
fi
echo "Detected PowerShell host: $PS_HOST"


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

# Global install -- everything kit-related lives under ~/.agents/.
copy_tree "$BUNDLE_GLOBAL/.agents" "$AGENTS_ROOT"

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
