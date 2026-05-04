# sync-all-hosts.ps1
# Single-command sync of the kit's canonical content into all four CLI hosts:
# Claude Code, Gemini CLI, OpenCode, OpenAI Codex CLI.
#
# Source of truth: ~/.agents/global-instructions.md
# Each host's instruction file gets the canonical block synced via
# <!-- agentic-kit:begin --> / <!-- agentic-kit:end --> markers, preserving
# any host-specific preamble OR user content outside those markers.
#
# Usage:
#   pwsh ~/.agents/tools/sync-all-hosts.ps1            # sync all installed hosts
#   pwsh ~/.agents/tools/sync-all-hosts.ps1 -DryRun
#   pwsh ~/.agents/tools/sync-all-hosts.ps1 -Force     # skip per-host prompts
#   pwsh ~/.agents/tools/sync-all-hosts.ps1 -Hosts claude,gemini

[CmdletBinding()]
param(
    [switch]$DryRun,
    [switch]$Force,
    [string[]]$Hosts = @('claude','gemini','opencode','codex')
)

$ErrorActionPreference = 'Stop'

$AgentsRoot   = Join-Path $HOME ".agents"
$ClaudeRoot   = Join-Path $HOME ".claude"
$GeminiRoot   = Join-Path $HOME ".gemini"
$CodexRoot    = Join-Path $HOME ".codex"
$OpenCodeRoot = Join-Path $HOME ".config\opencode"

$canonicalPath = Join-Path $AgentsRoot 'global-instructions.md'
if (-not (Test-Path $canonicalPath)) {
    throw "Canonical source missing: $canonicalPath. Create it before syncing."
}

function Say([string]$msg, [string]$color='White') { Write-Host $msg -ForegroundColor $color }
function Section([string]$msg) { Say "`n=== $msg ===" 'Cyan' }

$Utf8NoBom = New-Object System.Text.UTF8Encoding($false)
function Write-NoBom([string]$path, [string]$content) {
    [System.IO.File]::WriteAllText($path, $content, $Utf8NoBom)
}

# ---------- canonical-block sync into a host file ----------
# Replaces between <!-- agentic-kit:begin --> and <!-- agentic-kit:end -->.
# If no markers present: prepends the canonical block at top.
# Returns: 'replaced' | 'prepended' | 'created'
function Sync-CanonicalBlock {
    param(
        [Parameter(Mandatory)] [string]$TargetPath,
        [Parameter(Mandatory)] [string]$CanonicalContent,
        [hashtable]$EnvVarMap = @{}
    )

    $content = $CanonicalContent
    foreach ($k in $EnvVarMap.Keys) {
        $content = $content -replace [regex]::Escape($k), $EnvVarMap[$k]
    }

    $beginMarker = '<!-- agentic-kit:begin -->'
    $endMarker   = '<!-- agentic-kit:end -->'

    if (-not (Test-Path $TargetPath)) {
        if (-not $DryRun) {
            New-Item -ItemType Directory -Path (Split-Path -Parent $TargetPath) -Force | Out-Null
            Write-NoBom $TargetPath $content
        }
        return 'created'
    }

    $current = Get-Content -Raw -Encoding utf8 -LiteralPath $TargetPath
    if ($current -match [regex]::Escape($beginMarker)) {
        $pattern = "(?s)" + [regex]::Escape($beginMarker) + ".*?" + [regex]::Escape($endMarker)
        $updated = [regex]::Replace($current, $pattern, $content.TrimEnd())
        if (-not $DryRun) { Write-NoBom $TargetPath $updated }
        return 'replaced'
    }

    # No markers -- prepend the canonical block above the existing content.
    $updated = $content.TrimEnd() + "`r`n`r`n" + $current
    if (-not $DryRun) { Write-NoBom $TargetPath $updated }
    return 'prepended'
}

# ---------- per-host configuration ----------
$canonical = Get-Content -Raw -Encoding utf8 -LiteralPath $canonicalPath

$ClaudeMap = @{}  # no env-var translation for Claude (it IS the source)
$GeminiMap = @{
    'CLAUDE_SESSION_ID'      = 'GEMINI_SESSION_ID'
    'CLAUDE_PROJECT_DIR'     = 'GEMINI_PROJECT_DIR'
    'CLAUDE_SUBAGENT_NAME'   = 'GEMINI_AGENT_NAME'
    'CLAUDE_SUBAGENT_STATUS' = 'GEMINI_AGENT_STATUS'
    'CLAUDE_MODE'            = 'GEMINI_MODE'
}
$CodexMap = @{
    'CLAUDE_SESSION_ID'  = 'CODEX_SESSION_ID'
    'CLAUDE_PROJECT_DIR' = 'CODEX_PROJECT_DIR'
    'CLAUDE_MODE'        = 'CODEX_MODE'
}
$OpenCodeMap = @{
    'CLAUDE_SESSION_ID'  = 'OPENCODE_SESSION_ID'
    'CLAUDE_PROJECT_DIR' = 'OPENCODE_PROJECT_DIR'
}

# ---------- per-host sync ----------
$results = @()

foreach ($h in $Hosts) {
    switch ($h.ToLower()) {
        'claude' {
            Section "Claude (CLAUDE.md)"
            if (-not (Test-Path $ClaudeRoot)) { Say "  ~/.claude not found -- skipping" 'Yellow'; continue }
            $target = Join-Path $ClaudeRoot 'CLAUDE.md'
            $action = Sync-CanonicalBlock -TargetPath $target -CanonicalContent $canonical -EnvVarMap $ClaudeMap
            $verb = if ($DryRun) { 'would ' } else { '' }
            Say "  $verb$action canonical block in $target" 'Green'
            $results += [pscustomobject]@{ host='claude'; file=$target; action=$action }
        }
        'gemini' {
            Section "Gemini (GEMINI.md + agents)"
            if (-not (Test-Path $GeminiRoot)) { Say "  ~/.gemini not found -- skipping" 'Yellow'; continue }
            $target = Join-Path $GeminiRoot 'GEMINI.md'
            $action = Sync-CanonicalBlock -TargetPath $target -CanonicalContent $canonical -EnvVarMap $GeminiMap
            $verb = if ($DryRun) { 'would ' } else { '' }
            Say "  $verb$action canonical block in $target" 'Green'
            $results += [pscustomobject]@{ host='gemini'; file=$target; action=$action }

            # Delegate agent/command/settings sync to the Gemini installer.
            $installer = Join-Path $AgentsRoot 'tools\install-gemini-kit.ps1'
            if (Test-Path $installer) {
                $installerArgs = @{}
                if ($DryRun) { $installerArgs.DryRun = $true }
                if ($Force)  { $installerArgs.Force = $true }
                Say "  -> delegating agents/commands/settings to install-gemini-kit.ps1" 'DarkGray'
                & $installer @installerArgs | Out-Host
            }
        }
        'opencode' {
            Section "OpenCode (prompt.md + agents)"
            $installer = Join-Path $AgentsRoot 'tools\install-opencode-kit.ps1'
            if (Test-Path $installer) {
                $installerArgs = @{}
                if ($DryRun) { $installerArgs.DryRun = $true }
                if ($Force)  { $installerArgs.Force = $true }
                & $installer @installerArgs | Out-Host
                $results += [pscustomobject]@{ host='opencode'; file=(Join-Path $OpenCodeRoot 'prompt.md'); action='via-installer' }
            } else {
                Say "  install-opencode-kit.ps1 not found" 'Yellow'
            }
        }
        'codex' {
            Section "Codex (AGENTS.md + agents as TOML)"
            $installer = Join-Path $AgentsRoot 'tools\install-codex-kit.ps1'
            if (Test-Path $installer) {
                $installerArgs = @{}
                if ($DryRun) { $installerArgs.DryRun = $true }
                if ($Force)  { $installerArgs.Force = $true }
                & $installer @installerArgs | Out-Host
                $results += [pscustomobject]@{ host='codex'; file=(Join-Path $CodexRoot 'AGENTS.md'); action='via-installer' }
            } else {
                Say "  install-codex-kit.ps1 not found" 'Yellow'
            }
        }
        default { Say "  unknown host: $h" 'Yellow' }
    }
}

# ---------- summary ----------
Section "Summary"
foreach ($r in $results) { Say ("  {0,-10}  {1,-12}  {2}" -f $r.host, $r.action, $r.file) 'DarkGray' }
Say "`nDone." 'Green'
