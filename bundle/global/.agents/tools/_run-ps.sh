#!/usr/bin/env bash
# _run-ps.sh -- pick the available PowerShell executable and exec the script.
# Used by Claude Code SessionStart/End/SubagentStop/PreCompact hooks because
# the hook shell (git-bash on Windows, sh on Mac/Linux) doesn't always have
# pwsh on PATH even when powershell.exe is installed.
#
# Usage from a hook command:
#   ~/.agents/tools/_run-ps.sh ~/.agents/tools/session-start-hook.ps1 -SessionId "$CLAUDE_SESSION_ID" -Mode build
#
# Resolution order:
#   1. pwsh (PowerShell 7+, cross-platform)
#   2. powershell.exe (Windows PowerShell 5.1, present on all Windows)
#   3. powershell (rare, but matches some setups)
#
# When NO PowerShell host is available, this used to fail silently from the
# orchestrator's perspective: the hook returned exit 1 with a stderr message
# that the model could ignore. Field reflection (May 2026) identified this as
# silent degradation -- agent fell back to ad-hoc commits and never re-engaged
# the lifecycle. Mitigation:
#   1. Write a sentinel file at ~/.agents/KIT-DEGRADED.txt with timestamp+reason.
#   2. Print a multi-line banner to stderr that's hard to ignore.
#   3. The canonical instructions tell the model to check the sentinel on first
#      turn and warn the user before proceeding.

if [ "$#" -lt 1 ]; then
    echo "usage: $0 <script.ps1> [args...]" >&2
    exit 1
fi

if command -v pwsh >/dev/null 2>&1; then
    exec pwsh -NoProfile -File "$@"
elif command -v powershell.exe >/dev/null 2>&1; then
    exec powershell.exe -NoProfile -File "$@"
elif command -v powershell >/dev/null 2>&1; then
    exec powershell -NoProfile -File "$@"
else
    AGENTS_DIR="${AGENTS_HOME:-$HOME/.agents}"
    SENTINEL="$AGENTS_DIR/KIT-DEGRADED.txt"
    mkdir -p "$AGENTS_DIR" 2>/dev/null
    {
        echo "KIT-DEGRADED"
        echo "timestamp: $(date -u +%Y-%m-%dT%H:%M:%SZ)"
        echo "reason: no PowerShell executable on PATH (tried pwsh, powershell.exe, powershell)"
        echo "impact: state-init.ps1, workflow-evidence.ps1, post-session.ps1, verify-writeback.ps1, and all hooks are unavailable"
        echo "remediation: install pwsh"
        echo "  Windows:  winget install Microsoft.PowerShell"
        echo "  macOS:    brew install --cask powershell"
        echo "  Linux:    https://learn.microsoft.com/en-us/powershell/scripting/install/installing-powershell-on-linux"
    } > "$SENTINEL"

    {
        echo ""
        echo "######################################################################"
        echo "# KIT-DEGRADED -- no PowerShell host available                       #"
        echo "######################################################################"
        echo "# Tried: pwsh, powershell.exe, powershell -- all missing on PATH.    #"
        echo "# All kit lifecycle scripts (state-init, workflow-evidence,           #"
        echo "# post-session, verify-writeback, hooks) cannot run.                  #"
        echo "#                                                                     #"
        echo "# Sentinel written to: $SENTINEL"
        echo "#                                                                     #"
        echo "# Install PowerShell:                                                 #"
        echo "#   Windows:  winget install Microsoft.PowerShell                     #"
        echo "#   macOS:    brew install --cask powershell                          #"
        echo "######################################################################"
        echo ""
    } >&2
    exit 1
fi
