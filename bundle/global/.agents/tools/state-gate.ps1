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
    [int]$Step = -1,      # update current_step if provided
    [string]$Waiver = ""  # explicit reason to bypass filesystem-truth check on protected gates
)

. (Join-Path $PSScriptRoot "_paths.ps1")

# --- Filesystem-truth enforcement for protected gates -----------------
# The Iron Law applies to memory writebacks, not just code. When the model
# tries to mark a gate that REPRESENTS a writeback, this script verifies the
# writeback actually happened on disk. A model self-marking the gate without
# producing a fresh artifact is rejected.
#
# Protected gates and their required artifacts:
#   handoff_written        -> ~/.agents/session-state/<id>/handoffs.md mtime > session_start
#   implementation_done    -> .kit/context/memory.md OR shared.md mtime > session_start
#   verification_evidence  -> workflow-evidence.json has non-empty verification_commands
#
# Bypass with -Waiver "<reason>"; the waiver is logged.
# Disable globally with $env:AGENTS_ENFORCEMENT='off' (not recommended).
function Test-GateFilesystemTruth {
    param(
        [string]$GateName,
        [string]$SessionDir,
        [string]$WaiverReason
    )

    if ($env:AGENTS_ENFORCEMENT -eq 'off') { return $true }

    $protected = @('handoff_written', 'implementation_done', 'verification_evidence')
    if ($protected -notcontains $GateName) { return $true }

    if ($WaiverReason) {
        $waiverPath = Join-Path $SessionDir 'gate-waivers.jsonl'
        $waiverRec = [ordered]@{
            gate = $GateName
            reason = $WaiverReason
            at = (Get-Date -Format 'o')
        } | ConvertTo-Json -Compress
        Add-Content -Path $waiverPath -Value $waiverRec -Encoding utf8
        Write-Host "WAIVER  Gate '$GateName' bypassed: $WaiverReason"
        return $true
    }

    # Read session start timestamp from baseline.json (written by session-start-hook)
    $baselinePath = Join-Path $SessionDir 'baseline.json'
    $sessionStart = $null
    $repoRoot = ''
    if (Test-Path $baselinePath) {
        try {
            $baseline = Get-Content -Raw $baselinePath | ConvertFrom-Json
            $sessionStart = [DateTime]::Parse($baseline.session_start)
            $repoRoot = [string]$baseline.repo_root
        } catch {}
    }
    if (-not $sessionStart) {
        # Fall back to session dir creation time
        if (Test-Path $SessionDir) {
            $sessionStart = (Get-Item $SessionDir).CreationTime
        } else {
            $sessionStart = (Get-Date).AddHours(-24)
        }
    }

    switch ($GateName) {
        'handoff_written' {
            $hf = Join-Path $SessionDir 'handoffs.md'
            if (-not (Test-Path $hf)) {
                Write-Error "GATE BLOCKED: 'handoff_written' requires $hf to exist. None found. Pass -Waiver '<reason>' if intentionally skipping."
                return $false
            }
            $mtime = (Get-Item $hf).LastWriteTime
            if ($mtime -le $sessionStart) {
                Write-Error "GATE BLOCKED: 'handoff_written' requires $hf to be modified during this session. mtime=$mtime, session_start=$sessionStart. Write the handoff or pass -Waiver '<reason>'."
                return $false
            }
            $size = (Get-Item $hf).Length
            if ($size -lt 32) {
                Write-Error "GATE BLOCKED: '$hf' is suspiciously small ($size bytes). Empty/placeholder handoffs are rejected."
                return $false
            }
            return $true
        }
        'implementation_done' {
            if (-not $repoRoot -or -not (Test-Path $repoRoot)) {
                Write-Error "GATE BLOCKED: 'implementation_done' needs repo_root in baseline.json to verify .kit/context writes. Run session-start-hook with -RepoRoot, or pass -Waiver '<reason>' for non-repo work."
                return $false
            }
            $kitDir = Join-Path $repoRoot '.kit\context'
            if (-not (Test-Path $kitDir)) {
                Write-Error "GATE BLOCKED: 'implementation_done' requires .kit/context/ in '$repoRoot'. Run /kit-init or pass -Waiver 'no-kit'."
                return $false
            }
            $candidates = @(
                (Join-Path $kitDir 'memory.md'),
                (Join-Path $kitDir 'agent-memory\shared.md')
            )
            $touched = $false
            foreach ($c in $candidates) {
                if ((Test-Path $c) -and ((Get-Item $c).LastWriteTime -gt $sessionStart)) {
                    $touched = $true
                    break
                }
            }
            if (-not $touched) {
                Write-Error "GATE BLOCKED: 'implementation_done' requires at least one of $($candidates -join ' OR ') to be modified during this session. None were. Update durable memory with the architectural facts you learned, or pass -Waiver '<reason>' for trivial changes."
                return $false
            }
            return $true
        }
        'verification_evidence' {
            $evPath = Join-Path $SessionDir 'workflow-evidence.json'
            if (-not (Test-Path $evPath)) {
                Write-Error "GATE BLOCKED: 'verification_evidence' requires workflow-evidence.json with verification_commands."
                return $false
            }
            try {
                $ev = Get-Content -Raw $evPath | ConvertFrom-Json
                $cmds = @($ev.verification_commands)
                if ($cmds.Count -lt 1) {
                    Write-Error "GATE BLOCKED: 'verification_evidence' requires at least one verification command recorded. Use 'workflow-evidence.ps1 -AddVerification' as you run tests/builds, or pass -Waiver '<reason>'."
                    return $false
                }
            } catch {
                Write-Error "GATE BLOCKED: cannot parse $evPath. $_"
                return $false
            }
            return $true
        }
    }
    return $true
}

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
        # Filesystem-truth check: model claim must match disk state
        $sessionDir = Get-SessionDir $SessionId
        if (-not (Test-GateFilesystemTruth -GateName $Mark -SessionDir $sessionDir -WaiverReason $Waiver)) {
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
