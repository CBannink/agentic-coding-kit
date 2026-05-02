#!/usr/bin/env pwsh
# handoff-register.ps1
# Appends a row to the Session Handoff Index in memory.md.
# Called at the end of every build/review/analyze session.
# Enforces max-20-row limit by dropping the oldest entry.
#
# Usage:
#   handoff-register.ps1 -SessionId "abc123" -Task "build-auth" -Summary "JWT middleware, routes, token refresh, tests" [-MemoryPath ".kit/context/memory.md"]
#
# The Summary should answer: "if you're working on X, you'll find Y here"
# Keep it ≤15 words. It is the ONLY thing an agent reads before deciding to load the full handoff.

param(
    [Parameter(Mandatory)][string]$SessionId,
    [Parameter(Mandatory)][string]$Task,
    [Parameter(Mandatory)][string]$Summary,
    [string]$MemoryPath = ".kit/context/memory.md"
)

. (Join-Path $PSScriptRoot "_paths.ps1")

$MAX_ROWS = 20
$handoffPath = Join-Path (Get-SessionDir $SessionId) "handoffs.md"
$date = Get-Date -Format "yyyy-MM-dd"

# Resolve memory.md path
if (-not [System.IO.Path]::IsPathRooted($MemoryPath)) {
    $MemoryPath = Join-Path (Get-Location) $MemoryPath
}

if (-not (Test-Path $MemoryPath)) {
    Write-Error "❌ memory.md not found at $MemoryPath"
    exit 1
}

$content = Get-Content $MemoryPath -Raw

# Check index section exists
$sectionHeader = "## Session Handoff Index"
if ($content -notmatch [regex]::Escape($sectionHeader)) {
    Write-Error "❌ No '## Session Handoff Index' section found in $MemoryPath -- add it first."
    exit 1
}

# Truncate summary to 15 words max
$words = $Summary -split '\s+'
if ($words.Count -gt 15) {
    $Summary = ($words[0..14] -join ' ') + '…'
}

# Build the new row
$newRow = "| $date | $Task | $Summary | $handoffPath |"

# Find the table in the section
$lines = $content -split "`n"
$inSection = $false
$tableStart = -1
$tableEnd = -1
$dataRows = @()

for ($i = 0; $i -lt $lines.Count; $i++) {
    if ($lines[$i] -match "^## Session Handoff Index") {
        $inSection = $true
        continue
    }
    if ($inSection -and $lines[$i] -match "^\|") {
        if ($tableStart -eq -1) { $tableStart = $i }
        $tableEnd = $i
        # Collect data rows (skip header row and divider)
        if ($lines[$i] -notmatch "^\| Date" -and $lines[$i] -notmatch "^\|[-| ]+\|") {
            $dataRows += $lines[$i]
        }
    }
    # Stop at next section
    if ($inSection -and $tableStart -ne -1 -and $lines[$i] -match "^## " -and $lines[$i] -notmatch "^## Session Handoff Index") {
        break
    }
}

if ($tableStart -eq -1) {
    Write-Error "❌ Session Handoff Index table not found in $MemoryPath"
    exit 1
}

# Add new row at top, enforce max
$escapedPath = [regex]::Escape($handoffPath)
$dataRows = $dataRows | Where-Object { $_ -notmatch $escapedPath }
$dataRows = @($newRow) + $dataRows
if ($dataRows.Count -gt $MAX_ROWS) {
    $dataRows = $dataRows[0..($MAX_ROWS - 1)]
    Write-Host "⚠️  Dropped oldest handoff entry (max $MAX_ROWS rows)"
}

# Rebuild the table
$newTable = @(
    "| Date | Task | What you'll find there (≤15 words) | Handoff path |",
    "|------|------|-------------------------------------|--------------|"
) + $dataRows

# Replace old table lines with new ones
$before = $lines[0..($tableStart - 1)]
$after  = $lines[($tableEnd + 1)..($lines.Count - 1)]
$rebuilt = ($before + $newTable + $after) -join "`n"

Set-Content -Path $MemoryPath -Value $rebuilt -Encoding utf8 -NoNewline
Write-Host "✅ Handoff registered in $MemoryPath"
Write-Host "   Task:    $Task"
Write-Host "   Summary: $Summary"
Write-Host "   Path:    $handoffPath"
