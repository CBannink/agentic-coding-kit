#!/usr/bin/env pwsh

param(
    [string]$SessionId = "",
    [int]$RecentAgentCount = 5,
    [string]$Trigger = "PreCompact"
)

. (Join-Path $PSScriptRoot "_paths.ps1")

$SessionId = Resolve-HookSessionId -Provided $SessionId

$sessionDir = Get-SessionDir $SessionId
$packetPath = Join-Path $sessionDir "run-packet.json"
$evidencePath = Join-Path $sessionDir "workflow-evidence.json"
$planPath = Join-Path $sessionDir "plan.md"
$subagentEventsPath = Join-Path $sessionDir "subagent-events.jsonl"
$hookEventsPath = Join-Path $sessionDir "hook-events.jsonl"
$briefPath = Join-Path $sessionDir "compact-brief.md"
New-Item -ItemType Directory -Path $sessionDir -Force | Out-Null

$packet = if (Test-Path $packetPath) { Get-Content $packetPath -Raw | ConvertFrom-Json } else { $null }
$evidence = if (Test-Path $evidencePath) { Get-Content $evidencePath -Raw | ConvertFrom-Json } else { $null }
$planHeader = if (Test-Path $planPath) { (Get-Content $planPath -TotalCount 12) -join "`n" } else { "" }

$recentSubagents = @()
if (Test-Path $subagentEventsPath) {
    $recentSubagents = Get-Content $subagentEventsPath | Select-Object -Last $RecentAgentCount | ForEach-Object {
        try { $_ | ConvertFrom-Json } catch { $null }
    } | Where-Object { $_ }
}

$recentHooks = @()
if (Test-Path $hookEventsPath) {
    $recentHooks = Get-Content $hookEventsPath | Select-Object -Last 5 | ForEach-Object {
        try { $_ | ConvertFrom-Json } catch { $null }
    } | Where-Object { $_ }
}

$lines = @(
    "# Compact Brief",
    "",
    "- Session: $SessionId",
    "- Trigger: $Trigger",
    "- Updated: $(Get-Date -Format 'o')",
    "- Modes: $(if ($packet -and $packet.mode_sequence) { @($packet.mode_sequence) -join ', ' } else { 'none' })",
    "- Task: $(if ($packet -and $packet.task) { $packet.task } else { 'not recorded' })",
    "- Approval: $(if ($packet -and $packet.approval_status) { $packet.approval_status } else { 'not recorded' })",
    "",
    "## Plan Summary",
    $(if ($packet -and $packet.plan_summary) { $packet.plan_summary } elseif ($planHeader) { $planHeader } else { "not recorded" }),
    "",
    "## Likely Files",
    $(if ($packet -and $packet.likely_files.Count -gt 0) { (@($packet.likely_files) | ForEach-Object { "- $_" }) -join "`n" } else { "- none recorded" }),
    "",
    "## Integration Points",
    $(if ($packet -and $packet.integration_points.Count -gt 0) { (@($packet.integration_points) | ForEach-Object { "- $_" }) -join "`n" } else { "- none recorded" }),
    "",
    "## Verification",
    $(if ($packet -and $packet.verification_items.Count -gt 0) { (@($packet.verification_items) | ForEach-Object { "- $_" }) -join "`n" } elseif ($evidence -and $evidence.verification_commands.Count -gt 0) { (@($evidence.verification_commands) | ForEach-Object { "- $_" }) -join "`n" } else { "- none recorded" }),
    "",
    "## Specialist Memory Used",
    $(if ($packet -and $packet.repo_specialist_memory_used.Count -gt 0) { (@($packet.repo_specialist_memory_used) | ForEach-Object { "- $_" }) -join "`n" } else { "- none recorded" }),
    "",
    "## Recent Subagent Results",
    $(if ($recentSubagents.Count -gt 0) {
        ($recentSubagents | ForEach-Object {
            $summary = if ($_.summary) { $_.summary } else { "no summary" }
            "- $($_.agent) [$($_.status)] $summary"
        }) -join "`n"
    } else { "- none recorded" }),
    "",
    "## Mode Decisions",
    $(if ($evidence -and $evidence.mode_decisions.Count -gt 0) { (@($evidence.mode_decisions) | ForEach-Object { "- $_" }) -join "`n" } else { "- none recorded" }),
    "",
    "## Recent Hook Events",
    $(if ($recentHooks.Count -gt 0) {
        ($recentHooks | ForEach-Object { "- $($_.event) @ $($_.occurred_at)" }) -join "`n"
    } else { "- none recorded" })
)

Set-Content -Path $briefPath -Value ($lines -join "`n") -Encoding utf8
Sync-EvalArtifactMirror -SessionId $SessionId -SourcePath $briefPath -TargetName "compact-brief.md"

$hookRecord = [ordered]@{
    event       = $Trigger
    session_id  = $SessionId
    occurred_at = (Get-Date -Format "o")
    output      = $briefPath
}

Add-Content -Path $hookEventsPath -Value ($hookRecord | ConvertTo-Json -Compress) -Encoding utf8
Sync-EvalArtifactMirror -SessionId $SessionId -SourcePath $hookEventsPath -TargetName "hook-events.jsonl"

Write-Output $briefPath
