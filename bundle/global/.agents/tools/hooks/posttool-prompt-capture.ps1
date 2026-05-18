#!/usr/bin/env pwsh
# posttool-prompt-capture.ps1 -- PostToolUse hook that captures user corrections.
#
# Fires after user message submissions. Checks for correction signal words
# in the message text and appends a structured reflection entry to
# ~/.agents/context/reflections.md so the prompt-improver can act on it.
#
# Lightweight by design -- target < 100ms. No subprocess spawns.
#
# Correction signals: "no", "don't", "stop", "wrong", "not that", "instead",
#   "incorrect", "that's not", "undo", "revert", "you shouldn't", "don't do that"
#
# Opt-out: KIT_DISABLED_HOOKS=prompt-capture

$ErrorActionPreference = "Continue"
. (Join-Path $PSScriptRoot "../_paths.ps1") -ErrorAction SilentlyContinue

$disabledHooks = if ($env:KIT_DISABLED_HOOKS) { @($env:KIT_DISABLED_HOOKS -split ',') } else { @() }
if ($disabledHooks -contains "prompt-capture") { exit 0 }

# Read stdin payload (bounded by _paths.ps1 helper)
$payload = Get-HookStdinJson
if (-not $payload) { exit 0 }

# Only act on UserMessage or user_message tool types
$toolName = [string]$payload.tool_name
if ($toolName -notin @("UserMessage","user_message","HumanTurn","human_turn")) {
    # Also allow empty tool_name with a message field (some hosts)
    if ($toolName -and $toolName -ne "") { exit 0 }
}

# Extract message text -- try multiple payload shapes
$messageText = ""
if ($payload.tool_response -and $payload.tool_response.message) {
    $messageText = [string]$payload.tool_response.message
} elseif ($payload.tool_input -and $payload.tool_input.message) {
    $messageText = [string]$payload.tool_input.message
} elseif ($payload.message) {
    $messageText = [string]$payload.message
}

if (-not $messageText) { exit 0 }

# Correction signal detection (word-boundary aware where practical)
$signals = @(
    '\bno\b', '\bdon''t\b', '\bdo not\b', '\bstop\b', '\bwrong\b',
    '\bnot that\b', '\binstead\b', '\bincorrect\b', "that'?s not",
    '\bundo\b', '\brevert\b', "you shouldn'?t", "don'?t do that",
    '\bno,\s', '\bwrong,\s', '\bactually\b'
)

$matched = $false
foreach ($sig in $signals) {
    if ($messageText -imatch $sig) { $matched = $true; break }
}

if (-not $matched) { exit 0 }

# Truncate to first 100 chars for the entry
$excerpt = $messageText.Trim() -replace '\r?\n', ' '
if ($excerpt.Length -gt 100) { $excerpt = $excerpt.Substring(0, 100) }

$reflectionsPath = Join-Path $script:AgentsRoot "context/reflections.md"
$date = Get-Date -Format "yyyy-MM-dd"

$entry = @"

- [$date] [class:correction] [auto-captured]
  Pattern: User corrected agent behavior -- "$excerpt"
  Evidence: Captured by posttool-prompt-capture hook
  Suggested target: ~/.agents/context/reflections.md
"@

# Ensure parent dir exists, then append -- no subprocess, direct file write
try {
    $dir = Split-Path $reflectionsPath
    if (-not (Test-Path $dir)) { New-Item -ItemType Directory -Path $dir -Force | Out-Null }
    [System.IO.File]::AppendAllText($reflectionsPath, $entry, [System.Text.UTF8Encoding]::new($false))
} catch {
    # Silent -- hook must never surface errors to the user as a hard block
}

exit 0
