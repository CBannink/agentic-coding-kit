#!/usr/bin/env pwsh

$ScriptRoot = Split-Path -Parent $MyInvocation.MyCommand.Path
$RepoRoot = Split-Path -Parent $ScriptRoot
$SharedRoot = Join-Path $RepoRoot "bundle\adapters\_shared\orchestrator"
$MainTemplate = Join-Path $SharedRoot "main-session.template.md"
$PrimaryAgentTemplate = Join-Path $SharedRoot "primary-agent.template.md"
$Utf8NoBom = New-Object System.Text.UTF8Encoding($false)

function Write-RenderedFile {
    param(
        [string]$TemplatePath,
        [string]$DestinationPath,
        [hashtable]$Vars
    )

    $content = Get-Content -Raw -Encoding UTF8 -LiteralPath $TemplatePath
    if ($content.Length -gt 0 -and [int][char]$content[0] -eq 0xFEFF) {
        $content = $content.Substring(1)
    }

    foreach ($key in $Vars.Keys) {
        $content = $content.Replace($key, $Vars[$key])
    }

    $content = $content -replace "(?m)^[ \t]+\r?\n", ""
    $content = $content -replace "(\r?\n){3,}", "`r`n`r`n"
    $content = $content.Trim() + "`r`n"

    $parent = Split-Path -Parent $DestinationPath
    if (-not (Test-Path $parent)) {
        New-Item -ItemType Directory -Path $parent -Force | Out-Null
    }

    [System.IO.File]::WriteAllText($DestinationPath, $content, $Utf8NoBom)
    Write-Host "Wrote $DestinationPath"
}

$copilotConstraints = @"
## Host constraints (critical - modify your behavior)

- Subagent output is NOT streamed (issue #2265) - user sees nothing until the
  agent completes. Shell stdout is buffered (issue #1127).
- Per-command timeout is ~5-6 minutes. Each leaf agent must complete in <5 min.
- **YOU are the orchestrator.** Never spawn goal-orchestrator or
  build-orchestrator - they run silently. Only delegate to leaf agents.
"@

$copilotWorkflowLoading = @"
## Workflow loading

When a workflow is selected, read the matching skill under
`~/.agents/skills/<name>/SKILL.md`.
"@

$claudeTrailer = @"
## Model routing (Claude Code)

- **Main session / orchestration**: `claude-opus-4-6`
- **Implementation + review**: `claude-sonnet-4-6`
- **Cheap exploration**: `claude-haiku-4-5`
"@

$openCodeAgentFrontmatter = @"
---
name: orchestrator
description: "Main session agent - classifies requests, decides inline vs workflow first, then loads the right workflow or leaf agent. The top-level orchestrator for the Caspar Bannink Agentic Coding Kit."
mode: primary
task: true
---
"@

$openCodeAgentTrailer = @"
## Workflow loading

Read workflow skills on demand via the matching `~/.agents/skills/<name>/SKILL.md`
path:

- `~/.agents/skills/build/SKILL.md`
- `~/.agents/skills/analyze/SKILL.md`
- `~/.agents/skills/review/SKILL.md`
- `~/.agents/skills/investigate/SKILL.md`
- `~/.agents/skills/plan/SKILL.md`
- `~/.agents/skills/refactor/SKILL.md`
- `~/.agents/skills/redesign/SKILL.md`
- `~/.agents/skills/security-review/SKILL.md`
- `~/.agents/skills/goal/SKILL.md`

## Session management

- Session ID: `$CLAUDE_SESSION_ID` or `$SESSION_ID`
- AGENTS_SESSION_ROOT: `~/.agents/session-state/` (or `.kit/session-state/` in bootstrapped repos)
- New session starts with you as the primary agent
- Subagent sessions are children - use Tab/arrow keys to navigate
"@

$mainTargets = @(
    @{
        Destination = Join-Path $RepoRoot "bundle\adapters\claude-code\CLAUDE.md"
        Vars = @{
            "__TITLE__" = "CLAUDE.md - Claude Code Orchestrator"
            "__INTRO_BLOCK__" = "YOU are the default orchestrator. Every session starts here.`r`nYour job: classify every request, route it to the right agent, drive completion.`r`nYou are a coordinator - not an implementer."
            "__OPTIONAL_PREAMBLE__" = ""
            "__OPTIONAL_HOST_CONSTRAINTS__" = ""
            "__OPTIONAL_WORKFLOW_LOADING__" = ""
            "__OPTIONAL_TRAILER__" = $claudeTrailer
        }
    },
    @{
        Destination = Join-Path $RepoRoot "bundle\adapters\opencode\AGENTS.md"
        Vars = @{
            "__TITLE__" = "AGENTS.md - OpenCode Orchestrator"
            "__INTRO_BLOCK__" = "YOU are the default orchestrator. Every session starts here.`r`nYour job: classify every request, route it to the right agent, drive completion.`r`nYou are a coordinator - not an implementer."
            "__OPTIONAL_PREAMBLE__" = ""
            "__OPTIONAL_HOST_CONSTRAINTS__" = ""
            "__OPTIONAL_WORKFLOW_LOADING__" = ""
            "__OPTIONAL_TRAILER__" = ""
        }
    },
    @{
        Destination = Join-Path $RepoRoot "bundle\adapters\copilot-cli\.github\copilot-instructions.md"
        Vars = @{
            "__TITLE__" = "GitHub Copilot Instructions - Caspar Bannink Agentic Coding Kit"
            "__INTRO_BLOCK__" = "Copilot Chat / Copilot CLI reads this file. Every session starts here."
            "__OPTIONAL_PREAMBLE__" = "The global workflow skills under `~/.agents/skills/` are the canonical phase content - this file handles host constraints only."
            "__OPTIONAL_HOST_CONSTRAINTS__" = $copilotConstraints
            "__OPTIONAL_WORKFLOW_LOADING__" = $copilotWorkflowLoading
            "__OPTIONAL_TRAILER__" = "## Core rules`r`n`r`n1. Respect `.kit/` layout - memory in `.kit/context/`, handoffs in session-state.`r`n2. `.wiki/features.md` + `.wiki/.features` carry user-visible capabilities.`r`n3. Self-improvement runs automatically in post-session. Only call `/reflect` manually when reflections.md has 5+ unaddressed entries needing judgment."
        }
    }
)

foreach ($target in $mainTargets) {
    Write-RenderedFile -TemplatePath $MainTemplate -DestinationPath $target.Destination -Vars $target.Vars
}

Write-RenderedFile `
    -TemplatePath $PrimaryAgentTemplate `
    -DestinationPath (Join-Path $RepoRoot "bundle\adapters\opencode\.opencode\agents\orchestrator.md") `
    -Vars @{
        "__FRONTMATTER__" = $openCodeAgentFrontmatter
        "__INTRO_BLOCK__" = "You are the **orchestrator** - the primary session agent for the Caspar Bannink Agentic Coding Kit on OpenCode. Your job is to make the small routing decision first, then either act inline or load the right workflow."
        "__OPTIONAL_WORKFLOW_LOADING__" = ""
        "__OPTIONAL_TRAILER__" = $openCodeAgentTrailer
    }
