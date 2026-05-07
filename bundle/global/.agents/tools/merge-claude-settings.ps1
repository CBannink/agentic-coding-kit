#!/usr/bin/env pwsh
# merge-claude-settings.ps1 -- additively merge the kit's hook config into
# the user's ~/.claude/settings.json. Preserves all existing keys.
#
# Usage:
#   pwsh ~/.agents/tools/merge-claude-settings.ps1
#   pwsh ~/.agents/tools/merge-claude-settings.ps1 -SnippetPath /path/to/settings.snippet.json
#   pwsh ~/.agents/tools/merge-claude-settings.ps1 -DryRun   # show what would change
#
# Strategy:
#   - Read existing ~/.claude/settings.json (create empty {} if missing)
#   - Read the kit's settings.snippet.json (drop the _comment key)
#   - Deep-merge with kit values WINNING for the `hooks.<event>` arrays
#     (we replace each event array, not append, so re-running is idempotent)
#   - Backfill a kit default model only when the user has not chosen one
#   - Write back, preserving all unrelated user keys
#
# This is the only adapter step that touches a file outside the repo.

param(
    [string]$SettingsPath = (Join-Path $HOME ".claude/settings.json"),
    [string]$SnippetPath  = "",
    [switch]$DryRun
)

. (Join-Path $PSScriptRoot "_paths.ps1")

if (-not $SnippetPath) {
    # Resolve from this kit's checkout — assume install copied the adapter to the user's repo OR the snippet is bundled next to the kit
    $candidates = @(
        (Join-Path $PSScriptRoot "../../../adapters/claude-code/.claude/settings.snippet.json"),
        (Join-Path (Get-Location) "bundle/adapters/claude-code/.claude/settings.snippet.json"),
        (Join-Path (Get-Location) ".claude/settings.snippet.json")
    )
    foreach ($c in $candidates) {
        if (Test-Path $c) { $SnippetPath = (Resolve-Path $c).Path; break }
    }
}

if (-not (Test-Path $SnippetPath)) {
    Write-Error "settings.snippet.json not found. Pass -SnippetPath explicitly."
    exit 1
}

# Load snippet (strip _comment for merge)
$snippetRaw = Get-Content $SnippetPath -Raw -Encoding UTF8 | ConvertFrom-Json
$snippet = [pscustomobject]@{}
foreach ($p in $snippetRaw.PSObject.Properties) {
    if ($p.Name -ne "_comment") {
        $snippet | Add-Member -NotePropertyName $p.Name -NotePropertyValue $p.Value
    }
}

# Load existing (or empty)
$existing = if (Test-Path $SettingsPath) {
    Get-Content $SettingsPath -Raw -Encoding UTF8 | ConvertFrom-Json
} else {
    [pscustomobject]@{}
}

# Ensure existing has a `hooks` key
if (-not ($existing.PSObject.Properties.Name -contains "hooks")) {
    $existing | Add-Member -NotePropertyName "hooks" -NotePropertyValue ([pscustomobject]@{}) -Force
}

# Backfill the preferred Claude orchestrator model only when absent.
# This keeps a clean default for fresh installs without clobbering an
# explicit user choice on re-install.
if (-not ($existing.PSObject.Properties.Name -contains "model") -or [string]::IsNullOrWhiteSpace([string]$existing.model)) {
    $existing | Add-Member -NotePropertyName "model" -NotePropertyValue "claude-opus-4-6" -Force
    Write-Host "  model: defaulted to claude-opus-4-6"
}

# Merge: replace each event array (idempotent on re-run)
foreach ($event in $snippet.hooks.PSObject.Properties) {
    $existing.hooks | Add-Member -NotePropertyName $event.Name -NotePropertyValue $event.Value -Force
    Write-Host "  hooks.$($event.Name): wired $(@($event.Value).Count) matcher(s)"
}

$rendered = $existing | ConvertTo-Json -Depth 12

if ($DryRun) {
    Write-Host ""
    Write-Host "DRY RUN -- would write to ${SettingsPath}:"
    Write-Host ""
    Write-Output $rendered
    exit 0
}

# Backup existing if it exists
if (Test-Path $SettingsPath) {
    $backup = "$SettingsPath.before-agentic-kit-$(Get-Date -Format 'yyyyMMdd-HHmmss')"
    Copy-Item -Force $SettingsPath $backup
    Write-Host "  backup: $backup"
}

New-Item -ItemType Directory -Path (Split-Path -Parent $SettingsPath) -Force | Out-Null
Set-Content -Path $SettingsPath -Value $rendered -Encoding UTF8
Write-Host ""
Write-Host "Wrote $SettingsPath"
Write-Host "Restart Claude Code for hooks to take effect."
