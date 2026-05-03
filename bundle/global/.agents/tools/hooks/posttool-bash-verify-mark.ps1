#!/usr/bin/env pwsh
# posttool-bash-verify-mark.ps1 -- PostToolUse hook for Bash tool.
#
# Companion to pretool-bash-dispatcher.ps1. The pretool hook tags test
# commands by writing a .pending-verify-mark file. This hook runs after
# the Bash command completes; if there's a pending mark AND the command
# exited 0, AUTO-MARK verification_evidence in the session's state.json.
#
# Closes the Iron Law loop without orchestrator effort: agent runs tests,
# tests pass, gate marks itself, git commit hook unblocks. The agent
# never has to think about marking gates.
#
# Opt-out: KIT_DISABLED_HOOKS=verify-auto-mark

$ErrorActionPreference = "Continue"
. (Join-Path $PSScriptRoot "../_paths.ps1") -ErrorAction SilentlyContinue

$disabledHooks = if ($env:KIT_DISABLED_HOOKS) { @($env:KIT_DISABLED_HOOKS -split ',') } else { @() }
if ($disabledHooks -contains "verify-auto-mark") { exit 0 }

$rawInput = [Console]::In.ReadToEnd()
if (-not $rawInput) { exit 0 }
try {
    $payload = $rawInput | ConvertFrom-Json
} catch { exit 0 }

$sessionId = $payload.session_id
if (-not $sessionId) { exit 0 }

$sessDir = Join-Path $script:SessionRoot $sessionId
$markerFile = Join-Path $sessDir ".pending-verify-mark"
if (-not (Test-Path $markerFile)) { exit 0 }

# Read pending command for context, then delete the marker either way
$pendingCmd = ""
try { $pendingCmd = Get-Content $markerFile -Raw -Encoding UTF8 } catch {}
Remove-Item -Force $markerFile -ErrorAction SilentlyContinue

# Check the tool exit code from PostToolUse payload
$exitCode = if ($payload.tool_response.exit_code -ne $null) {
    [int]$payload.tool_response.exit_code
} elseif ($payload.tool_response.exitCode -ne $null) {
    [int]$payload.tool_response.exitCode
} else { -1 }

if ($exitCode -ne 0) {
    # Tests failed -- DO NOT mark the gate. Surface the fact for visibility.
    [Console]::Error.WriteLine("Kit hook (verify-auto-mark): test command exited $exitCode -- verification_evidence NOT marked.")
    exit 0
}

# Tests passed -- auto-record verification + mark the gate
$wfEvidence = Join-Path $script:Tools "workflow-evidence.ps1"
$cmdSummary = ($pendingCmd -replace '\s+', ' ').Trim()
if ($cmdSummary.Length -gt 80) { $cmdSummary = $cmdSummary.Substring(0, 80) }
if (Test-Path $wfEvidence) {
    try {
        & $script:AgentsShell -NoProfile -File $wfEvidence -SessionId $sessionId -AddVerification $cmdSummary 2>&1 | Out-Null
    } catch {}
}
$stateGate = Join-Path $script:Tools "state-gate.ps1"
if (Test-Path $stateGate) {
    try {
        & $script:AgentsShell -NoProfile -File $stateGate -SessionId $sessionId -Mark "verification_evidence" 2>&1 | Out-Null
        [Console]::Error.WriteLine("Kit hook (verify-auto-mark): tests passed -- verification_evidence gate marked automatically.")
    } catch {}
}

exit 0
