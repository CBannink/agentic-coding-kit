#!/usr/bin/env pwsh

param(
    [string]$SessionId = "",
    [string]$AgentName = "",
    [string]$Status = "completed",
    [string]$Summary = "",
    [string]$Files = "",
    [string]$Trigger = "SubagentStop"
)

. (Join-Path $PSScriptRoot "_paths.ps1")

$SessionId = Resolve-HookSessionId -Provided $SessionId
if (-not $AgentName) {
    $AgentName = Resolve-HookField -Provided "" -JsonField "agent_name"
    if (-not $AgentName) { $AgentName = "unknown-agent" }
}

$toolsDir = $PSScriptRoot
$sessionDir = Get-SessionDir $SessionId
$eventsPath = Join-Path $sessionDir "subagent-events.jsonl"
New-Item -ItemType Directory -Path $sessionDir -Force | Out-Null

$record = [ordered]@{
    event       = $Trigger
    session_id  = $SessionId
    occurred_at = (Get-Date -Format "o")
    agent       = $AgentName
    status      = $Status
    summary     = $Summary
    files       = if ($Files) { @($Files -split '\s*,\s*' | Where-Object { $_ }) } else { @() }
}

Add-Content -Path $eventsPath -Value ($record | ConvertTo-Json -Compress) -Encoding utf8
Sync-EvalArtifactMirror -SessionId $SessionId -SourcePath $eventsPath -TargetName "subagent-events.jsonl"

$agentEvidence = $AgentName
if ($Summary) { $agentEvidence = "$AgentName|$Summary" }
& $script:AgentsShell -NoProfile -File (Join-Path $toolsDir "workflow-evidence.ps1") -SessionId $SessionId -AddAgent $agentEvidence | Out-Null

$note = "subagent:$AgentName|$Status"
if ($Summary) { $note += "|$Summary" }
& $script:AgentsShell -NoProfile -File (Join-Path $toolsDir "run-packet.ps1") -SessionId $SessionId -AddNote $note | Out-Null

Write-Output ($record | ConvertTo-Json -Compress)
