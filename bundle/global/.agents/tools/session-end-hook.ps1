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

# Filesystem-truth audit. Diff baseline.json (session start) against current
# state. If NONE of the durable-memory files changed and no waiver was filed,
# record a compliance violation against this session in the global compliance
# history. Iron Law applied to memory writebacks.
$baselinePath = Join-Path $sessionDir 'baseline.json'
$violation = $null
if ((Test-Path $baselinePath) -and ($env:AGENTS_ENFORCEMENT -ne 'off')) {
    try {
        $baseline = Get-Content -Raw $baselinePath | ConvertFrom-Json
        $changed = @()
        foreach ($name in @('memory.md','shared.md','features.md','reflections.md','handoffs.md')) {
            $b = $baseline.files.$name
            if (-not $b) { continue }
            $path = $null
            if ($name -eq 'handoffs.md') {
                $path = Join-Path $sessionDir 'handoffs.md'
            } elseif ($baseline.repo_root) {
                $path = switch ($name) {
                    'memory.md'      { Join-Path $baseline.repo_root '.kit\context\memory.md' }
                    'shared.md'      { Join-Path $baseline.repo_root '.kit\context\agent-memory\shared.md' }
                    'features.md'    { Join-Path $baseline.repo_root '.wiki\features.md' }
                    'reflections.md' { Join-Path $baseline.repo_root '.kit\context\reflections.md' }
                }
            }
            if (-not $path) { continue }
            if (Test-Path $path) {
                $now = (Get-FileHash -LiteralPath $path -Algorithm SHA256).Hash
                if ($now -ne $b.sha256) { $changed += $name }
            } elseif ($b.exists) {
                $changed += "$name(deleted)"
            }
        }

        $waiverPath = Join-Path $sessionDir 'gate-waivers.jsonl'
        $hasWaiver = Test-Path $waiverPath

        if ($changed.Count -eq 0 -and -not $hasWaiver) {
            $violation = [ordered]@{
                event        = 'compliance_violation'
                kind         = 'no_durable_writebacks'
                session_id   = $SessionId
                occurred_at  = (Get-Date -Format 'o')
                repo_root    = $baseline.repo_root
                mode         = $Mode
                outcome      = $Outcome
                detail       = 'Session ended without modifying memory.md, shared.md, features.md, reflections.md, or handoffs.md. No waiver filed.'
            }
            $compliancePath = Join-Path (Split-Path $sessionDir -Parent | Split-Path -Parent) 'compliance-history.jsonl'
            Add-Content -Path $compliancePath -Value ($violation | ConvertTo-Json -Compress) -Encoding utf8
            Add-Content -Path $eventsPath -Value ($violation | ConvertTo-Json -Compress) -Encoding utf8
            Write-Warning "COMPLIANCE: session ended with no durable memory writebacks (Iron Law). Logged to $compliancePath"
        }
    } catch {
        Write-Warning "Filesystem-truth audit failed: $_"
    }
}

Write-Output ($record | ConvertTo-Json -Compress)
if ($violation -and $env:AGENTS_ENFORCEMENT -eq 'strict') { exit 1 }
