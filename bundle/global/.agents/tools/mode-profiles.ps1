#!/usr/bin/env pwsh
# mode-profiles.ps1
# Resolves mode profiles for subagent spawning.
# Returns a JSON object including a ready-to-embed prompt_block.
#
# Usage:
#   pwsh ~/.agents/tools/mode-profiles.ps1 -Mode debug
#   pwsh ~/.agents/tools/mode-profiles.ps1 -Mode architect -RepoRoot C:\path\to\repo
#
# Repo overrides: place .kit/modes/{mode}.json in the repo to merge on top of
# the built-in defaults. Only include fields you want to override.

param(
    [Parameter(Mandatory = $true)]
    [string]$Mode,
    [string]$RepoRoot = ""
)

. (Join-Path $PSScriptRoot "_paths.ps1")

if (-not $RepoRoot) {
    $RepoRoot = (Get-Location).Path
}

# --- Built-in mode profiles ---------------------------------------------------

$builtInProfiles = @{
    "debug" = [ordered]@{
        tools_allow         = @("Read", "Grep", "Glob", "Bash(read-only)", "WebSearch", "WebFetch")
        tools_deny          = @("Edit", "Write", "NotebookEdit")
        file_patterns_read  = @("**/*")
        file_patterns_write = @()
        persona             = "Diagnostic investigator. Read everything, write nothing. Find root causes."
    }
    "architect" = [ordered]@{
        tools_allow         = @("Read", "Grep", "Glob", "Write", "Edit")
        tools_deny          = @("Bash")
        file_patterns_read  = @("**/*")
        file_patterns_write = @("*.md", ".wiki/**", ".kit/**", "docs/**", "*.txt")
        persona             = "System architect. Edit documentation and design files only. Never touch source code."
    }
    "reviewer" = [ordered]@{
        tools_allow         = @("Read", "Grep", "Glob")
        tools_deny          = @("Edit", "Write", "Bash", "NotebookEdit")
        file_patterns_read  = @("**/*")
        file_patterns_write = @()
        persona             = "Code reviewer. Read and analyze only. Report findings, never fix them."
    }
    "implementer" = [ordered]@{
        tools_allow         = @("Read", "Grep", "Glob", "Edit", "Write", "Bash")
        tools_deny          = @()
        file_patterns_read  = @("**/*")
        file_patterns_write = @("**/*")
        persona             = "Implementation agent. Full access. Edit source, run tests, fix issues."
    }
    "explorer" = [ordered]@{
        tools_allow         = @("Read", "Grep", "Glob", "Bash(read-only)")
        tools_deny          = @("Edit", "Write", "NotebookEdit")
        file_patterns_read  = @("**/*")
        file_patterns_write = @()
        persona             = "Codebase explorer. Read-only navigation. Map files, find patterns, report structure."
    }
    "security-reviewer" = [ordered]@{
        tools_allow         = @("Read", "Grep", "Glob", "WebSearch")
        tools_deny          = @("Edit", "Write", "Bash", "NotebookEdit")
        file_patterns_read  = @("**/*")
        file_patterns_write = @()
        persona             = "Security auditor. Read-only analysis with web research. Report vulnerabilities, never fix them."
    }
}

$availableModes = ($builtInProfiles.Keys | Sort-Object) -join ", "

# --- Load built-in profile ----------------------------------------------------

$modeKey = $Mode.ToLower()

if (-not $builtInProfiles.ContainsKey($modeKey)) {
    # Check repo override before failing — a repo can define entirely new modes.
    $repoOverridePath = Join-Path $RepoRoot ".kit\modes\$modeKey.json"
    if (-not (Test-Path $repoOverridePath)) {
        $err = [ordered]@{
            error           = "Unknown mode: '$Mode'"
            available_modes = $builtInProfiles.Keys | Sort-Object
            hint            = "Built-in modes: $availableModes. Add .kit/modes/$modeKey.json to define a custom mode."
        }
        Write-Output ($err | ConvertTo-Json -Compress -Depth 4)
        exit 1
    }

    # Repo-only custom mode — start from an empty base.
    $profile = [ordered]@{
        tools_allow         = @()
        tools_deny          = @()
        file_patterns_read  = @()
        file_patterns_write = @()
        persona             = ""
    }
} else {
    # Deep-copy the built-in so we don't mutate the hashtable.
    $src = $builtInProfiles[$modeKey]
    $profile = [ordered]@{
        tools_allow         = @($src.tools_allow)
        tools_deny          = @($src.tools_deny)
        file_patterns_read  = @($src.file_patterns_read)
        file_patterns_write = @($src.file_patterns_write)
        persona             = $src.persona
    }
}

# --- Repo override (merge on top) ---------------------------------------------

$repoModePath = Join-Path $RepoRoot ".kit\modes\$modeKey.json"
$repoOverrideApplied = $false

if (Test-Path $repoModePath) {
    try {
        $override = Get-Content $repoModePath -Raw | ConvertFrom-Json -ErrorAction Stop

        if ($null -ne $override.tools_allow)         { $profile.tools_allow         = @($override.tools_allow) }
        if ($null -ne $override.tools_deny)          { $profile.tools_deny          = @($override.tools_deny) }
        if ($null -ne $override.file_patterns_read)  { $profile.file_patterns_read  = @($override.file_patterns_read) }
        if ($null -ne $override.file_patterns_write) { $profile.file_patterns_write = @($override.file_patterns_write) }
        if ($override.persona)                       { $profile.persona             = [string]$override.persona }

        $repoOverrideApplied = $true
    } catch {
        # Malformed JSON — surface as a warning but continue with built-in.
        Write-Warning "mode-profiles: failed to parse $repoModePath — using built-in defaults. Error: $_"
    }
}

# --- Build prompt_block -------------------------------------------------------

$modeLabel     = $Mode.ToUpper()
$allowList     = if ($profile.tools_allow.Count -gt 0) { $profile.tools_allow -join ", " } else { "(none)" }
$denyList      = if ($profile.tools_deny.Count -gt 0)  { $profile.tools_deny  -join ", " } else { "(none)" }
$writePatterns = if ($profile.file_patterns_write.Count -gt 0) { $profile.file_patterns_write -join ", " } else { "(none - do not write any files)" }

$promptBlock = @"
## Mode restrictions
You are operating in $modeLabel mode.

- Allowed tools: $allowList
- Denied tools: $denyList
- Readable file patterns: $($profile.file_patterns_read -join ", ")
- Writable file patterns: $writePatterns

Persona: $($profile.persona)

Treat denied tools as unavailable. If you would normally reach for a denied tool,
report that you cannot perform the action rather than finding a workaround.
"@
$promptBlock = $promptBlock.Trim()

# --- Output -------------------------------------------------------------------

$result = [ordered]@{
    mode                  = $modeKey
    tools_allow           = $profile.tools_allow
    tools_deny            = $profile.tools_deny
    file_patterns_read    = $profile.file_patterns_read
    file_patterns_write   = $profile.file_patterns_write
    persona               = $profile.persona
    repo_override_applied = $repoOverrideApplied
    repo_override_path    = if ($repoOverrideApplied) { $repoModePath } else { "" }
    prompt_block          = $promptBlock
}

Write-Output ($result | ConvertTo-Json -Compress -Depth 6)
