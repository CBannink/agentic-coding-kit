#!/usr/bin/env pwsh

param(
    [string]$SessionId = "",
    [string]$Mode = "",
    [string]$Task = "",
    [string]$RepoRoot = "",
    [string]$Trigger = "SessionStart"
)

. (Join-Path $PSScriptRoot "_paths.ps1")

$SessionId = Resolve-HookSessionId -Provided $SessionId
$RepoRoot  = Resolve-HookField -Provided $RepoRoot -JsonField "cwd" -EnvVar "CLAUDE_PROJECT_DIR"

$toolsDir = $PSScriptRoot
$sessionDir = Get-SessionDir $SessionId
$eventsPath = Join-Path $sessionDir "hook-events.jsonl"
New-Item -ItemType Directory -Path $sessionDir -Force | Out-Null

$packetArgs = @("-NoProfile", "-File", (Join-Path $toolsDir "run-packet.ps1"), "-SessionId", $SessionId, "-AddNote", "hook:$Trigger")
if ($Mode) { $packetArgs += @("-Mode", $Mode) }
if ($Task) { $packetArgs += @("-Task", $Task) }
& $script:AgentsShell @packetArgs | Out-Null

$record = [ordered]@{
    event       = $Trigger
    session_id  = $SessionId
    occurred_at = (Get-Date -Format "o")
    mode        = $Mode
    task        = $Task
    repo_root   = $RepoRoot
}

$baseline = [ordered]@{
    session_id    = $SessionId
    session_start = (Get-Date -Format 'o')
    repo_root     = $RepoRoot
    mode          = $Mode
    files         = @{}
}
$baselinePath = Join-Path $sessionDir 'baseline.json'
$baseline | ConvertTo-Json -Depth 6 | Set-Content -Path $baselinePath -Encoding utf8

Add-Content -Path $eventsPath -Value ($record | ConvertTo-Json -Compress) -Encoding utf8
Sync-EvalArtifactMirror -SessionId $SessionId -SourcePath $eventsPath -TargetName "hook-events.jsonl"
Write-Output ($record | ConvertTo-Json -Compress)
