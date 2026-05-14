#!/usr/bin/env pwsh
# pretool-read-delegation-gate.ps1 -- PreToolUse hook for the Read tool.
#
# Enforces the coordinator's pre-delegation source-read budget for /build-like
# sessions. The main session gets at most two unique source-file reads before
# it must delegate to workflow-explorer or workflow-implementer. This keeps the
# expensive top-level session from doing all excavation inline.
#
# Opt-out:
#   KIT_DISABLED_HOOKS=read-delegation-gate

$ErrorActionPreference = "Continue"
. (Join-Path $PSScriptRoot "../_paths.ps1") -ErrorAction SilentlyContinue

$disabledHooks = if ($env:KIT_DISABLED_HOOKS) { @($env:KIT_DISABLED_HOOKS -split ',') } else { @() }
if ($disabledHooks -contains "read-delegation-gate") { exit 0 }

$rawInput = [Console]::In.ReadToEnd()
if (-not $rawInput) { exit 0 }
try {
    $payload = $rawInput | ConvertFrom-Json
} catch { exit 0 }

$sessionId = [string]$payload.session_id
if (-not $sessionId) { exit 0 }

$toolName = [string]$payload.tool_name
if ($toolName -and $toolName -notmatch '^(Read|read)$') { exit 0 }

$targetFile = $null
if ($payload.tool_input.file_path) { $targetFile = [string]$payload.tool_input.file_path }
elseif ($payload.tool_input.path) { $targetFile = [string]$payload.tool_input.path }
elseif ($payload.tool_input.filePath) { $targetFile = [string]$payload.tool_input.filePath }
if (-not $targetFile) { exit 0 }

$normalizedTarget = $targetFile -replace '\\', '/'
$srcPattern = '\.(ts|tsx|js|jsx|py|go|rs|java|cs|rb|php|swift|kt|scala|cpp|c|h|hpp|vue|svelte|astro)$'
$ignorePattern = '(^|/)(\.kit|\.wiki|\.github|docs?|tests?|__tests__|fixtures|dist|build|node_modules|\.venv|__pycache__)(/|$)|(\.test\.|\.spec\.)'
if ($normalizedTarget -notmatch $srcPattern) { exit 0 }
if ($normalizedTarget -match $ignorePattern) { exit 0 }

$sessionDir = Join-Path $script:SessionRoot $sessionId
$statePath = Join-Path $sessionDir "state.json"
if (-not (Test-Path $statePath)) { exit 0 }

try {
    $state = Get-Content $statePath -Raw -Encoding UTF8 | ConvertFrom-Json
} catch { exit 0 }

$delegatedAgents = @($state.agents_run) | Where-Object {
    $_ -match '(^|-)workflow-explorer$|(^|-)workflow-implementer$|(^|-)delta-explorer$|(^|-)patterns-explorer$|(^|-)implementer$'
}
if ($delegatedAgents.Count -gt 0) { exit 0 }

$readFilesPath = Join-Path $sessionDir "source-read-files.json"
$readFiles = @{}
if (Test-Path $readFilesPath) {
    try {
        $loaded = Get-Content $readFilesPath -Raw -Encoding UTF8 | ConvertFrom-Json
        foreach ($p in $loaded.PSObject.Properties) {
            $readFiles[$p.Name] = $p.Value
        }
    } catch {}
}

$candidateCount = @($readFiles.Keys).Count
if (-not $readFiles.ContainsKey($normalizedTarget)) {
    $candidateCount++
}

if ($candidateCount -gt 2) {
    [Console]::Error.WriteLine(@"
Blocked by kit hook (read-delegation-gate/pre-delegation-budget):

This session has already read two unique source files before delegation. The
next step should be spawning `workflow-explorer` (preferred) or
`workflow-implementer`, not continuing excavation inline in the main session.

To resolve:
  1. Spawn `workflow-explorer` if you still need context.
  2. Spawn `workflow-implementer` if the task is already understood.
  3. Keep the main session as coordinator; let subagents do the source reads.

To bypass entirely:
  Set KIT_DISABLED_HOOKS=read-delegation-gate and retry the read.
"@)
    exit 2
}

if (-not $readFiles.ContainsKey($normalizedTarget) -and (Test-Path $sessionDir)) {
    try {
        $readFiles[$normalizedTarget] = (Get-Date).ToString("o")
        ($readFiles | ConvertTo-Json -Depth 3) | Set-Content -Path $readFilesPath -Encoding UTF8
    } catch {}
}

exit 0
