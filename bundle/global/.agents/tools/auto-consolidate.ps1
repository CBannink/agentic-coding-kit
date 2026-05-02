#!/usr/bin/env pwsh
# auto-consolidate.ps1
# Mechanical pass over reflections.md (repo + global) that runs the agent-less
# parts of /reflect. Closes the self-improvement loop without requiring an
# explicit /reflect invocation for routine cleanup.
#
# What it does (deterministic, judgment-free):
#   1. DEDUP    -- merge identical {class, pattern} entries; increment count in evidence
#   2. ARCHIVE  -- drop entries whose pattern appears in memory.md as "Promoted:" line
#   3. STALE    -- drop single-occurrence entries older than -StaleDays (default 30)
#   4. PROMOTE  -- auto-promote class=additive entries with count >= 2 by appending
#                  a marked block to the suggested target file, then archive
#
# What it does NOT do (still requires /reflect with an agent):
#   - class=gating/routing/verification entries (changes workflow contracts -- judgment)
#   - cross-scope decisions (repo-local vs global)
#   - any rewording of pattern text
#
# Output: JSON summary of actions taken. Always exits 0 unless input parsing fails.

param(
    [string]$RepoRoot   = "",
    [int]$StaleDays     = 30,
    [int]$PromoteThreshold = 2,
    [switch]$DryRun,
    [switch]$Json
)

. (Join-Path $PSScriptRoot "_paths.ps1")

if (-not $RepoRoot) { $RepoRoot = (Get-Location).Path }

$repoPath   = Join-Path $RepoRoot ".kit/context/reflections.md"
$globalPath = Join-Path $script:AgentsRoot "context/reflections.md"
$memoryPath = Join-Path $RepoRoot ".kit/context/memory.md"

$summary = [ordered]@{
    started_with    = 0
    deduped         = 0
    archived        = 0
    stale_dropped   = 0
    auto_promoted   = 0
    remaining       = 0
    dry_run         = [bool]$DryRun
    actions         = [System.Collections.ArrayList]::new()
}

function Read-MemoryPromotedPatterns {
    if (-not (Test-Path $memoryPath)) { return @() }
    $patterns = @()
    foreach ($line in Get-Content $memoryPath -Encoding UTF8) {
        if ($line -match "^\s*\[\d{4}-\d{2}-\d{2}\]\s+Promoted:\s+(.+?)(\s+->\s+|$)") {
            $patterns += $Matches[1].Trim()
        }
    }
    return $patterns
}

function Parse-Entries([string]$path) {
    if (-not (Test-Path $path)) { return @() }
    $entries = @()
    $lines = Get-Content $path -Encoding UTF8
    $current = $null
    for ($i = 0; $i -lt $lines.Count; $i++) {
        $l = $lines[$i]
        if ($l -match "^- \[(\d{4}-\d{2}-\d{2})\].*?\[class:([^\]]+)\]") {
            if ($current) { $entries += $current }
            $current = [pscustomobject]@{
                date     = $Matches[1]
                class    = $Matches[2]
                header   = $l
                pattern  = ""
                evidence = ""
                target   = ""
                start_line = $i
                end_line   = $i
                count    = 1
            }
        } elseif ($current) {
            if ($l -match "^\s*Pattern:\s*(.*)$")           { $current.pattern  = $Matches[1].Trim(); $current.end_line = $i }
            elseif ($l -match "^\s*Evidence:\s*(.*)$")      { $current.evidence = $Matches[1].Trim(); $current.end_line = $i }
            elseif ($l -match "^\s*Suggested target:\s*(.*)$") { $current.target = $Matches[1].Trim(); $current.end_line = $i }
            elseif ($l -match "^- \[" -or $l -match "^##\s") {
                $entries += $current; $current = $null; $i--
            } elseif ($l.Trim() -eq "" -and $current.pattern) {
                # blank line after content = entry closed
                $entries += $current; $current = $null
            }
        }
    }
    if ($current) { $entries += $current }
    return @($entries | Where-Object { $_.pattern })
}

function Write-Entries([string]$path, [object[]]$entries) {
    if ($DryRun) { return }
    $lines = @()
    # Preserve any header content above the first entry
    if (Test-Path $path) {
        $orig = Get-Content $path -Encoding UTF8
        $firstEntryIdx = -1
        for ($i = 0; $i -lt $orig.Count; $i++) {
            if ($orig[$i] -match "^- \[\d{4}-\d{2}-\d{2}\]") { $firstEntryIdx = $i; break }
        }
        if ($firstEntryIdx -gt 0) {
            $lines += $orig[0..($firstEntryIdx - 1)]
        } elseif ($firstEntryIdx -eq -1 -and $orig.Count -gt 0) {
            # No entries -- preserve file as-is up to a clear header marker
            $lines += $orig
        }
    }
    foreach ($e in $entries) {
        if ($lines.Count -gt 0 -and $lines[-1] -ne "") { $lines += "" }
        $countSuffix = if ($e.count -gt 1) { " [seen $($e.count)x]" } else { "" }
        $lines += "- [$($e.date)] [class:$($e.class)]$countSuffix"
        $lines += "  Pattern: $($e.pattern)"
        if ($e.evidence) { $lines += "  Evidence: $($e.evidence)" }
        if ($e.target)   { $lines += "  Suggested target: $($e.target)" }
    }
    if ($lines.Count -gt 0 -and $lines[-1] -ne "") { $lines += "" }
    Set-Content -Path $path -Value ($lines -join "`n") -Encoding UTF8 -NoNewline
}

function Append-PromotedNote([string]$memoryPath, [string]$pattern, [string]$target) {
    if ($DryRun) { return }
    if (-not (Test-Path $memoryPath)) { return }
    $date = Get-Date -Format "yyyy-MM-dd"
    Add-Content -Path $memoryPath -Value "`n[$date] Promoted: $pattern -> $target (auto-consolidate)" -Encoding UTF8
}

function Append-AdditivePromotion([string]$targetFile, [string]$pattern, [string]$evidence) {
    if ($DryRun) { return }
    # Only promote into files that exist; never create new top-level files
    # in a target the user didn't anticipate.
    if (-not [System.IO.Path]::IsPathRooted($targetFile)) {
        $targetFile = Join-Path $RepoRoot $targetFile
    }
    if (-not (Test-Path $targetFile)) { return $false }
    $marker = "<!-- auto-consolidated promotion -->"
    $date = Get-Date -Format "yyyy-MM-dd"
    $block = @"

$marker
**[$date] Additive pattern (auto-promoted from reflections):**
- $pattern
- Evidence: $evidence
"@
    Add-Content -Path $targetFile -Value $block -Encoding UTF8
    return $true
}

# --- Run -------------------------------------------------------------------
$promoted = Read-MemoryPromotedPatterns
$today = Get-Date

foreach ($pathSpec in @(
    @{ Path = $repoPath;   Scope = "repo" },
    @{ Path = $globalPath; Scope = "global" }
)) {
    $entries = Parse-Entries $pathSpec.Path
    if ($entries.Count -eq 0) { continue }
    $summary.started_with += $entries.Count

    # 1. DEDUP -- group by (class, pattern), merge evidence, sum counts
    $grouped = $entries | Group-Object -Property { "$($_.class)|$($_.pattern)" }
    $deduped = @()
    foreach ($g in $grouped) {
        if ($g.Count -gt 1) {
            $merged = $g.Group[0]
            $merged.count = ($g.Group | Measure-Object -Property count -Sum).Sum
            $allEvidence = ($g.Group | ForEach-Object { $_.evidence } | Where-Object { $_ }) -join " || "
            if ($allEvidence) { $merged.evidence = $allEvidence }
            # Use most recent date
            $merged.date = ($g.Group | Sort-Object date -Descending | Select-Object -First 1).date
            $deduped += $merged
            $summary.deduped += $g.Count - 1
            [void]$summary.actions.Add("dedup ($($pathSpec.Scope)): merged $($g.Count) entries of '$($merged.pattern)'")
        } else {
            $deduped += $g.Group[0]
        }
    }

    # 2. ARCHIVE -- drop anything in memory.md as Promoted:
    $kept = @()
    foreach ($e in $deduped) {
        $isResolved = $false
        foreach ($p in $promoted) {
            if ($e.pattern -like "*$p*" -or $p -like "*$($e.pattern)*") { $isResolved = $true; break }
        }
        if ($isResolved) {
            $summary.archived += 1
            [void]$summary.actions.Add("archive ($($pathSpec.Scope)): '$($e.pattern)' (already in memory.md)")
        } else {
            $kept += $e
        }
    }
    $deduped = $kept

    # 3. STALE -- drop single-occurrence entries older than $StaleDays
    $kept = @()
    foreach ($e in $deduped) {
        try {
            $entryDate = [datetime]::ParseExact($e.date, "yyyy-MM-dd", $null)
            $ageDays = ($today - $entryDate).Days
        } catch { $ageDays = 0 }
        if ($e.count -eq 1 -and $ageDays -gt $StaleDays) {
            $summary.stale_dropped += 1
            [void]$summary.actions.Add("stale ($($pathSpec.Scope)): '$($e.pattern)' aged $ageDays days, single occurrence")
        } else {
            $kept += $e
        }
    }
    $deduped = $kept

    # 4. PROMOTE -- additive patterns with count >= threshold
    $kept = @()
    foreach ($e in $deduped) {
        $promoteEligible = ($e.class -eq "additive" -or $e.class -eq "noise") -and ($e.count -ge $PromoteThreshold) -and $e.target
        if ($promoteEligible) {
            $ok = Append-AdditivePromotion -targetFile $e.target -pattern $e.pattern -evidence $e.evidence
            if ($ok) {
                Append-PromotedNote -memoryPath $memoryPath -pattern $e.pattern -target $e.target
                $summary.auto_promoted += 1
                [void]$summary.actions.Add("promote ($($pathSpec.Scope)): '$($e.pattern)' -> $($e.target)")
                continue
            }
        }
        $kept += $e
    }
    $deduped = $kept

    # Write back
    Write-Entries $pathSpec.Path $deduped
    $summary.remaining += $deduped.Count
}

if ($Json) {
    Write-Output (($summary | ConvertTo-Json -Depth 5 -Compress))
} else {
    Write-Host "auto-consolidate: started=$($summary.started_with) deduped=$($summary.deduped) archived=$($summary.archived) stale=$($summary.stale_dropped) promoted=$($summary.auto_promoted) remaining=$($summary.remaining)"
    if ($summary.actions.Count -gt 0) {
        Write-Host ""
        foreach ($a in $summary.actions) { Write-Host "  - $a" }
    }
}
exit 0
