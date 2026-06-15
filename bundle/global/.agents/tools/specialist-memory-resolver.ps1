#!/usr/bin/env pwsh

param(
    [Parameter(Mandatory = $true)]
    [string]$SessionId,
    [Parameter(Mandatory = $true)]
    [string]$Role,
    [string]$RepoRoot = "",
    [switch]$IncludeLegacyRoleMemory,
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

$patternsPath = Join-Path $RepoRoot ".kit\context\patterns.md"
$legacyMemoryDir = Join-Path $RepoRoot ".kit\context\agent-memory"
$globalMemoryDir = Join-Path $script:AgentsRoot "context\specialist-memory"
$reusablesPath = Join-Path $RepoRoot ".kit\context\reusables.md"
$legacySharedPath = Join-Path $legacyMemoryDir "shared.md"
$legacyRolePath = Join-Path $legacyMemoryDir "$Role.md"
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

if (Test-Path $patternsPath) {
    $patternsText = Get-Content $patternsPath -Raw
    if ($patternsText.Trim()) {
        [void]$usedFiles.Add($patternsPath)
        [void]$sections.Add("## repo context patterns`n" + (Normalize-Excerpt -Text $patternsText -MaxChars $MaxCharsPerFile -MaxLines $MaxLinesPerFile))
    }
}

if ($IncludeLegacyRoleMemory) {
    if (Test-Path $legacySharedPath) {
        $legacySharedText = Get-Content $legacySharedPath -Raw
        if ($legacySharedText.Trim()) {
            [void]$usedFiles.Add($legacySharedPath)
            [void]$sections.Add("## legacy shared role memory`n" + (Normalize-Excerpt -Text $legacySharedText -MaxChars $MaxCharsPerFile -MaxLines $MaxLinesPerFile))
        }
    }

    if (Test-Path $legacyRolePath) {
        $legacyRoleText = Get-Content $legacyRolePath -Raw
        if ($legacyRoleText.Trim()) {
            [void]$usedFiles.Add($legacyRolePath)
            [void]$sections.Add("## legacy $Role role memory`n" + (Normalize-Excerpt -Text $legacyRoleText -MaxChars $MaxCharsPerFile -MaxLines $MaxLinesPerFile))
        }
    }
}

$found = $usedFiles.Count -gt 0
$resolvedPath = Join-Path $resolvedDir "$Role.md"
$promptBlock = ""

if ($found) {
    $joinedSections = ($sections -join "`n`n").Trim()
    $promptBlock = @"
Repo context patterns for role '$Role':
Use this repo-specific guidance only as bounded context. Prefer current code when it conflicts. Do not widen scope beyond the assigned task.

$joinedSections
"@

    Set-Content -Path $resolvedPath -Value $promptBlock -Encoding utf8
    Sync-EvalArtifactMirror -SessionId $SessionId -SourcePath $resolvedPath -TargetName "resolved-specialist-memory-$Role.md"

    foreach ($file in $usedFiles) {
        & $script:AgentsShell -NoProfile -File (Join-Path $toolsDir "run-packet.ps1") -SessionId $SessionId -AddMemoryPath $file | Out-Null
        & $script:AgentsShell -NoProfile -File (Join-Path $toolsDir "workflow-evidence.ps1") -SessionId $SessionId -AddRepoContext $file | Out-Null
    }
    & $script:AgentsShell -NoProfile -File (Join-Path $toolsDir "run-packet.ps1") -SessionId $SessionId -AddNote "repo-context-patterns:$Role|$($usedFiles.Count) file(s)" | Out-Null
    & $script:AgentsShell -NoProfile -File (Join-Path $toolsDir "workflow-evidence.ps1") -SessionId $SessionId -AddNote "repo-context-patterns:$Role|$($usedFiles.Count) file(s)" | Out-Null
} elseif (Test-Path $resolvedPath) {
    Remove-Item -Force $resolvedPath
}

$result = [ordered]@{
    found        = $found
    role         = $Role
    repo_root    = $RepoRoot
    include_legacy_role_memory = [bool]$IncludeLegacyRoleMemory
    files        = @($usedFiles)
    resolved_path = if ($found) { $resolvedPath } else { "" }
    prompt_block = $promptBlock
}

Write-Output ($result | ConvertTo-Json -Compress -Depth 6)
