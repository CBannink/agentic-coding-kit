#!/usr/bin/env pwsh
# _paths.ps1
# Shared path resolution for all agent tools. Dot-source this at the top of any
# script that needs the agents root or session root:
#
#   . (Join-Path $PSScriptRoot "_paths.ps1")
#
# Resolves (with env-var override):
#   $AgentsRoot      -- base agents dir            (default ~/.agents)
#   $SessionRoot     -- session state dir          (default $AgentsRoot/session-state)
#   $InstructionsPath -- global instructions file  (default $AgentsRoot/instructions.md)
#   $EvalMirror      -- eval artifact mirror flag  (env: AGENTS_EVAL_ARTIFACT_MIRROR)
#   $EvalRunRoot     -- eval run root              (env: AGENTS_EVAL_RUN_ROOT)
#
# Env vars are tool-neutral. Legacy COPILOT_EVAL_* vars are honored for one
# release cycle so partial migrations don't break.

if ($env:AGENTS_HOME) {
    $script:AgentsRoot = $env:AGENTS_HOME
} else {
    $script:AgentsRoot = Join-Path $HOME ".agents"
}

if ($env:AGENTS_SESSION_ROOT) {
    $script:SessionRoot = $env:AGENTS_SESSION_ROOT
} else {
    $script:SessionRoot = Join-Path $script:AgentsRoot "session-state"
}

$script:InstructionsPath = Join-Path $script:AgentsRoot "instructions.md"
$script:Tools = Join-Path $script:AgentsRoot "tools"

# Eval mirror -- prefer new env var, fall back to legacy
$script:EvalMirror = if ($env:AGENTS_EVAL_ARTIFACT_MIRROR) {
    $env:AGENTS_EVAL_ARTIFACT_MIRROR
} else {
    $env:COPILOT_EVAL_ARTIFACT_MIRROR
}
$script:EvalRunRoot = if ($env:AGENTS_EVAL_RUN_ROOT) {
    $env:AGENTS_EVAL_RUN_ROOT
} else {
    $env:COPILOT_EVAL_RUN_ROOT
}

function Get-SessionDir([string]$SessionId) {
    Join-Path $script:SessionRoot $SessionId
}

# Resolve which PowerShell host to use for subprocess invocations.
# pwsh 7+ is preferred; fall back to Windows PowerShell 5.1 when pwsh isn't installed.
# Lets the kit run cleanly on machines without pwsh -- every internal
# subprocess call should use $script:AgentsShell instead of hardcoded "pwsh".
$script:AgentsShell = if (Get-Command pwsh -ErrorAction SilentlyContinue) {
    "pwsh"
} else {
    "powershell"
}

# Hook stdin parsing -- Claude Code passes session metadata as a JSON payload on
# stdin to hook commands. Older configs relied on $env:CLAUDE_SESSION_ID being
# set, which isn't reliable across shells/versions. Read stdin once, cache, and
# expose helpers so hook scripts can survive missing/empty -SessionId args.
$script:_HookStdinCache = $null
$script:_HookStdinRead = $false

function Get-HookStdinJson {
    if (-not $script:_HookStdinRead) {
        $script:_HookStdinRead = $true
        try {
            if ([Console]::IsInputRedirected) {
                $raw = [Console]::In.ReadToEnd()
                if ($raw -and $raw.Trim()) {
                    $script:_HookStdinCache = $raw | ConvertFrom-Json -ErrorAction SilentlyContinue
                }
            }
        } catch {
            $script:_HookStdinCache = $null
        }
    }
    return $script:_HookStdinCache
}

function Resolve-HookSessionId {
    param([string]$Provided)
    if ($Provided) { return $Provided }
    if ($env:CLAUDE_SESSION_ID) { return $env:CLAUDE_SESSION_ID }
    $stdin = Get-HookStdinJson
    if ($stdin -and $stdin.session_id) { return [string]$stdin.session_id }
    return "unknown-$(Get-Date -Format 'yyyyMMddHHmmss')"
}

function Resolve-HookField {
    param([string]$Provided, [string]$JsonField, [string]$EnvVar = "")
    if ($Provided) { return $Provided }
    if ($EnvVar -and (Get-Item "env:$EnvVar" -ErrorAction SilentlyContinue)) {
        $v = (Get-Item "env:$EnvVar").Value
        if ($v) { return $v }
    }
    $stdin = Get-HookStdinJson
    if ($stdin -and $JsonField -and $stdin.$JsonField) { return [string]$stdin.$JsonField }
    return ""
}

function Sync-EvalArtifactMirror {
    param(
        [string]$SessionId,
        [string]$SourcePath,
        [string]$TargetName
    )
    if ($script:EvalMirror -ne "1") { return }
    if (-not $script:EvalRunRoot) { return }
    if (-not (Test-Path $SourcePath)) { return }

    $mirrorDir = Join-Path $script:EvalRunRoot "artifacts/sessions/$SessionId"
    New-Item -ItemType Directory -Path $mirrorDir -Force | Out-Null
    Copy-Item -Force $SourcePath (Join-Path $mirrorDir $TargetName)
}
