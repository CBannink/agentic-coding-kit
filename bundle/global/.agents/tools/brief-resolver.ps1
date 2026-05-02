#!/usr/bin/env pwsh
# brief-resolver.ps1
# Resolves the newest same-day build brief from analyze/investigate sessions.

param(
    [string]$Date = "",
    [string]$SharedHandoffsPath = ".codex/context/handoffs.md",
    [string]$SharedIndexPath = ""
)

if (-not $Date) {
    $Date = Get-Date -Format "yyyy-MM-dd"
}

$result = [ordered]@{
    found          = $false
    session_id     = ""
    task           = ""
    handoff_path   = ""
    section_header = ""
    source         = ""
    outcome        = ""
    keywords       = ""
}

if (-not (Test-Path $SharedHandoffsPath)) {
    Write-Output ($result | ConvertTo-Json -Compress)
    exit 0
}

$matchingHeaders = @(
    "## Build Brief [$Date]",
    "## Analysis-to-Build Brief [$Date]",
    "## Investigation-to-Build Brief [$Date]"
)

if (-not $SharedIndexPath) {
    $SharedIndexPath = Join-Path (Split-Path $SharedHandoffsPath) "handoffs.index.jsonl"
}

if (Test-Path $SharedIndexPath) {
    $records = Get-Content $SharedIndexPath | Where-Object { $_ } | ForEach-Object {
        try { $_ | ConvertFrom-Json } catch { $null }
    } | Where-Object {
        $_ -and $_.session_id -like "$Date--*" -and ($_.task -like "analyze-*" -or $_.task -like "investigate-*")
    } | Sort-Object session_id

    for ($i = $records.Count - 1; $i -ge 0; $i--) {
        $record = $records[$i]
        if (-not (Test-Path $record.handoff_path)) { continue }
        $handoffRaw = Get-Content $record.handoff_path -Raw
        $matchedHeader = $null
        foreach ($header in $matchingHeaders) {
            if ($handoffRaw -match [regex]::Escape($header)) {
                $matchedHeader = $header
                break
            }
        }
        if (-not $matchedHeader) { continue }

        $result.found = $true
        $result.session_id = $record.session_id
        $result.task = $record.task
        $result.handoff_path = $record.handoff_path
        $result.section_header = $matchedHeader
        $result.source = if ($record.task -like "analyze-*") { "analyze" } else { "investigate" }
        $result.outcome = $record.outcome
        $result.keywords = ($record.keywords -join ',')
        Write-Output ($result | ConvertTo-Json -Compress)
        exit 0
    }
}

$pattern = "SESSION: (" + [regex]::Escape($Date) + "--\d{6}).*Task: ((analyze|investigate)-[^|\]]+).*Handoff: ([^|\]]+)"

$tagLines = Get-Content $SharedHandoffsPath
for ($i = $tagLines.Count - 1; $i -ge 0; $i--) {
    $line = $tagLines[$i]
    if (-not ($line -match $pattern)) {
        continue
    }

    $sessionId = $Matches[1].Trim()
    $task = $Matches[2].Trim()
    $handoffPath = $Matches[4].Trim()
    $source = if ($task -like "analyze-*") { "analyze" } else { "investigate" }
    $keywords = ""
    $outcome = ""
    if ($line -match "Keywords: ([^|\]]+)") { $keywords = $Matches[1].Trim() }
    if ($line -match "Outcome: ([^|\]]+)")  { $outcome = $Matches[1].Trim() }

    if (-not (Test-Path $handoffPath)) {
        continue
    }

    $handoffRaw = Get-Content $handoffPath -Raw
    $matchedHeader = $null
    foreach ($header in $matchingHeaders) {
        if ($handoffRaw -match [regex]::Escape($header)) {
            $matchedHeader = $header
            break
        }
    }

    if (-not $matchedHeader) {
        continue
    }

    $result.found = $true
    $result.session_id = $sessionId
    $result.task = $task
    $result.handoff_path = $handoffPath
    $result.section_header = $matchedHeader
    $result.source = $source
    $result.outcome = $outcome
    $result.keywords = $keywords
    Write-Output ($result | ConvertTo-Json -Compress)
    exit 0
}

Write-Output ($result | ConvertTo-Json -Compress)
