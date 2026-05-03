#!/usr/bin/env pwsh
# pretool-task-orchestrator-gate.ps1 -- PreToolUse hook for the Task tool.
#
# When the orchestrator spawns a sub-agent via the Task tool, this hook
# AUTO-RUNS state-gate.ps1 -AddAgent and workflow-evidence.ps1 -AddAgent
# on the orchestrator's behalf. No agent thought required.
#
# This closes the empirical gap measured in our 2-agent precedence test:
# orchestrators consistently skip lifecycle bookkeeping under conversational
# pressure. Hooks fire deterministically -- the bookkeeping happens whether
# the agent thinks about it or not.
#
# This hook does NOT block dispatch. It allows the Task call through after
# recording the agent.
#
# Opt-out: KIT_DISABLED_HOOKS=task-orchestrator-gate

$ErrorActionPreference = "Continue"
. (Join-Path $PSScriptRoot "../_paths.ps1") -ErrorAction SilentlyContinue

$disabledHooks = if ($env:KIT_DISABLED_HOOKS) { @($env:KIT_DISABLED_HOOKS -split ',') } else { @() }
if ($disabledHooks -contains "task-orchestrator-gate") { exit 0 }

$rawInput = [Console]::In.ReadToEnd()
if (-not $rawInput) { exit 0 }
try {
    $payload = $rawInput | ConvertFrom-Json
} catch { exit 0 }

$sessionId = $payload.session_id
if (-not $sessionId) { exit 0 }

# Resolve sub-agent name from the Task tool input. Could be subagent_type
# or description (Claude Code's two ways of naming).
$agentName = $null
if ($payload.tool_input.subagent_type) { $agentName = [string]$payload.tool_input.subagent_type }
elseif ($payload.tool_input.description) {
    # Use first 30 chars of description as a synthetic agent identifier
    $desc = [string]$payload.tool_input.description
    $agentName = ($desc -replace '[^a-zA-Z0-9\s]', '' -replace '\s+', '-').ToLower()
    if ($agentName.Length -gt 30) { $agentName = $agentName.Substring(0, 30) }
}
if (-not $agentName) { exit 0 }

# Auto-run state-gate.ps1 -AddAgent
$stateGate = Join-Path $script:Tools "state-gate.ps1"
if (Test-Path $stateGate) {
    try {
        & $script:AgentsShell -NoProfile -File $stateGate -SessionId $sessionId -AddAgent $agentName -EnforceAgentCap 2>&1 | Out-Null
    } catch {
        # Don't block on tooling failure -- record-but-allow
    }
}

# Auto-run workflow-evidence.ps1 -AddAgent
$wfEvidence = Join-Path $script:Tools "workflow-evidence.ps1"
if (Test-Path $wfEvidence) {
    try {
        & $script:AgentsShell -NoProfile -File $wfEvidence -SessionId $sessionId -AddAgent "$agentName|auto-recorded by task-orchestrator-gate hook" 2>&1 | Out-Null
    } catch {}
}

exit 0
