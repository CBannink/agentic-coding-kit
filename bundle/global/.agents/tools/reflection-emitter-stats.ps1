#!/usr/bin/env pwsh
# reflection-emitter-stats.ps1 -- aggregate reflections by emitter agent.
#
# The kit currently scores findings (was X superseded?) but never aggregates
# by which agent emitted them. Without that, /reflect has no signal about
# WHICH agent is reliably noisy -- only that "some finding got dropped."
#
# This tool reads reflections.md (global + repo if present), parses entries
# tagged by emitter, and emits a leaderboard:
#   - findings_total per agent
#   - findings_superseded per agent
#   - supersession_rate (the noise score)
#
# Used by /reflect and the 30-day digest. Read-only -- never writes prompts.
#
# Output: Markdown table by default; -Json for machine consumption.

param(
    [int]$DaysBack = 30,
    [switch]$Json,
    [string]$RepoRoot = (Get-Location).Path
)

. (Join-Path $PSScriptRoot "_paths.ps1")

$globalReflections = Join-Path $env:USERPROFILE ".agents/context/reflections.md"
$repoReflections   = Join-Path $RepoRoot ".kit/context/reflections.md"

$cutoff = (Get-Date).AddDays(-$DaysBack)
$emitterStats = @{}

function Update-Stat {
    param([string]$Emitter, [bool]$Superseded)
    if (-not $emitterStats.ContainsKey($Emitter)) {
        $emitterStats[$Emitter] = [pscustomobject]@{
            agent       = $Emitter
            total       = 0
            superseded  = 0
        }
    }
    $emitterStats[$Emitter].total++
    if ($Superseded) { $emitterStats[$Emitter].superseded++ }
}

# Pattern matches the canonical reflection entry shape from post-session.ps1
# detectors plus historical [SUPERSEDED]/[FALSE-POSITIVE] markers from
# build-loop-gate output that gets harvested into reflections.
$entryPattern = '(?ms)^- \[(\d{4}-\d{2}-\d{2})\][^\n]*\n\s+(?:Pattern|Finding):\s*(.+?)(?:\n\s+(?:Evidence|Source|Emitter):\s*(.+?))?(?=\n-\s\[|\z)'
$emitterHints = @(
    'code-quality-reviewer','security-reviewer','modularity-expert',
    'adversarial-reviewer','final-verifier','spec-reviewer','qa-reviewer',
    'pr-reviewer','workflow-reviewer','workflow-skeptic','ux-driver','ui-driver'
)
$supersededMarkers = @('[SUPERSEDED]','[FALSE-POSITIVE]','[DOWNGRADED]')

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

        # Detect emitter from body or evidence
        $emitter = 'unattributed'
        foreach ($hint in $emitterHints) {
            if ($body -match [regex]::Escape($hint)) { $emitter = $hint; break }
        }

        # Detect supersession
        $superseded = $false
        foreach ($mk in $supersededMarkers) {
            if ($body -match [regex]::Escape($mk)) { $superseded = $true; break }
        }

        Update-Stat -Emitter $emitter -Superseded $superseded
    }
}

# Compute supersession rate; sort by noisiness (highest rate first, tiebreak total desc)
$rows = @()
foreach ($k in $emitterStats.Keys) {
    $s = $emitterStats[$k]
    $rate = if ($s.total -gt 0) { [Math]::Round(($s.superseded / $s.total) * 100, 1) } else { 0.0 }
    $rows += [pscustomobject]@{
        agent              = $s.agent
        total              = $s.total
        superseded         = $s.superseded
        supersession_rate  = $rate
    }
}
$rows = $rows | Sort-Object -Property @{Expression='supersession_rate'; Descending=$true}, @{Expression='total'; Descending=$true}

if ($Json) {
    @{
        days_back = $DaysBack
        cutoff    = $cutoff.ToString('o')
        rows      = $rows
        total_findings = ($rows | Measure-Object -Property total -Sum).Sum
    } | ConvertTo-Json -Depth 5 -Compress | Write-Output
    exit 0
}

# Markdown table
Write-Output ""
Write-Output "## Reflection emitter stats (last $DaysBack days)"
Write-Output ""
if ($rows.Count -eq 0) {
    Write-Output "_No reflection entries found in window._"
    exit 0
}
Write-Output "| Agent | Findings | Superseded | Supersession rate |"
Write-Output "|---|---:|---:|---:|"
foreach ($r in $rows) {
    $signal = if ($r.supersession_rate -ge 60) { ' <- VERY noisy' }
              elseif ($r.supersession_rate -ge 35) { ' <- noisy' }
              elseif ($r.supersession_rate -le 15 -and $r.total -ge 5) { ' <- trustworthy' }
              else { '' }
    Write-Output ("| {0} | {1} | {2} | {3}%{4} |" -f $r.agent, $r.total, $r.superseded, $r.supersession_rate, $signal)
}
exit 0
