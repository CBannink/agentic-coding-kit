#!/usr/bin/env pwsh
# agent-trust-scorer.ps1 -- generate trust context for agent prompt injection.
#
# Reads reflection history, scores agent reliability, and outputs a prompt
# block that orchestrators inject when spawning subagents. Agents with high
# false-positive rates get calibration context; reliable agents get reinforcement.
#
# Usage:
#   agent-trust-scorer.ps1 -Role code-quality-reviewer
#   agent-trust-scorer.ps1 -Role adversarial-reviewer -DaysBack 30
#   agent-trust-scorer.ps1 -All -Json
#
# Output: prompt_block (text) or JSON with scores + prompt_block per agent

param(
    [string]$Role,
    [int]$DaysBack = 30,
    [string]$RepoRoot = (Get-Location).Path,
    [switch]$All,
    [switch]$Json
)

. (Join-Path $PSScriptRoot "_paths.ps1")

$globalReflections = Join-Path $env:USERPROFILE ".agents/context/reflections.md"
$repoReflections   = Join-Path $RepoRoot ".kit/context/reflections.md"

$cutoff = (Get-Date).AddDays(-$DaysBack)
$emitterStats = @{}

function Update-Stat {
    param([string]$Emitter, [bool]$Superseded, [bool]$Confirmed)
    if (-not $emitterStats.ContainsKey($Emitter)) {
        $emitterStats[$Emitter] = [pscustomobject]@{
            agent     = $Emitter
            total     = 0
            superseded = 0
            confirmed  = 0
        }
    }
    $emitterStats[$Emitter].total++
    if ($Superseded) { $emitterStats[$Emitter].superseded++ }
    if ($Confirmed)  { $emitterStats[$Emitter].confirmed++ }
}

# Same entry pattern as reflection-emitter-stats.ps1
$entryPattern = '(?ms)^- \[(\d{4}-\d{2}-\d{2})\][^\n]*\n\s+(?:Pattern|Finding):\s*(.+?)(?:\n\s+(?:Evidence|Source|Emitter):\s*(.+?))?(?=\n-\s\[|\z)'

$knownRoles = @(
    'code-quality-reviewer','security-reviewer','modularity-expert',
    'adversarial-reviewer','final-verifier','spec-reviewer','qa-reviewer',
    'pr-reviewer','workflow-reviewer','workflow-skeptic','ux-driver','ui-driver'
)

$supersededMarkers = @('[SUPERSEDED]','[FALSE-POSITIVE]','[DOWNGRADED]')
$confirmedMarkers  = @('[CONFIRMED]','[APPLIED]','[FIXED]')

foreach ($path in @($globalReflections, $repoReflections)) {
    if (-not (Test-Path $path)) { continue }
    $content = Get-Content $path -Raw -Encoding UTF8
    foreach ($m in [regex]::Matches($content, $entryPattern)) {
        $dateStr = $m.Groups[1].Value
        $body    = $m.Groups[2].Value + " " + $m.Groups[3].Value
        try {
            $entryDate = [datetime]::Parse($dateStr)
            if ($entryDate -lt $cutoff) { continue }
        } catch { continue }

        # Detect emitter from body or evidence line
        $emitter = 'unattributed'
        foreach ($hint in $knownRoles) {
            if ($body -match [regex]::Escape($hint)) { $emitter = $hint; break }
        }

        $superseded = $false
        foreach ($mk in $supersededMarkers) {
            if ($body -match [regex]::Escape($mk)) { $superseded = $true; break }
        }

        $confirmed = $false
        foreach ($mk in $confirmedMarkers) {
            if ($body -match [regex]::Escape($mk)) { $confirmed = $true; break }
        }

        Update-Stat -Emitter $emitter -Superseded $superseded -Confirmed $confirmed
    }
}

# ---------------------------------------------------------------------------
# Score computation
# ---------------------------------------------------------------------------

function Get-TrustScore {
    param([pscustomobject]$Stats)
    if ($Stats.total -eq 0) { return $null }
    $rate = $Stats.superseded / $Stats.total
    return [Math]::Round([Math]::Max(0.0, [Math]::Min(1.0, 1.0 - $rate)), 4)
}

function Get-Tier {
    param([nullable[double]]$Score, [int]$Total)
    if ($null -eq $Score)           { return 'no-data' }
    if ($Total -lt 5)               { return 'high' }   # insufficient data; default high
    if ($Score -ge 0.8)             { return 'high' }
    if ($Score -ge 0.4)             { return 'medium' }
    return 'low'
}

function Build-PromptBlock {
    param([string]$AgentRole, [nullable[double]]$Score, [string]$Tier,
          [int]$Total, [int]$Superseded, [int]$Confirmed)

    $supersessionPct = if ($Total -gt 0) {
        [Math]::Round(($Superseded / $Total) * 100, 1)
    } else { 0.0 }

    switch ($Tier) {
        'high' {
            if ($Total -lt 5) {
                return @"
## Trust context
No sufficient historical data for agent role '$AgentRole' in this repo ($Total findings recorded). Default to balanced precision -- flag concrete issues, skip speculative ones.
"@
            }
            $scoreDisplay = [Math]::Round($Score, 2)
            return @"
## Trust context
Your findings in this repo have been consistently actionable (trust score: $scoreDisplay, $Confirmed/$Total confirmed). Continue at current precision level.
"@
        }
        'medium' {
            $scoreDisplay = [Math]::Round($Score, 2)
            return @"
## Trust context
Your recent findings have a $($supersessionPct)% supersession rate ($Superseded/$Total findings were downgraded or marked false-positive). Before flagging an issue:
1. Verify the finding is backed by a concrete code path, not a theoretical possibility
2. Check if the pattern is intentional in this repo (see .kit/context/agent-memory/$AgentRole.md)
3. Prefer silence over a speculative finding
"@
        }
        'low' {
            return @"
## Trust context
WARNING: $($supersessionPct)% of your recent findings were superseded or marked false-positive ($Superseded/$Total). Your signal-to-noise ratio needs improvement. Apply strict filters:
1. Only flag findings you can trace to a specific file:line with a concrete failure mode
2. Skip style, naming, and theoretical concerns entirely
3. If in doubt, do NOT flag it -- false positives cost more than missed findings in this repo
"@
        }
        default {
            return @"
## Trust context
No historical data for this agent role in this repo. Default to balanced precision -- flag concrete issues, skip speculative ones.
"@
        }
    }
}

# ---------------------------------------------------------------------------
# -All -Json output
# ---------------------------------------------------------------------------

if ($All -and $Json) {
    $agents = @{}
    $overrides = @{}

    $roles = if ($emitterStats.Count -gt 0) { $emitterStats.Keys } else { @() }

    foreach ($r in $roles) {
        $s = $emitterStats[$r]
        $score = Get-TrustScore -Stats $s
        $tier  = Get-Tier -Score $score -Total $s.total
        $rate  = if ($s.total -gt 0) { [Math]::Round($s.superseded / $s.total, 4) } else { 0.0 }

        $agents[$r] = [ordered]@{
            total             = $s.total
            superseded        = $s.superseded
            confirmed         = $s.confirmed
            supersession_rate = $rate
            trust_score       = if ($null -ne $score) { $score } else { $null }
            tier              = $tier
            prompt_block      = Build-PromptBlock -AgentRole $r -Score $score -Tier $tier `
                                    -Total $s.total -Superseded $s.superseded -Confirmed $s.confirmed
        }

        if ($null -ne $score -and $score -lt 0.4) {
            $overrides[$r] = [ordered]@{
                downgrade = $true
                reason    = "trust_score $score < 0.4"
            }
        }
    }

    @{
        agents                  = $agents
        model_routing_overrides = $overrides
    } | ConvertTo-Json -Depth 6 | Write-Output
    exit 0
}

# ---------------------------------------------------------------------------
# Single-role output
# ---------------------------------------------------------------------------

if ($Role) {
    $s = if ($emitterStats.ContainsKey($Role)) { $emitterStats[$Role] } else {
        [pscustomobject]@{ agent = $Role; total = 0; superseded = 0; confirmed = 0 }
    }
    $score = Get-TrustScore -Stats $s
    $tier  = Get-Tier -Score $score -Total $s.total

    if ($Json) {
        $rate = if ($s.total -gt 0) { [Math]::Round($s.superseded / $s.total, 4) } else { 0.0 }
        [ordered]@{
            role              = $Role
            total             = $s.total
            superseded        = $s.superseded
            confirmed         = $s.confirmed
            supersession_rate = $rate
            trust_score       = if ($null -ne $score) { $score } else { $null }
            tier              = $tier
            prompt_block      = Build-PromptBlock -AgentRole $Role -Score $score -Tier $tier `
                                    -Total $s.total -Superseded $s.superseded -Confirmed $s.confirmed
        } | ConvertTo-Json -Depth 4 | Write-Output
    } else {
        Build-PromptBlock -AgentRole $Role -Score $score -Tier $tier `
            -Total $s.total -Superseded $s.superseded -Confirmed $s.confirmed | Write-Output
    }
    exit 0
}

# ---------------------------------------------------------------------------
# Default: markdown table for all known agents found in reflections
# ---------------------------------------------------------------------------

if ($emitterStats.Count -eq 0) {
    Write-Output "No reflection entries found in the last $DaysBack days."
    exit 0
}

$rows = @()
foreach ($k in $emitterStats.Keys) {
    $s     = $emitterStats[$k]
    $score = Get-TrustScore -Stats $s
    $tier  = Get-Tier -Score $score -Total $s.total
    $rate  = if ($s.total -gt 0) { [Math]::Round(($s.superseded / $s.total) * 100, 1) } else { 0.0 }
    $rows += [pscustomobject]@{
        agent             = $s.agent
        total             = $s.total
        superseded        = $s.superseded
        confirmed         = $s.confirmed
        supersession_rate = $rate
        trust_score       = if ($null -ne $score) { [Math]::Round($score, 2) } else { 'n/a' }
        tier              = $tier
    }
}
$rows = $rows | Sort-Object -Property @{Expression='trust_score'; Descending=$false}, @{Expression='total'; Descending=$true}

Write-Output ""
Write-Output "## Agent trust scores (last $DaysBack days)"
Write-Output ""
Write-Output "| Agent | Total | Superseded | Confirmed | Supersession% | Trust score | Tier |"
Write-Output "|---|---:|---:|---:|---:|---:|---|"
foreach ($r in $rows) {
    $signal = switch ($r.tier) {
        'low'    { ' <- NOISY' }
        'medium' { ' <- needs calibration' }
        'high'   { ' <- reliable' }
        default  { '' }
    }
    Write-Output ("| {0} | {1} | {2} | {3} | {4}% | {5}{6} | {7} |" -f `
        $r.agent, $r.total, $r.superseded, $r.confirmed, `
        $r.supersession_rate, $r.trust_score, $signal, $r.tier)
}

exit 0
