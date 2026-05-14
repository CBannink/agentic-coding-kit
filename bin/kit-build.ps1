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

function Start-Heartbeat {
    param([string]$Agent, [string]$Task)

    Start-Job -ScriptBlock {
        param($SessionDir, $AgentLabel, $TaskLabel)
        while ($true) {
            Start-Sleep -Seconds 20
            $line = "{0} still-running[{1}]={2}" -f (Get-Date -Format 'yyyy-MM-dd HH:mm:ss'), $AgentLabel, $TaskLabel
            Add-Content -Path (Join-Path $SessionDir 'progress.log') -Value $line
        }
    } -ArgumentList $script:SessionDir, $Agent, $Task
}

function Stop-Heartbeat {
    param($Job)
    if (-not $Job) { return }
    Stop-Job -Job $Job -ErrorAction SilentlyContinue | Out-Null
    Remove-Job -Job $Job -Force -ErrorAction SilentlyContinue | Out-Null
}

function Invoke-CopilotCapture {
    param(
        [string]$Agent,
        [string]$Task,
        [string]$Prompt,
        [string]$OutputFile
    )

    Write-KitLog "spawned agent=$Agent"
    Write-KitLog "working[$Agent]=$Task"
    Record-Subagent -Agent $Agent -Task $Task -Status 'started'
    $start = Get-Date
    $heartbeat = Start-Heartbeat -Agent $Agent -Task $Task

    try {
        $allArgs = @($script:Copilot.Prefix) + @('--agent', $Agent, '-p', $Prompt, '--no-ask-user', '--allow-all-tools')
        & $script:Copilot.Command @allArgs 2>&1 |
            Tee-Object -FilePath $OutputFile | Out-Host
        $code = $LASTEXITCODE
    } finally {
        Stop-Heartbeat -Job $heartbeat
    }

    if ($code -eq 0) {
        Record-Subagent -Agent $Agent -Task $Task -Status 'done'
    } else {
        Record-Subagent -Agent $Agent -Task "$Task (exit=$code)" -Status 'failed'
    }

    $duration = [int]((Get-Date) - $start).TotalSeconds
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

Invoke-CopilotCapture `
    -Agent 'workflow-explorer' `
    -Task "map code surface for: $Goal" `
    -Prompt "Map the code surface relevant to: $Goal. Return: 3-5 likely files, integration points, conventions to follow." `
    -OutputFile (Join-Path $script:SessionDir 'explore.md')

Invoke-CopilotCapture `
    -Agent 'workflow-implementer' `
    -Task "implement: $Goal" `
    -Prompt "Implement: $Goal. Context from explorer is at $script:SessionDir\explore.md. Run the project's test command after editing and report exit code." `
    -OutputFile (Join-Path $script:SessionDir 'implement.md')

Invoke-CopilotCapture `
    -Agent 'code-quality-reviewer' `
    -Task 'review diff' `
    -Prompt "Review the diff in this repo against goal: $Goal. Tag findings BLOCKING/NON-BLOCKING/NIT." `
    -OutputFile (Join-Path $script:SessionDir 'review-quality.md')

Invoke-CopilotCapture `
    -Agent 'security-reviewer' `
    -Task 'security review diff' `
    -Prompt "Security review of the diff. Same tag scheme. Goal: $Goal." `
    -OutputFile (Join-Path $script:SessionDir 'review-security.md')

Write-Host "kit-build: review reports at $script:SessionDir\review-{quality,security}.md"
Write-Host "kit-build: ensure verification (tests/lint/build) is green before treating this as done."
