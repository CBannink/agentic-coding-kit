#!/usr/bin/env pwsh
[CmdletBinding()]
param(
    [Parameter(Mandatory = $true, Position = 0, ValueFromRemainingArguments = $true)]
    [string[]]$GoalParts
)

$ErrorActionPreference = 'Stop'
$Goal = ($GoalParts -join ' ').Trim()
if ([string]::IsNullOrWhiteSpace($Goal)) {
    throw "Usage: kit-build.ps1 '<request>'"
}

# Per-phase timeouts (seconds, 0 = disabled). Override via env vars.
$script:ExplorerTimeoutSec  = if ($env:KIT_BUILD_EXPLORER_TIMEOUT)  { [int]$env:KIT_BUILD_EXPLORER_TIMEOUT  } else { 180 }
$script:ImplementTimeoutSec = if ($env:KIT_BUILD_IMPLEMENT_TIMEOUT) { [int]$env:KIT_BUILD_IMPLEMENT_TIMEOUT } else { 360 }
$script:ReviewTimeoutSec    = if ($env:KIT_BUILD_REVIEW_TIMEOUT)    { [int]$env:KIT_BUILD_REVIEW_TIMEOUT    } else { 180 }

function Get-SessionRoot {
    param([string]$RepoRoot)

    if ($env:AGENTS_SESSION_ROOT) { return $env:AGENTS_SESSION_ROOT }

    $current = $RepoRoot
    while ($current) {
        if ((Test-Path (Join-Path $current '.kit\context')) -or (Test-Path (Join-Path $current '.kit\workflows'))) {
            return (Join-Path $current '.kit\session-state')
        }

        $parent = Split-Path -Parent $current
        if ($parent -eq $current) { break }
        $current = $parent
    }

    return (Join-Path $HOME '.agents\session-state')
}

function Write-KitLog {
    param([string]$Message)
    $line = "$(Get-Date -Format 'yyyy-MM-dd HH:mm:ss') $Message"
    Write-Host $line
    Add-Content -Path (Join-Path $script:SessionDir 'progress.log') -Value $line
}

function Resolve-CopilotCommand {
    $copilot = Get-Command copilot -ErrorAction SilentlyContinue
    if ($copilot) {
        return [pscustomobject]@{ Command = $copilot.Source; Prefix = @(); Label = 'copilot' }
    }

    $gh = Get-Command gh -ErrorAction SilentlyContinue
    if ($gh) {
        return [pscustomobject]@{ Command = $gh.Source; Prefix = @('copilot'); Label = 'gh copilot' }
    }

    throw "GitHub Copilot CLI not found. Install the standalone 'copilot' binary or 'gh' with Copilot enabled."
}

function Invoke-KitTool {
    param(
        [string]$ToolPath,
        [string[]]$Arguments = @()
    )

    if (-not (Test-Path $ToolPath)) { return }
    try {
        & $ToolPath @Arguments | Out-Null
    } catch {
        Write-KitLog "WARN -- tool failed: $ToolPath"
    }
}

function Record-Subagent {
    param(
        [string]$Agent,
        [string]$Task,
        [string]$Status
    )

    $line = "{0}`t{1}`t{2}`t{3}" -f (Get-Date -Format 'yyyy-MM-dd HH:mm:ss'), $Agent, $Status, $Task
    Add-Content -Path (Join-Path $script:SessionDir 'agent-status.tsv') -Value $line

    if (-not (Test-Path $script:WorkflowEvidenceTool)) { return }
    if ($Status -eq 'started') {
        Invoke-KitTool -ToolPath $script:WorkflowEvidenceTool -Arguments @('-SessionId', $script:SessionId, '-AddAgent', "$Agent|$Task")
    }
    Invoke-KitTool -ToolPath $script:WorkflowEvidenceTool -Arguments @('-SessionId', $script:SessionId, '-AddNote', "subagent:$Status|$Agent|$Task")
}

# Returns $true when the goal is trivially scoped (explicit file ref or < 12 words).
function Test-TrivialGoal {
    param([string]$Goal)
    if ($Goal -match '\.[a-zA-Z]{2,5}(\s|$|/)') { return $true }
    if (($Goal.Trim() -split '\s+').Count -lt 12) { return $true }
    return $false
}

# Runs a Copilot agent phase with an optional wall-clock timeout.
# Uses Start-Job so the wrapper process never hangs indefinitely.
# Streams captured output to console via file polling (20s intervals = heartbeat cadence).
# On timeout: appends a WARN line to OutputFile and either continues (ContinueOnTimeout)
#             or throws (default).
function Invoke-CopilotCapture {
    param(
        [string]$Agent,
        [string]$Task,
        [string]$Prompt,
        [string]$OutputFile,
        [int]$TimeoutSec = 0,
        [switch]$ContinueOnTimeout
    )

    Write-KitLog "spawned agent=$Agent"
    Write-KitLog "working[$Agent]=$Task"
    Record-Subagent -Agent $Agent -Task $Task -Status 'started'
    $start = Get-Date

    # Temp file used to capture exit code from the job subprocess.
    $exitCodeFile = Join-Path $script:SessionDir ("._ec_{0}_{1}" -f $Agent, (Get-Date -Format 'HHmmssff'))
    $copilotCmd    = $script:Copilot.Command
    $copilotPrefix = $script:Copilot.Prefix

    $job = Start-Job -ScriptBlock {
        param($Cmd, $Prefix, $Agent, $Prompt, $OutFile, $EcFile)
        $jobArgs = $Prefix + @('--agent', $Agent, '-p', $Prompt, '--no-ask-user', '--allow-all-tools')
        & $Cmd @jobArgs 2>&1 | Tee-Object -FilePath $OutFile
        Set-Content -Path $EcFile -Value "$LASTEXITCODE" -NoNewline -ErrorAction SilentlyContinue
    } -ArgumentList $copilotCmd, $copilotPrefix, $Agent, $Prompt, $OutputFile, $exitCodeFile

    # Poll loop: stream output to console, emit heartbeat, enforce timeout.
    $heartbeatSec = 20
    $timedOut     = $false
    $lastFileSize = 0

    while ($true) {
        $done = Wait-Job -Job $job -Timeout $heartbeatSec
        if ($done) { break }

        # Stream any new bytes from the output file to the console.
        if (Test-Path $OutputFile) {
            try {
                $raw = [System.IO.File]::ReadAllText($OutputFile)
                if ($raw.Length -gt $lastFileSize) {
                    Write-Host $raw.Substring($lastFileSize) -NoNewline
                    $lastFileSize = $raw.Length
                }
            } catch { }
        }

        $elapsed = [int]((Get-Date) - $start).TotalSeconds
        Write-KitLog "still-running[$Agent]=$Task (${elapsed}s)"

        if ($TimeoutSec -gt 0 -and $elapsed -ge $TimeoutSec) {
            Write-KitLog "WARN -- $Agent timed out after ${TimeoutSec}s"
            Stop-Job  -Job $job -ErrorAction SilentlyContinue | Out-Null
            Remove-Job -Job $job -Force -ErrorAction SilentlyContinue | Out-Null
            Remove-Item $exitCodeFile -ErrorAction SilentlyContinue | Out-Null
            $timedOut = $true
            break
        }
    }

    if (-not $timedOut) {
        Receive-Job -Job $job -ErrorAction SilentlyContinue | Out-Null
        Remove-Job  -Job $job -Force -ErrorAction SilentlyContinue | Out-Null
        # Flush any remaining file content to the console.
        if (Test-Path $OutputFile) {
            try {
                $raw = [System.IO.File]::ReadAllText($OutputFile)
                if ($raw.Length -gt $lastFileSize) {
                    Write-Host $raw.Substring($lastFileSize) -NoNewline
                }
            } catch { }
        }
    }

    # Read exit code written by the job.
    $code = 0
    if (Test-Path $exitCodeFile) {
        $ecStr = (Get-Content $exitCodeFile -Raw -ErrorAction SilentlyContinue).Trim()
        if ($ecStr -match '^\d+$') { $code = [int]$ecStr }
        Remove-Item $exitCodeFile -ErrorAction SilentlyContinue | Out-Null
    }

    $duration = [int]((Get-Date) - $start).TotalSeconds

    if ($timedOut) {
        Add-Content -Path $OutputFile -Value "`n`n---`nWARN: $Agent timed out after ${duration}s." -ErrorAction SilentlyContinue
        Record-Subagent -Agent $Agent -Task "$Task (timed-out after ${duration}s)" -Status 'failed'
        Write-KitLog "completed agent=$Agent duration=${duration}s status=timed-out"
        if ($ContinueOnTimeout) { return }
        throw "Agent $Agent timed out after ${duration}s. Set KIT_BUILD_$($Agent.ToUpper().Replace('-','_'))_TIMEOUT to increase."
    }

    if ($code -eq 0) {
        Record-Subagent -Agent $Agent -Task $Task -Status 'done'
    } else {
        Record-Subagent -Agent $Agent -Task "$Task (exit=$code)" -Status 'failed'
    }

    Write-KitLog "completed agent=$Agent duration=${duration}s"

    if ($code -ne 0) {
        throw "Agent $Agent failed with exit code $code"
    }
}

$repoRoot = (Get-Location).Path
$sessionRoot = Get-SessionRoot -RepoRoot $repoRoot
$script:SessionDir = Join-Path $sessionRoot ("{0:yyyyMMdd-HHmmss}-build" -f (Get-Date))
New-Item -ItemType Directory -Path $script:SessionDir -Force | Out-Null
$script:SessionId = Split-Path -Leaf $script:SessionDir
$agentsRoot = if ($env:AGENTS_HOME) { $env:AGENTS_HOME } else { Join-Path $HOME '.agents' }
$script:WorkflowEvidenceTool = Join-Path $agentsRoot 'tools\workflow-evidence.ps1'
$script:Copilot = Resolve-CopilotCommand

Write-KitLog "kit-build: session=$script:SessionDir"
Write-KitLog "kit-build: cli=$($script:Copilot.Label)"
Write-KitLog "kit-build: goal=$Goal"
Write-KitLog ("kit-build: timeouts explorer={0}s implement={1}s review={2}s" -f $script:ExplorerTimeoutSec, $script:ImplementTimeoutSec, $script:ReviewTimeoutSec)

# Phase 1 -- explore (skipped for trivially-scoped single-file goals)
if (Test-TrivialGoal -Goal $Goal) {
    Write-KitLog "kit-build: trivial goal detected -- fast-pathing explorer"
    Set-Content -Path (Join-Path $script:SessionDir 'explore.md') `
        -Value "# Fast-path explore (trivial goal)`n`nGoal: $Goal`n`nNo deep exploration needed for trivially-scoped goals."
} else {
    Invoke-CopilotCapture `
        -Agent 'workflow-explorer' `
        -Task "map code surface for: $Goal" `
        -Prompt "Map the code surface relevant to: $Goal. Return: 3-5 likely files, integration points, conventions to follow." `
        -OutputFile (Join-Path $script:SessionDir 'explore.md') `
        -TimeoutSec $script:ExplorerTimeoutSec `
        -ContinueOnTimeout
}

# Phase 2 -- implement (hard timeout; timeout here is fatal)
Invoke-CopilotCapture `
    -Agent 'workflow-implementer' `
    -Task "implement: $Goal" `
    -Prompt "Implement: $Goal. Context from explorer is at $script:SessionDir\explore.md. Run the project's test command after editing and report exit code." `
    -OutputFile (Join-Path $script:SessionDir 'implement.md') `
    -TimeoutSec $script:ImplementTimeoutSec

# Phase 3 -- review (non-blocking: timeout or failure logged but does not abort)
foreach ($review in @(
    @{ Agent = 'code-quality-reviewer'; Task = 'review diff';
       Prompt = "Review the diff in this repo against goal: $Goal. Tag findings BLOCKING/NON-BLOCKING/NIT.";
       Out    = (Join-Path $script:SessionDir 'review-quality.md') },
    @{ Agent = 'security-reviewer';     Task = 'security review diff';
       Prompt = "Security review of the diff. Same tag scheme. Goal: $Goal.";
       Out    = (Join-Path $script:SessionDir 'review-security.md') }
)) {
    try {
        Invoke-CopilotCapture `
            -Agent  $review.Agent `
            -Task   $review.Task `
            -Prompt $review.Prompt `
            -OutputFile $review.Out `
            -TimeoutSec $script:ReviewTimeoutSec `
            -ContinueOnTimeout
    } catch {
        Write-KitLog "WARN -- $($review.Agent) failed: $_"
    }
}

Write-Host "kit-build: review reports at $script:SessionDir\review-{quality,security}.md"
Write-Host "kit-build: ensure verification (tests/lint/build) is green before treating this as done."
