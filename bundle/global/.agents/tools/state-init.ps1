#!/usr/bin/env pwsh
# state-init.ps1
# Initializes (or resets) the workflow state file for a build session.
# Called at the start of every /build Step 0.
#
# Usage:
#   state-init.ps1 -SessionId "abc123" -Task "add-auth-module" -Scope "SHARED"
#
# Writes: ${AGENTS_SESSION_ROOT}/{session_id}/state.json
# (defaults to ~/.agents/session-state)

param(
    [Parameter(Mandatory)][string]$SessionId,
    [Parameter(Mandatory)][string]$Task,
    [Parameter(Mandatory)][ValidateSet("ISOLATED","SHARED","CRITICAL")][string]$Scope,
    [string]$ScopeReason = ""
)

. (Join-Path $PSScriptRoot "_paths.ps1")

$stateDir = Get-SessionDir $SessionId
New-Item -ItemType Directory -Path $stateDir -Force | Out-Null

$statePath = Join-Path $stateDir "state.json"

$state = [ordered]@{
    session_id   = $SessionId
    task         = $Task
    scope        = $Scope
    scope_reason = $ScopeReason
    started_at   = (Get-Date -Format "o")
    current_step = 0
    gates        = [ordered]@{
        scope_classified            = $true
        context_loaded              = $false
        rubber_duck_consulted       = ($Scope -eq "ISOLATED")  # ISOLATED skips rubber-duck
        consequence_traced          = ($Scope -eq "ISOLATED")  # ISOLATED skips consequence
        implementation_done         = $false
        false_positive_verified     = $false
        test_quality_advised        = $false
        error_handling_advised      = $false
        verification_evidence       = $false
        handoff_written             = $false
    }
    agents_run    = @()
    skipped_agents = @()
    notes         = @()
}

$state | ConvertTo-Json -Depth 5 | Set-Content -Path $statePath -Encoding utf8
Sync-EvalArtifactMirror -SessionId $SessionId -SourcePath $statePath -TargetName "state.json"
Write-Host "✅ state.json initialized at $statePath"
Write-Output $statePath
