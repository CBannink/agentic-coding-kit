#!/usr/bin/env pwsh

param(
    [string]$SessionId = "",
    [string]$Mode = "",
    [string]$Outcome = "",
    [string]$Summary = "",
    [string]$Files = "",
    [string]$Trigger = "SessionEnd"
)

. (Join-Path $PSScriptRoot "_paths.ps1")

$SessionId = Resolve-HookSessionId -Provided $SessionId

$toolsDir = $PSScriptRoot
$sessionDir = Get-SessionDir $SessionId
$eventsPath = Join-Path $sessionDir "hook-events.jsonl"
New-Item -ItemType Directory -Path $sessionDir -Force | Out-Null

$note = "hook:$Trigger"
if ($Outcome) { $note += "|$Outcome" }
if ($Summary) { $note += "|$Summary" }
$packetArgs = @("-NoProfile", "-File", (Join-Path $toolsDir "run-packet.ps1"), "-SessionId", $SessionId, "-AddNote", $note)
if ($Mode) { $packetArgs += @("-Mode", $Mode) }
& $script:AgentsShell @packetArgs | Out-Null

$record = [ordered]@{
    event       = $Trigger
    session_id  = $SessionId
    occurred_at = (Get-Date -Format "o")
    mode        = $Mode
    outcome     = $Outcome
    summary     = $Summary
    files       = if ($Files) { @($Files -split '\s*,\s*' | Where-Object { $_ }) } else { @() }
}

Add-Content -Path $eventsPath -Value ($record | ConvertTo-Json -Compress) -Encoding utf8
Sync-EvalArtifactMirror -SessionId $SessionId -SourcePath $eventsPath -TargetName "hook-events.jsonl"
Write-Output ($record | ConvertTo-Json -Compress)
