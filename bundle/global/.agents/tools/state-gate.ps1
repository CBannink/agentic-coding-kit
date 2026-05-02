#!/usr/bin/env pwsh
# state-gate.ps1
# Checks that a required gate in state.json is marked as passed.
# If the gate is NOT passed, prints an error and exits with code 1 -- hard stop.
# Use this before any BLOCKING step to make enforcement mechanical.
#
# Usage:
#   state-gate.ps1 -SessionId "abc123" -Gate "rubber_duck_consulted"
#   state-gate.ps1 -SessionId "abc123" -Gate "false_positive_verified"
#   state-gate.ps1 -SessionId "abc123" -Mark "rubber_duck_consulted"  # mark gate as passed
#   state-gate.ps1 -SessionId "abc123" -Mark "implementation_done" -AddAgent "implementer"
#
# Gates:
#   scope_classified, context_loaded, rubber_duck_consulted, consequence_traced,
#   implementation_done, false_positive_verified, test_quality_advised,
#   error_handling_advised, verification_evidence, handoff_written

param(
    [Parameter(Mandatory)][string]$SessionId,
    [string]$Gate,        # check that this gate is true
    [string]$Mark,        # mark this gate as true
    [string]$AddAgent,    # add agent name to agents_run list
    [string]$SkipAgent,   # add agent name to skipped_agents list
    [switch]$EnforceAgentCap,
    [int]$Step = -1       # update current_step if provided
)

. (Join-Path $PSScriptRoot "_paths.ps1")

$statePath = Join-Path (Get-SessionDir $SessionId) "state.json"

if (-not (Test-Path $statePath)) {
    Write-Error "❌ state.json not found at $statePath -- was state-init.ps1 run?"
    exit 1
}

$state = Get-Content $statePath -Raw | ConvertFrom-Json

function Save-State($stateObj, $path) {
    $stateObj | ConvertTo-Json -Depth 5 | Set-Content -Path $path -Encoding utf8
}

function Get-AgentCap([string]$sessionId, $stateObj) {
    # SWARM is opt-in only and runs parallel fan-out -- higher cap.
    $tierCaps = @{ INLINE = 0; TARGETED = 6; FULL = 12; SWARM = 24 }
    $evidencePath = Join-Path (Get-SessionDir $sessionId) "workflow-evidence.json"
    $metaPath = Join-Path (Get-SessionDir $sessionId) "session-meta.json"

    if (Test-Path $evidencePath) {
        try {
            $evidence = Get-Content $evidencePath -Raw | ConvertFrom-Json
            if ($evidence.tier -and $tierCaps.ContainsKey($evidence.tier)) {
                return $tierCaps[$evidence.tier]
            }
        } catch {}
    }

    if (Test-Path $metaPath) {
        try {
            $meta = Get-Content $metaPath -Raw | ConvertFrom-Json
            if ($meta.tier_rec -and $tierCaps.ContainsKey($meta.tier_rec)) {
                return $tierCaps[$meta.tier_rec]
            }
        } catch {}
    }

    $scopeCaps = @{ ISOLATED = 0; SHARED = 6; CRITICAL = 12 }
    if ($scopeCaps.ContainsKey($stateObj.scope)) {
        return $scopeCaps[$stateObj.scope]
    }

    return 6
}

# --- Mutating actions: mark gate / register agent / register skip ---
if ($Mark -or $AddAgent -or $SkipAgent) {
    if ($Mark) {
        if ($null -eq $state.gates.$Mark) {
            Write-Error "❌ Unknown gate: '$Mark'. Valid gates: $($state.gates.PSObject.Properties.Name -join ', ')"
            exit 1
        }
        $state.gates.$Mark = $true
    }
    if ($AddAgent -and $state.agents_run -notcontains $AddAgent) {
        $state.agents_run += $AddAgent
    }
    if ($SkipAgent -and $state.skipped_agents -notcontains $SkipAgent) {
        $state.skipped_agents += $SkipAgent
    }
    if ($Step -ge 0) {
        $state.current_step = $Step
    }
    Save-State $state $statePath

    if ($AddAgent -and $EnforceAgentCap) {
        $cap = Get-AgentCap $SessionId $state
        $count = @($state.agents_run).Count
        if ($count -gt $cap) {
            Write-Error "🚫 AGENT CAP EXCEEDED: $count agents registered, tier cap is $cap."
            exit 1
        }
    }

    if ($Mark) {
        Write-Host "✅ Gate '$Mark' marked as passed"
    } elseif ($AddAgent) {
        $cap = Get-AgentCap $SessionId $state
        $count = @($state.agents_run).Count
        Write-Host "✅ Agent '$AddAgent' registered ($count/$cap)"
    } elseif ($SkipAgent) {
        Write-Host "✅ Agent '$SkipAgent' recorded as skipped"
    }
    exit 0
}

# --- Check a gate is passed ---
if ($Gate) {
    if ($null -eq $state.gates.$Gate) {
        Write-Error "❌ Unknown gate: '$Gate'. Valid gates: $($state.gates.PSObject.Properties.Name -join ', ')"
        exit 1
    }
    if ($state.gates.$Gate -eq $true) {
        Write-Host "✅ Gate '$Gate' passed (scope: $($state.scope))"
        exit 0
    } else {
        Write-Error "🚫 GATE BLOCKED: '$Gate' has not been completed. Do not proceed past this step."
        Write-Error "   Current step: $($state.current_step) | Scope: $($state.scope) | Task: $($state.task)"
        exit 1
    }
}

# --- No action -- print state summary ---
Write-Host "📋 Build state for session: $SessionId"
Write-Host "   Task:  $($state.task)"
Write-Host "   Scope: $($state.scope) ($($state.scope_reason))"
Write-Host "   Step:  $($state.current_step)"
Write-Host "   Gates:"
foreach ($g in $state.gates.PSObject.Properties) {
    $icon = if ($g.Value) { "✅" } else { "⬜" }
    Write-Host "     $icon $($g.Name)"
}
if ($state.agents_run.Count -gt 0) {
    Write-Host "   Agents run: $($state.agents_run -join ', ')"
}
if ($state.skipped_agents.Count -gt 0) {
    Write-Host "   Skipped:    $($state.skipped_agents -join ', ')"
}
