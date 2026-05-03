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

# Filesystem-truth baseline. Captures session-start timestamp + size+sha256 of
# the critical writeback files so session-end-hook can detect whether anything
# was actually written, and so state-gate.ps1 has a session_start to compare
# mtimes against.
function Get-FileSnapshot([string]$Path) {
    if (-not (Test-Path $Path)) { return @{ exists = $false; size = 0; sha256 = ""; mtime = "" } }
    $i = Get-Item $Path
    $sha = (Get-FileHash -LiteralPath $Path -Algorithm SHA256).Hash
    return @{ exists = $true; size = $i.Length; sha256 = $sha; mtime = $i.LastWriteTime.ToString('o') }
}
$baselineFiles = @{}
if ($RepoRoot -and (Test-Path $RepoRoot)) {
    $baselineFiles['memory.md']      = Get-FileSnapshot (Join-Path $RepoRoot '.kit\context\memory.md')
    $baselineFiles['shared.md']      = Get-FileSnapshot (Join-Path $RepoRoot '.kit\context\agent-memory\shared.md')
    $baselineFiles['features.md']    = Get-FileSnapshot (Join-Path $RepoRoot '.wiki\features.md')
    $baselineFiles['reflections.md'] = Get-FileSnapshot (Join-Path $RepoRoot '.kit\context\reflections.md')
}
$baselineFiles['handoffs.md'] = Get-FileSnapshot (Join-Path $sessionDir 'handoffs.md')

$baseline = [ordered]@{
    session_id    = $SessionId
    session_start = (Get-Date -Format 'o')
    repo_root     = $RepoRoot
    mode          = $Mode
    files         = $baselineFiles
}
$baselinePath = Join-Path $sessionDir 'baseline.json'
$baseline | ConvertTo-Json -Depth 6 | Set-Content -Path $baselinePath -Encoding utf8

Add-Content -Path $eventsPath -Value ($record | ConvertTo-Json -Compress) -Encoding utf8
Sync-EvalArtifactMirror -SessionId $SessionId -SourcePath $eventsPath -TargetName "hook-events.jsonl"
Write-Output ($record | ConvertTo-Json -Compress)
