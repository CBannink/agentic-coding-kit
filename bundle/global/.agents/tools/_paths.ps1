#!/usr/bin/env pwsh
# _paths.ps1
# Shared path resolution for all agent tools. Dot-source this at the top of any
# script that needs the agents root or session root:
#
#   . (Join-Path $PSScriptRoot "_paths.ps1")
#
# Resolves (with env-var override):
#   $AgentsRoot      -- base agents dir            (default ~/.agents)
#   $GlobalSessionRoot -- device-wide session dir  (default $AgentsRoot/session-state)
#   $SessionRoot     -- active session state dir   (default <repo>/.kit/session-state in a bootstrapped repo, else $GlobalSessionRoot)
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

function Test-BootstrappedRepoRoot {
    param([string]$CandidatePath)
    if (-not $CandidatePath) { return $false }
    return (Test-Path (Join-Path $CandidatePath ".kit\context") -PathType Container) -or
           (Test-Path (Join-Path $CandidatePath ".kit\workflows") -PathType Container)
}

function Resolve-RepoSessionRoot {
    param([string]$StartPath = "")

    $current = $StartPath
    if (-not $current) {
        try {
            $current = (Get-Location).Path
        } catch {
            return $null
        }
    }
    if (-not $current) { return $null }

    try {
        $current = [System.IO.Path]::GetFullPath($current)
    } catch {
        return $null
    }

    while ($current) {
        if (Test-BootstrappedRepoRoot -CandidatePath $current) {
            return (Join-Path $current ".kit\session-state")
        }
        $parent = Split-Path $current -Parent
        if (-not $parent -or $parent -eq $current) { break }
        $current = $parent
    }

    return $null
}

$script:GlobalSessionRoot = Join-Path $script:AgentsRoot "session-state"

if ($env:AGENTS_SESSION_ROOT) {
    $script:SessionRoot = $env:AGENTS_SESSION_ROOT
    $script:SessionRootMode = "env-override"
} else {
    $repoSessionRoot = Resolve-RepoSessionRoot
    if ($repoSessionRoot) {
        $script:SessionRoot = $repoSessionRoot
        $script:SessionRootMode = "repo-local"
    } else {
        $script:SessionRoot = $script:GlobalSessionRoot
        $script:SessionRootMode = "global-default"
    }
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

function Get-CrossRepoIndexPath {
    Join-Path $script:GlobalSessionRoot "INDEX.md"
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
    # Bounded stdin read with timeout. Some hook hosts (notably Gemini CLI) redirect
    # stdin but never close it -- a naive ReadToEnd() blocks indefinitely. Read
    # asynchronously and bail after a short timeout, OR after stdin closes,
    # whichever comes first. Override timeout via AGENTS_HOOK_STDIN_TIMEOUT_MS.
    if ($script:_HookStdinRead) { return $script:_HookStdinCache }
    $script:_HookStdinRead = $true

    if (-not [Console]::IsInputRedirected) { return $null }

    $timeoutMs = 250
    if ($env:AGENTS_HOOK_STDIN_TIMEOUT_MS) {
        $parsed = 0
        if ([int]::TryParse($env:AGENTS_HOOK_STDIN_TIMEOUT_MS, [ref]$parsed) -and $parsed -ge 0) {
            $timeoutMs = $parsed
        }
    }
    if ($timeoutMs -eq 0) { return $null }

    try {
        $reader = [Console]::In
        $task = $reader.ReadToEndAsync()
        if ($task.Wait($timeoutMs)) {
            $raw = $task.Result
            if ($raw -and $raw.Trim()) {
                $script:_HookStdinCache = $raw | ConvertFrom-Json -ErrorAction SilentlyContinue
            }
        }
        # If timed out, leave cache as $null. The task continues running in the
        # background but the hook returns -- the host will reap the process.
    } catch {
        $script:_HookStdinCache = $null
    }
    return $script:_HookStdinCache
}

function Resolve-HookSessionId {
    param([string]$Provided)
    # Treat literal "${VAR}" / "$VAR" patterns as missing. Some hosts (Gemini CLI)
    # don't expand bash-style placeholders in their hook command lines, so the
    # raw template arrives here as a literal string. Using it as a session id
    # creates junk directories with $ and { characters in the path.
    if ($Provided -and $Provided -notmatch '^\$\{?\w+\}?$') { return $Provided }
    if ($env:CLAUDE_SESSION_ID)  { return $env:CLAUDE_SESSION_ID }
    if ($env:GEMINI_SESSION_ID)  { return $env:GEMINI_SESSION_ID }
    if ($env:CODEX_SESSION_ID)   { return $env:CODEX_SESSION_ID }
    if ($env:OPENCODE_SESSION_ID) { return $env:OPENCODE_SESSION_ID }
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
