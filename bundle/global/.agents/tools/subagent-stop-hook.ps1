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

# Filesystem-truth check per subagent. Compare current sha256 of the writeback
# files against the LAST recorded snapshot for this session. If nothing changed
# since the previous AfterAgent event, append a warning record. Makes mid-run
# context debt visible in real time instead of only at session end.
$sigPath = Join-Path $sessionDir 'subagent-snapshots.json'
$baselinePath = Join-Path $sessionDir 'baseline.json'
if ((Test-Path $baselinePath) -and ($env:AGENTS_ENFORCEMENT -ne 'off')) {
    try {
        $baseline = Get-Content -Raw $baselinePath | ConvertFrom-Json
        $repoRoot = [string]$baseline.repo_root
        $targets = @{}
        if ($repoRoot) {
            $targets['memory.md']      = Join-Path $repoRoot '.kit\context\memory.md'
            $targets['shared.md']      = Join-Path $repoRoot '.kit\context\agent-memory\shared.md'
            $targets['features.md']    = Join-Path $repoRoot '.wiki\features.md'
            $targets['reflections.md'] = Join-Path $repoRoot '.kit\context\reflections.md'
        }
        $targets['handoffs.md'] = Join-Path $sessionDir 'handoffs.md'

        $now = @{}
        foreach ($k in $targets.Keys) {
            $p = $targets[$k]
            if (Test-Path $p) {
                $now[$k] = (Get-FileHash -LiteralPath $p -Algorithm SHA256).Hash
            } else {
                $now[$k] = ""
            }
        }

        $prev = $null
        if (Test-Path $sigPath) {
            try { $prev = Get-Content -Raw $sigPath | ConvertFrom-Json } catch {}
        }
        $prevHashes = if ($prev -and $prev.last) { $prev.last } else { $baseline.files }

        $changed = @()
        foreach ($k in $now.Keys) {
            $pHash = ""
            if ($prevHashes -and $prevHashes.$k) {
                $pHash = if ($prevHashes.$k.sha256) { [string]$prevHashes.$k.sha256 } else { [string]$prevHashes.$k }
            }
            if ($now[$k] -and $now[$k] -ne $pHash) { $changed += $k }
        }

        if ($changed.Count -eq 0) {
            $warning = [ordered]@{
                event       = 'subagent_no_writebacks'
                session_id  = $SessionId
                occurred_at = (Get-Date -Format 'o')
                agent       = $AgentName
                detail      = "Subagent '$AgentName' completed without changing memory.md, shared.md, features.md, reflections.md, or handoffs.md. If this agent produced durable facts, write them BEFORE the next subagent runs to avoid context debt."
            }
            Add-Content -Path $eventsPath -Value ($warning | ConvertTo-Json -Compress) -Encoding utf8
            Write-Warning "SUBAGENT $AgentName produced no durable writebacks (context-debt rule)."
        }

        @{ updated_at = (Get-Date -Format 'o'); last = $now } | ConvertTo-Json -Depth 4 |
            Set-Content -Path $sigPath -Encoding utf8
    } catch {
        Write-Warning "Per-subagent writeback check failed: $_"
    }
}

$agentEvidence = $AgentName
if ($Summary) { $agentEvidence = "$AgentName|$Summary" }
& $script:AgentsShell -NoProfile -File (Join-Path $toolsDir "workflow-evidence.ps1") -SessionId $SessionId -AddAgent $agentEvidence | Out-Null

$note = "subagent:$AgentName|$Status"
if ($Summary) { $note += "|$Summary" }
& $script:AgentsShell -NoProfile -File (Join-Path $toolsDir "run-packet.ps1") -SessionId $SessionId -AddNote $note | Out-Null

Write-Output ($record | ConvertTo-Json -Compress)
