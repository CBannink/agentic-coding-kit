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

function Block-WithReason {
    param([string]$Reason)
    [Console]::Error.WriteLine($Reason)
    exit 2
}

function Get-JsonFile {
    param([string]$Path)
    if (-not (Test-Path $Path)) { return $null }
    try {
        return Get-Content $Path -Raw -Encoding UTF8 | ConvertFrom-Json
    } catch {
        return $null
    }
}

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

$sessionDir = Join-Path $script:SessionRoot $sessionId
$state = Get-JsonFile -Path (Join-Path $sessionDir "state.json")
$runPacket = Get-JsonFile -Path (Join-Path $sessionDir "run-packet.json")
$planPath = Join-Path $sessionDir "plan.md"

$isImplementer = $agentName -match '(^|-)workflow-implementer$|(^|-)implementer$'
$needsApprovedPlan =
    $isImplementer -and
    $state -and
    (@("SHARED", "CRITICAL") -contains [string]$state.scope)

if ($needsApprovedPlan) {
    $approvalStatus = if ($runPacket) { [string]$runPacket.approval_status } else { "" }
    $planApproved = $approvalStatus -ieq "approved"
    if ((-not $planApproved) -or (-not (Test-Path $planPath))) {
        Block-WithReason @"
Blocked by kit hook (task-orchestrator-gate/plan-approval):

This session attempted to spawn $agentName before the build contract was
approved. For SHARED and CRITICAL build work, the plan must exist at
~/.agents/session-state/$sessionId/plan.md and run-packet.json must record
approval_status = approved before implementation starts.

To resolve:
  1. Run /plan (or refresh the existing plan) for this same session.
  2. Record approval in run-packet.json.
  3. Retry the implementer spawn.

To bypass entirely:
  Set KIT_DISABLED_HOOKS=task-orchestrator-gate and retry the Task call.
"@
    }
}

# Auto-run state-gate.ps1 -AddAgent
$stateGate = Join-Path $script:Tools "state-gate.ps1"
if (Test-Path $stateGate) {
    try {
        if ($needsApprovedPlan -and -not $state.gates.plan_approved) {
            & $script:AgentsShell -NoProfile -File $stateGate -SessionId $sessionId -Mark "plan_approved" 2>&1 | Out-Null
        }
        $addAgentOutput = & $script:AgentsShell -NoProfile -File $stateGate -SessionId $sessionId -AddAgent $agentName -EnforceAgentCap 2>&1
        if ($LASTEXITCODE -ne 0) {
            $details = ($addAgentOutput | Out-String).Trim()
            if (-not $details) {
                $details = "state-gate.ps1 rejected agent registration."
            }
            Block-WithReason @"
Blocked by kit hook (task-orchestrator-gate/agent-cap):

$details
"@
        }
    } catch {
        Block-WithReason "Blocked by kit hook (task-orchestrator-gate/state): failed to register '$agentName' in state-gate.ps1. $($_.Exception.Message)"
    }
}

# Auto-run workflow-evidence.ps1 -AddAgent
$wfEvidence = Join-Path $script:Tools "workflow-evidence.ps1"
if (Test-Path $wfEvidence) {
    try {
        & $script:AgentsShell -NoProfile -File $wfEvidence -SessionId $sessionId -AddAgent $agentName 2>&1 | Out-Null
    } catch {}
}

exit 0
