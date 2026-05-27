#!/usr/bin/env pwsh
# Append a bounded, deduplicated line to global specialist memory.

param(
    [Parameter(Mandatory = $true)]
    [string]$Role,
    [Parameter(Mandatory = $true)]
    [string]$Pattern,
    [string]$Source = "",
    [int]$MaxLines = 1200,
    [switch]$Json
)

. (Join-Path $PSScriptRoot "_paths.ps1")

function Emit($obj) {
    if ($Json) { Write-Output ($obj | ConvertTo-Json -Compress -Depth 6) }
    else { Write-Output $obj.message }
}

$safeRole = ($Role -replace '[^a-zA-Z0-9_.-]', '-').ToLowerInvariant()
if (-not $safeRole) {
    Emit ([ordered]@{ ok = $false; reason = "invalid-role"; message = "Invalid role." })
    exit 1
}

$patternText = $Pattern.Trim()
if (-not $patternText) {
    Emit ([ordered]@{ ok = $false; reason = "empty-pattern"; message = "Pattern is empty." })
    exit 1
}
if ($patternText.Length -gt 600) {
    Emit ([ordered]@{ ok = $false; reason = "pattern-too-long"; message = "Pattern exceeds 600 chars." })
    exit 1
}
if ($patternText -match '(?i)(api[_-]?key|secret|password|token|credential|private key|bearer\s+[a-z0-9._-]+)') {
    Emit ([ordered]@{ ok = $false; reason = "possible-secret"; message = "Pattern looks like it may contain a secret." })
    exit 1
}

$memoryDir = Join-Path $script:AgentsRoot "context/specialist-memory"
$path = Join-Path $memoryDir "$safeRole.md"
New-Item -ItemType Directory -Path $memoryDir -Force | Out-Null

if (-not (Test-Path $path)) {
    [System.IO.File]::WriteAllText($path, "# $safeRole Global Specialist Memory`n`n", [System.Text.UTF8Encoding]::new($false))
}

$existing = Get-Content -Path $path -Raw -Encoding UTF8
$needle = $patternText.Substring(0, [Math]::Min(80, $patternText.Length))
if ($existing -match [regex]::Escape($needle)) {
    Emit ([ordered]@{ ok = $true; action = "skipped"; reason = "duplicate"; path = $path; message = "Skipped duplicate specialist memory." })
    exit 0
}

$lines = @($existing -split "`r?`n")
if ($lines.Count -ge $MaxLines) {
    Emit ([ordered]@{ ok = $false; reason = "line-limit"; path = $path; lines = $lines.Count; max_lines = $MaxLines; message = "Specialist memory line limit reached; run memory review/compression before appending." })
    exit 1
}

$date = Get-Date -Format "yyyy-MM-dd"
$sourceSuffix = if ($Source.Trim()) { " [source:$($Source.Trim())]" } else { "" }
$entry = "- [$date]$sourceSuffix $patternText"
[System.IO.File]::AppendAllText($path, $entry + "`n", [System.Text.UTF8Encoding]::new($false))

Emit ([ordered]@{ ok = $true; action = "appended"; path = $path; role = $safeRole; message = "Appended specialist memory: $path" })
exit 0
