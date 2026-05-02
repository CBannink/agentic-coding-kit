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
# Exits 1 with a clear message if none are available.

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
    echo "ERROR: no PowerShell executable found on PATH (tried pwsh, powershell.exe, powershell)" >&2
    echo "Install pwsh: winget install Microsoft.PowerShell  OR  brew install --cask powershell" >&2
    exit 1
fi
