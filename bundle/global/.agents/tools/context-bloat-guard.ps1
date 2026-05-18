#!/usr/bin/env pwsh
# context-bloat-guard.ps1
# Fast, lightweight checker that scans context files for line-count bloat.
# Designed to run from pre-session and mid-session hooks without blocking.
# Auto-triggers compress-memory.ps1 / auto-consolidate.ps1 when hard limits
# are exceeded and -AutoFix is set.
#
# Usage:
#   pwsh ~/.agents/tools/context-bloat-guard.ps1 [-RepoRoot <path>] [-SessionId <id>] [-AutoFix] [-Json]
#
# Output (default): one-line summary
#   context-bloat-guard: ok (6 files checked, 0 warnings, 0 critical)
#
# Output (-Json): JSON object (see schema in comments below)

param(
    [string]$RepoRoot  = "",
    [string]$SessionId = "",
    [switch]$AutoFix,
    [switch]$Json
)

. (Join-Path $PSScriptRoot "_paths.ps1")

if (-not $RepoRoot) { $RepoRoot = (Get-Location).Path }

# ---------------------------------------------------------------------------
# File table
# Each entry: Path (resolved), SoftLimit, HardLimit, HardAction
# HardAction values: "compress-memory" | "auto-consolidate" | "trim-handoffs" | "compress-memory" | "flag"
# ---------------------------------------------------------------------------
$fileTable = @(
    [pscustomobject]@{
        Key        = "repo-memory"
        Path       = Join-Path $RepoRoot ".kit/context/memory.md"
        SoftLimit  = 300
        HardLimit  = 500
        HardAction = "compress-memory"
    },
    [pscustomobject]@{
        Key        = "repo-reflections"
        Path       = Join-Path $RepoRoot ".kit/context/reflections.md"
        SoftLimit  = 50
        HardLimit  = 100
        HardAction = "auto-consolidate"
    },
    [pscustomobject]@{
        Key        = "repo-handoffs"
        Path       = Join-Path $RepoRoot ".kit/context/handoffs.md"
        SoftLimit  = 200
        HardLimit  = 400
        HardAction = "trim-handoffs"
    },
    [pscustomobject]@{
        Key        = "repo-history"
        Path       = Join-Path $RepoRoot ".kit/context/history.md"
        SoftLimit  = 300
        HardLimit  = 600
        HardAction = "compress-memory"
    },
    [pscustomobject]@{
        Key        = "global-reflections"
        Path       = Join-Path $script:AgentsRoot "context/reflections.md"
        SoftLimit  = 50
        HardLimit  = 100
        HardAction = "auto-consolidate"
    }
)

# Discover skill memory files dynamically
$skillDir = Join-Path $script:AgentsRoot "skills"
if (Test-Path $skillDir -PathType Container) {
    Get-ChildItem $skillDir -Directory | ForEach-Object {
        $smPath = Join-Path $_.FullName "memory.md"
        if (Test-Path $smPath) {
            $fileTable += [pscustomobject]@{
                Key        = "skill:$($_.Name)"
                Path       = $smPath
                SoftLimit  = 200
                HardLimit  = 400
                HardAction = "flag"
            }
        }
    }
}

# ---------------------------------------------------------------------------
# Check each file
# ---------------------------------------------------------------------------
$checks        = [System.Collections.ArrayList]::new()
$totalWarnings = 0
$totalCritical = 0
$autoFixRan    = $false
$recommendations = [System.Collections.ArrayList]::new()

function Invoke-TrimHandoffs {
    param([string]$Path, [int]$KeepCount)
    # Keep the newest $KeepCount entries; append the rest to handoffs.archive.md
    if (-not (Test-Path $Path)) { return $false }
    $lines   = Get-Content $Path -Encoding UTF8
    $archivePath = ($Path -replace '\.md$', '.archive.md')

    # Entries are delimited by lines starting with "SESSION:" or "## " or pipe-table rows.
    # Simplest safe approach: keep the last $KeepCount non-empty lines (entire file tail).
    # More precise: split on "SESSION:" markers.
    $entryStarts = @()
    for ($i = 0; $i -lt $lines.Count; $i++) {
        if ($lines[$i] -match "^SESSION:") { $entryStarts += $i }
    }

    if ($entryStarts.Count -le $KeepCount) { return $false }

    $trimCount  = $entryStarts.Count - $KeepCount
    $trimUntil  = $entryStarts[$trimCount] - 1   # last line before the first kept entry

    $toArchive = $lines[0..$trimUntil]
    $toKeep    = $lines[($trimUntil + 1)..($lines.Count - 1)]

    if (Test-Path $archivePath) {
        Add-Content -Path $archivePath -Value ("`n" + ($toArchive -join "`n")) -Encoding UTF8
    } else {
        Set-Content -Path $archivePath -Value ($toArchive -join "`n") -Encoding UTF8
    }
    Set-Content -Path $Path -Value ($toKeep -join "`n") -Encoding UTF8
    return $true
}

foreach ($entry in $fileTable) {
    $path      = $entry.Path
    $fileShort = $path   # display as-is; absolute paths are unambiguous

    if (-not (Test-Path $path)) {
        # File does not exist -- nothing to check, skip silently
        continue
    }

    $lineCount  = (Get-Content $path -Encoding UTF8 -ErrorAction SilentlyContinue).Count
    if ($null -eq $lineCount) { $lineCount = 0 }

    $status      = "ok"
    $actionTaken = "none"

    if ($lineCount -ge $entry.HardLimit) {
        $status = "hard"
        $totalCritical++

        if ($AutoFix) {
            switch ($entry.HardAction) {
                "compress-memory" {
                    & $script:AgentsShell -NoProfile -File (Join-Path $PSScriptRoot "compress-memory.ps1") `
                        -RepoRoot $RepoRoot 2>$null | Out-Null
                    $actionTaken = "auto-compressed"
                    $autoFixRan  = $true
                }
                "auto-consolidate" {
                    & $script:AgentsShell -NoProfile -File (Join-Path $PSScriptRoot "auto-consolidate.ps1") `
                        -RepoRoot $RepoRoot 2>$null | Out-Null
                    $actionTaken = "auto-consolidated"
                    $autoFixRan  = $true
                }
                "trim-handoffs" {
                    $trimmed = Invoke-TrimHandoffs -Path $path -KeepCount 200
                    $actionTaken = if ($trimmed) { "trimmed-handoffs" } else { "none" }
                    if ($trimmed) { $autoFixRan = $true }
                }
                "flag" {
                    $actionTaken = "flagged"
                    [void]$recommendations.Add("Run /reflect to consolidate skill memory ($($entry.Key), $lineCount lines)")
                }
            }
        } else {
            if ($entry.HardAction -eq "flag") {
                $actionTaken = "flagged"
                [void]$recommendations.Add("Run /reflect to consolidate skill memory ($($entry.Key), $lineCount lines)")
            }
        }

    } elseif ($lineCount -ge $entry.SoftLimit) {
        $status = "soft"
        $totalWarnings++
        [void]$recommendations.Add("$($entry.Key) approaching limit ($lineCount/$($entry.HardLimit) lines)")
    }

    [void]$checks.Add([ordered]@{
        file        = $fileShort
        lines       = $lineCount
        soft_limit  = $entry.SoftLimit
        hard_limit  = $entry.HardLimit
        status      = $status
        action_taken = $actionTaken
    })
}

# ---------------------------------------------------------------------------
# Derive overall status
# ---------------------------------------------------------------------------
$overallStatus = if ($totalCritical -gt 0) { "critical" }
                 elseif ($totalWarnings -gt 0) { "warn" }
                 else { "ok" }

$recommendationStr = if ($recommendations.Count -gt 0) {
    $recommendations[0]   # surface most actionable
} else {
    ""
}

$result = [ordered]@{
    status          = $overallStatus
    checks          = $checks
    total_warnings  = $totalWarnings
    total_critical  = $totalCritical
    auto_fix_ran    = $autoFixRan
    recommendation  = $recommendationStr
}

if ($Json) {
    Write-Output ($result | ConvertTo-Json -Depth 5 -Compress)
} else {
    $filesChecked = $checks.Count
    Write-Host "context-bloat-guard: $overallStatus ($filesChecked files checked, $totalWarnings warnings, $totalCritical critical)"
    if ($recommendations.Count -gt 0) {
        foreach ($r in $recommendations) { Write-Host "  Note: $r" }
    }
}

exit 0
