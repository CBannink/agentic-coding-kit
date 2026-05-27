#!/usr/bin/env pwsh

param(
    [Parameter(Mandatory = $true)]
    [string]$SessionId,
    [Parameter(Mandatory = $true)]
    [string]$Role,
    [string]$RepoRoot = "",
    [int]$MaxCharsPerFile = 2500,
    [int]$MaxLinesPerFile = 80
)

. (Join-Path $PSScriptRoot "_paths.ps1")

function Normalize-Excerpt {
    param(
        [string]$Text,
        [int]$MaxChars,
        [int]$MaxLines
    )

    $lines = @($Text -split "`r?`n")
    if ($lines.Count -gt $MaxLines) {
        $lines = $lines[0..($MaxLines - 1)] + "[truncated after $MaxLines lines]"
    }

    $excerpt = ($lines -join "`n").Trim()
    if ($excerpt.Length -gt $MaxChars) {
        $excerpt = $excerpt.Substring(0, $MaxChars).TrimEnd() + "`n[truncated after $MaxChars characters]"
    }

    return $excerpt
}

if (-not $RepoRoot) {
    $RepoRoot = (Get-Location).Path
}

$toolsDir = $PSScriptRoot
$sessionDir = Get-SessionDir $SessionId
$resolvedDir = Join-Path $sessionDir "resolved-specialist-memory"
New-Item -ItemType Directory -Path $resolvedDir -Force | Out-Null

$memoryDir = Join-Path $RepoRoot ".kit\context\agent-memory"
$globalMemoryDir = Join-Path $script:AgentsRoot "context\specialist-memory"
$reusablesPath = Join-Path $RepoRoot ".kit\context\reusables.md"
$sharedPath = Join-Path $memoryDir "shared.md"
$rolePath = Join-Path $memoryDir "$Role.md"
$globalSharedPath = Join-Path $globalMemoryDir "shared.md"
$globalRolePath = Join-Path $globalMemoryDir "$Role.md"

$sections = [System.Collections.ArrayList]::new()
$usedFiles = [System.Collections.ArrayList]::new()

if (Test-Path $reusablesPath) {
    $reusablesText = Get-Content $reusablesPath -Raw
    if ($reusablesText.Trim()) {
        [void]$usedFiles.Add($reusablesPath)
        # Cap reusables at ~4500 chars (approx 1500 tokens) to ensure it never blows up context.
        [void]$sections.Add("## reusables.md (Available Code/Components)`n" + (Normalize-Excerpt -Text $reusablesText -MaxChars 4500 -MaxLines 150))
    }
}

if (Test-Path $globalSharedPath) {
    $globalSharedText = Get-Content $globalSharedPath -Raw
    if ($globalSharedText.Trim()) {
        [void]$usedFiles.Add($globalSharedPath)
        [void]$sections.Add("## global shared specialist memory`n" + (Normalize-Excerpt -Text $globalSharedText -MaxChars $MaxCharsPerFile -MaxLines $MaxLinesPerFile))
    }
}

if (Test-Path $globalRolePath) {
    $globalRoleText = Get-Content $globalRolePath -Raw
    if ($globalRoleText.Trim()) {
        [void]$usedFiles.Add($globalRolePath)
        [void]$sections.Add("## global $Role specialist memory`n" + (Normalize-Excerpt -Text $globalRoleText -MaxChars $MaxCharsPerFile -MaxLines $MaxLinesPerFile))
    }
}

if (Test-Path $sharedPath) {
    $sharedText = Get-Content $sharedPath -Raw
    if ($sharedText.Trim()) {
        [void]$usedFiles.Add($sharedPath)
        [void]$sections.Add("## shared.md`n" + (Normalize-Excerpt -Text $sharedText -MaxChars $MaxCharsPerFile -MaxLines $MaxLinesPerFile))
    }
}

if (Test-Path $rolePath) {
    $roleText = Get-Content $rolePath -Raw
    if ($roleText.Trim()) {
        [void]$usedFiles.Add($rolePath)
        [void]$sections.Add("## $Role.md`n" + (Normalize-Excerpt -Text $roleText -MaxChars $MaxCharsPerFile -MaxLines $MaxLinesPerFile))
    }
}

$found = $usedFiles.Count -gt 0
$resolvedPath = Join-Path $resolvedDir "$Role.md"
$promptBlock = ""

if ($found) {
    $joinedSections = ($sections -join "`n`n").Trim()
    $promptBlock = @"
Repo-local specialist memory for role '$Role':
Use this repo-specific guidance only as role-targeted context. Do not widen scope beyond the assigned task.

$joinedSections
"@

    Set-Content -Path $resolvedPath -Value $promptBlock -Encoding utf8
    Sync-EvalArtifactMirror -SessionId $SessionId -SourcePath $resolvedPath -TargetName "resolved-specialist-memory-$Role.md"

    foreach ($file in $usedFiles) {
        & $script:AgentsShell -NoProfile -File (Join-Path $toolsDir "run-packet.ps1") -SessionId $SessionId -AddMemoryPath $file | Out-Null
        & $script:AgentsShell -NoProfile -File (Join-Path $toolsDir "workflow-evidence.ps1") -SessionId $SessionId -AddRepoContext $file | Out-Null
    }
    & $script:AgentsShell -NoProfile -File (Join-Path $toolsDir "run-packet.ps1") -SessionId $SessionId -AddNote "role-memory:$Role|$($usedFiles.Count) file(s)" | Out-Null
    & $script:AgentsShell -NoProfile -File (Join-Path $toolsDir "workflow-evidence.ps1") -SessionId $SessionId -AddNote "role-memory:$Role|$($usedFiles.Count) file(s)" | Out-Null
} elseif (Test-Path $resolvedPath) {
    Remove-Item -Force $resolvedPath
}

$result = [ordered]@{
    found        = $found
    role         = $Role
    repo_root    = $RepoRoot
    files        = @($usedFiles)
    resolved_path = if ($found) { $resolvedPath } else { "" }
    prompt_block = $promptBlock
}

Write-Output ($result | ConvertTo-Json -Compress -Depth 6)
