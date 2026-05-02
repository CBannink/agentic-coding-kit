#!/usr/bin/env pwsh

param(
    [Parameter(Mandatory = $true)]
    [string]$SessionId,
    [string]$Mode = "",
    [string]$Task = "",
    [string]$RepoRoot = "",
    [string]$Trigger = "SessionStart"
)

. (Join-Path $PSScriptRoot "_paths.ps1")

$toolsDir = $PSScriptRoot
$sessionDir = Get-SessionDir $SessionId
$eventsPath = Join-Path $sessionDir "hook-events.jsonl"
New-Item -ItemType Directory -Path $sessionDir -Force | Out-Null

& $script:AgentsShell -NoProfile -File (Join-Path $toolsDir "run-packet.ps1") -SessionId $SessionId -Mode $Mode -Task $Task -AddNote "hook:$Trigger" | Out-Null

$record = [ordered]@{
    event       = $Trigger
    session_id  = $SessionId
    occurred_at = (Get-Date -Format "o")
    mode        = $Mode
    task        = $Task
    repo_root   = $RepoRoot
}

Add-Content -Path $eventsPath -Value ($record | ConvertTo-Json -Compress) -Encoding utf8
Sync-EvalArtifactMirror -SessionId $SessionId -SourcePath $eventsPath -TargetName "hook-events.jsonl"
Write-Output ($record | ConvertTo-Json -Compress)
