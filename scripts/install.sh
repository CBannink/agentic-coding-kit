#!/usr/bin/env bash
# install.sh -- thin Bash wrapper around install.ps1 (Mac/Linux/WSL).
#
# Keeps the old short-flag UX for shells that launch bash first, but PowerShell
# is now the canonical installer implementation and source of truth.
# Use install.ps1 directly when possible:
#   pwsh ./install-claude.ps1
#   pwsh ./install.ps1 -For all
#   pwsh ./install.ps1 -Auto
#
# Bash version usage:
#   ./install.sh                                    # global install only
#   ./install.sh -t /path/to/repo -r                # + repo template
#   ./install.sh -t /path/to/repo -r -a claude      # + Claude Code adapter
#   ./install.sh -t /path/to/repo -r -a all         # + all supported adapters
#
# Adapters: claude | codex | copilot | opencode | generic | all
# Requires a PowerShell host because the wrapper delegates to install.ps1.

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

# Pre-flight: PowerShell host detection
# The kit's runtime scripts require pwsh (or fall back to powershell.exe on
# Windows). Without one of them, lifecycle scripts silently no-op and the
# lifecycle helpers degrade. Detect early and walk the user through install.
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
    echo "# post-session and verification helpers require pwsh.                #"
    echo "# Installing the kit without pwsh produces a silently-degraded      #"
    echo "# setup where lifecycle helpers are unavailable.                     #"
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
    echo "install.sh now delegates to install.ps1, so a PowerShell host is mandatory."
    exit 1
fi
echo "Detected PowerShell host: $PS_HOST"


resolve_adapter() {
    case "$1" in
        claude)   echo "claude-code" ;;
        codex)    echo "codex-cli" ;;
        copilot)  echo "copilot-cli" ;;
        opencode) echo "opencode" ;;
        *)        echo "$1" ;;
    esac
}

PS_SCRIPT="$SCRIPT_DIR/install.ps1"
if [[ ! -f "$PS_SCRIPT" ]]; then
    echo "install.ps1 not found at $PS_SCRIPT"
    exit 1
fi

ps_args=(-NoProfile -File "$PS_SCRIPT" -HomeRoot "$HOME_ROOT")
if [[ -n "$TARGET_REPO" ]]; then
    ps_args+=(-TargetRepo "$TARGET_REPO")
fi
if [[ "$INSTALL_REPO_TEMPLATE" -eq 1 ]]; then
    ps_args+=(-InstallRepoTemplate)
fi
if [[ -n "$INSTALL_ADAPTER" ]]; then
    ps_args+=(-InstallAdapter "$(resolve_adapter "$INSTALL_ADAPTER")")
fi

exec "$PS_HOST" "${ps_args[@]}"
