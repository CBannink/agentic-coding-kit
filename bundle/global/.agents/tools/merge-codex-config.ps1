#!/usr/bin/env pwsh
# merge-codex-config.ps1 -- additively append the kit's Codex CLI hook
# block into ~/.codex/config.toml using <<<agentic-kit:codex-hooks
# markers. Idempotent: skips if marker block already present.
#
# Why TOML-append-with-marker rather than parse-and-merge: PowerShell has
# no built-in TOML parser, and a line-based append is safe AS LONG AS the
# marker block is single-injection. The closing `>>>` marker prevents
# duplicate injection on re-run.
#
# Codex CLI hook config schema source:
#   https://developers.openai.com/codex/hooks
# Coverage caveat (issue #20204): hooks fire for Bash, apply_patch, and
# MCP tools. Reads / plan / web_search are silent.
#
# Usage:
#   pwsh merge-codex-config.ps1 [-SnippetPath <path>] [-ConfigPath <path>] [-DryRun]
#   pwsh merge-codex-config.ps1 -Remove   # strip the kit's block (for opt-out)
#
# Defaults:
#   -SnippetPath -> bundle/adapters/codex-cli/.codex/hooks.snippet.toml
#   -ConfigPath  -> ~/.codex/config.toml

param(
    [string]$SnippetPath = "",
    [string]$ConfigPath = (Join-Path $HOME ".codex/config.toml"),
    [switch]$DryRun,
    [switch]$Remove
)

if (-not $SnippetPath) {
    foreach ($candidate in @(
        (Join-Path $PSScriptRoot "../../../adapters/codex-cli/.codex/hooks.snippet.toml"),
        (Join-Path (Get-Location) "bundle/adapters/codex-cli/.codex/hooks.snippet.toml")
    )) {
        if (Test-Path $candidate) { $SnippetPath = (Resolve-Path $candidate).Path; break }
    }
}

if (-not $Remove -and (-not $SnippetPath -or -not (Test-Path $SnippetPath))) {
    Write-Error "Snippet not found. Pass -SnippetPath explicitly."
    exit 1
}

$startMarker = "# <<< agentic-kit:codex-hooks"
$endMarker = "# >>> agentic-kit:codex-hooks"

# Read existing config (if any)
$existing = ""
if (Test-Path $ConfigPath) {
    $existing = Get-Content $ConfigPath -Raw -Encoding UTF8
}

# Strip any existing marker block (for re-run + Remove modes)
if ($existing -match [regex]::Escape($startMarker)) {
    # Remove everything between markers (inclusive)
    $stripPattern = [regex]::Escape($startMarker) + '.*?' + [regex]::Escape($endMarker) + '\r?\n?'
    $existing = [regex]::Replace($existing, $stripPattern, '', 'Singleline')
    $existing = $existing.TrimEnd("`r", "`n") + "`r`n"
}

if ($Remove) {
    if ($DryRun) {
        Write-Host "DRY RUN -- would write (kit block removed):"
        Write-Host $existing
    } else {
        New-Item -ItemType Directory -Path (Split-Path -Parent $ConfigPath) -Force | Out-Null
        Set-Content -Path $ConfigPath -Value $existing -Encoding UTF8
        Write-Host "Removed kit hook block from $ConfigPath"
    }
    exit 0
}

# Append the snippet
$snippet = Get-Content $SnippetPath -Raw -Encoding UTF8
$newContent = if ($existing) {
    $existing.TrimEnd("`r", "`n") + "`r`n`r`n" + $snippet
} else {
    $snippet
}

if ($DryRun) {
    Write-Host "DRY RUN -- would write to ${ConfigPath}:"
    Write-Host $newContent
} else {
    New-Item -ItemType Directory -Path (Split-Path -Parent $ConfigPath) -Force | Out-Null
    Set-Content -Path $ConfigPath -Value $newContent -Encoding UTF8
    Write-Host "Wrote $ConfigPath"
    Write-Host "Restart Codex CLI for hooks to take effect."
}
