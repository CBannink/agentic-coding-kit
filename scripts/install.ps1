#!/usr/bin/env pwsh
# install.ps1 -- Caspar Bannink Agentic Coding Kit installer.
#
# Quick start (most users):
#   pwsh ./install.ps1 -For claude               # one CLI, device-wide
#   pwsh ./install.ps1 -For "claude,opencode"    # multiple
#   pwsh ./install.ps1 -For all                  # everything
#   pwsh ./install.ps1 -Auto                     # detect CLIs on PATH and install for those
#
# Per-repo (advanced):
#   pwsh ./install.ps1 -TargetRepo C:\path\to\repo -InstallRepoTemplate -InstallAdapter claude
#   pwsh ./install.ps1 -TargetRepo C:\path\to\repo -InstallRepoTemplate -InstallAdapter all
#
# Upgrade (preserves customizations via backup):
#   pwsh ./install.ps1 -Upgrade -For claude
#
# Adapters: claude | codex | copilot | opencode | kilocode | generic | all
# `generic` writes a tool-neutral AGENTS.md (Aider, Cline, Cursor, etc. read it).
# `all` writes every adapter's files (they coexist; CLIs pick what they recognize).

param(
    [string]$HomeRoot = $HOME,
    [string]$TargetRepo = "",
    [switch]$InstallGlobal = $true,
    [switch]$InstallRepoTemplate,
    [string]$InstallAdapter = "",
    # The simple path: -For <cli-list> installs global assets + device-wide
    # config for the named CLIs. Same as -DeviceWide; new name is clearer.
    # Examples:
    #   -For claude               # one CLI
    #   -For "claude,opencode"    # multiple
    #   -For all                  # all 5 supported CLIs
    [string]$For = "",
    # Detect which CLIs are on PATH and install for those automatically.
    [switch]$Auto,
    # Legacy flag, kept for back-compat. Same behavior as -For.
    [string]$DeviceWide = "",
    [switch]$Upgrade,
    [switch]$Force
)

$ScriptRoot   = Split-Path -Parent $MyInvocation.MyCommand.Path
$RepoRoot     = Split-Path -Parent $ScriptRoot
$BundleGlobal = Join-Path $RepoRoot "bundle/global"
$BundleRepo   = Join-Path $RepoRoot "bundle/repo-template"
$AdaptersRoot = Join-Path $RepoRoot "bundle/adapters"

$AgentsRoot = Join-Path $HomeRoot ".agents"

# Pre-flight: validate the bundle. Refuses to install a broken kit.
$validator = Join-Path $ScriptRoot "validate-bundle.ps1"
if (Test-Path $validator) {
    Write-Host "Pre-flight: running validate-bundle.ps1..."
    & $validator
    if ($LASTEXITCODE -ne 0 -and -not $Force) {
        Write-Error "Bundle validation FAILED. Re-run with -Force to install anyway."
        exit 1
    }
    Write-Host ""
}

function Copy-Tree {
    param([string]$Source, [string]$Destination)
    if (-not (Test-Path $Source)) { return }
    New-Item -ItemType Directory -Path $Destination -Force | Out-Null
    Copy-Item -Recurse -Force (Join-Path $Source '*') $Destination
}

function Render-Template {
    param([string]$Source, [string]$Destination, [hashtable]$Vars)
    if (-not (Test-Path $Source)) { return }
    $content = Get-Content $Source -Raw
    foreach ($k in $Vars.Keys) {
        $content = $content.Replace($k, $Vars[$k])
    }
    New-Item -ItemType Directory -Path (Split-Path -Parent $Destination) -Force | Out-Null
    Set-Content -Path $Destination -Value $content -Encoding utf8
}

function Install-Adapter {
    param([string]$Name, [string]$TargetRepo)
    $src = Join-Path $AdaptersRoot $Name
    if (-not (Test-Path $src)) {
        Write-Host "  Adapter '$Name' not found at $src -- skipping"
        return
    }
    Copy-Tree -Source $src -Destination $TargetRepo
    Write-Host "  Installed '$Name' adapter into $TargetRepo"
}

# Copies slash command markdown files from an adapter's commands dir into the
# CLI's device-wide commands dir. Both Claude (~/.claude/commands/) and
# OpenCode (~/.config/opencode/commands/) auto-mount commands from these
# locations into every session in every repo.
function Install-DeviceWideCommands {
    param(
        [string]$SourceDir,        # bundle/adapters/<cli>/.../commands
        [string]$DestDir,          # ~/.claude/commands or ~/.config/opencode/commands
        [string]$Label
    )
    if (-not (Test-Path $SourceDir)) { return }
    New-Item -ItemType Directory -Path $DestDir -Force | Out-Null
    $count = 0
    foreach ($f in (Get-ChildItem -Path $SourceDir -Filter "*.md" -File)) {
        $dst = Join-Path $DestDir $f.Name
        if ((Test-Path $dst) -and (-not $Force)) {
            # Skip if user has a custom command at this name. Tell them.
            Write-Host "  $Label command: $($f.Name) already exists at $dst (skipped, pass -Force to overwrite)"
            continue
        }
        Copy-Item -Force $f.FullName $dst
        $count++
    }
    if ($count -gt 0) { Write-Host "  $Label commands: $count installed at $DestDir" }

    # Claude Code: additively merge SessionEnd hooks into ~/.claude/settings.json
    if ($Name -eq "claude-code") {
        $merger = Join-Path $AgentsRoot "tools/merge-claude-settings.ps1"
        $snippet = Join-Path $TargetRepo ".claude/settings.snippet.json"
        if ((Test-Path $merger) -and (Test-Path $snippet)) {
            Write-Host "  Wiring Claude Code SessionEnd hooks into ~/.claude/settings.json..."
            & pwsh -NoProfile -File $merger -SnippetPath $snippet
        }
    }
}

# ── Upgrade mode: backup before overwriting ───────────────────────────────────
# Preserves any user customizations of skill files, memory files, etc., by
# moving the existing ~/.agents to ~/.agents.bak.<timestamp> before installing.
# User can hand-merge customizations from the backup after upgrade.
if ($Upgrade -and (Test-Path $AgentsRoot)) {
    $backup = "$AgentsRoot.bak.$(Get-Date -Format 'yyyyMMdd-HHmmss')"
    Write-Host "Upgrade mode: backing up $AgentsRoot -> $backup"
    Move-Item -Force $AgentsRoot $backup
    Write-Host "  After upgrade, hand-merge any customized files from the backup."
    Write-Host ""
}

# ── Global install ─────────────────────────────────────────────────────────────
# Everything kit-related lives under ~/.agents/. Codex CLI users who want their
# own ~/.codex/ config can set it up separately -- it's not the kit's concern.
if ($InstallGlobal) {
    Copy-Tree -Source (Join-Path $BundleGlobal ".agents") -Destination $AgentsRoot

    # Render skill-memory-index.json from template with absolute paths
    $tmpl = Join-Path $AgentsRoot "context/skill-memory-index.json.tmpl"
    $out  = Join-Path $AgentsRoot "context/skill-memory-index.json"
    if (Test-Path $tmpl) {
        $agentsRootAbs = (Resolve-Path $AgentsRoot).Path -replace '\\', '/'
        Render-Template -Source $tmpl -Destination $out -Vars @{
            "__AGENTS_ROOT__" = $agentsRootAbs
        }
        Remove-Item -Force $tmpl
        Write-Host "  Rendered skill-memory-index.json with AGENTS_ROOT=$agentsRootAbs"
    }

    Write-Host "Installed global assets into $HomeRoot"
}

# ── Repo template install ─────────────────────────────────────────────────────
if ($TargetRepo -and $InstallRepoTemplate) {
    Copy-Tree -Source $BundleRepo -Destination $TargetRepo
    Write-Host "Installed repo template into $TargetRepo"
}

# ── Adapter install ───────────────────────────────────────────────────────────
if ($TargetRepo -and $InstallAdapter) {
    $adapters = if ($InstallAdapter -eq "all") {
        @("claude-code", "codex-cli", "copilot-cli", "opencode", "kilocode", "generic")
    } else {
        @($InstallAdapter)
    }

    foreach ($a in $adapters) {
        $resolved = switch ($a) {
            "claude"   { "claude-code" }
            "codex"    { "codex-cli" }
            "copilot"  { "copilot-cli" }
            "opencode" { "opencode" }
            "kilocode" { "kilocode" }
            "kilo"     { "kilocode" }
            default    { $a }
        }
        Install-Adapter -Name $resolved -TargetRepo $TargetRepo
    }
}

if (-not $TargetRepo -and -not $DeviceWide -and -not $For -and -not $Auto) {
    Write-Host ""
    Write-Host "Global assets installed at $AgentsRoot."
    Write-Host ""
    Write-Host "To wire the kit into a CLI on this device, re-run with -For or -Auto:"
    Write-Host "  pwsh ./install.ps1 -For claude                     # one CLI"
    Write-Host "  pwsh ./install.ps1 -For 'claude,opencode'           # multiple"
    Write-Host "  pwsh ./install.ps1 -For all                        # all five"
    Write-Host "  pwsh ./install.ps1 -Auto                            # detect CLIs on PATH"
    Write-Host ""
    Write-Host "Or bootstrap a single repo:"
    Write-Host "  pwsh ./install.ps1 -TargetRepo <path> -InstallRepoTemplate -InstallAdapter all"
}

# ── Resolve which CLIs to install for (-For, -Auto, -DeviceWide all converge) ─
# -For is the new canonical flag. -DeviceWide is kept as an alias.
# -Auto detects which CLIs are on PATH and installs for those.
$resolvedFor = ""
if ($For)        { $resolvedFor = $For }
elseif ($DeviceWide) { $resolvedFor = $DeviceWide }
elseif ($Auto) {
    $detected = @()
    if (Get-Command claude -ErrorAction SilentlyContinue)   { $detected += "claude" }
    if (Get-Command opencode -ErrorAction SilentlyContinue) { $detected += "opencode" }
    if (Get-Command codex -ErrorAction SilentlyContinue)    { $detected += "codex" }
    if (Get-Command gh -ErrorAction SilentlyContinue) {
        # Copilot CLI is `gh copilot ...`. If gh is present, offer copilot adapter.
        $detected += "copilot"
    }
    if ($detected.Count -gt 0) {
        $resolvedFor = $detected -join ","
        Write-Host ""
        Write-Host "Auto-detected CLIs on PATH: $($detected -join ', ')"
        Write-Host "Installing for those. Pass -For <list> to override."
    } else {
        Write-Host ""
        Write-Host "Auto-detect found no supported CLI on PATH."
        Write-Host "Pass -For <claude|codex|copilot|opencode|kilocode|all> explicitly."
    }
}

# ── Device-wide install ──────────────────────────────────────────────────────
# Writes companion files (~/.claude/agentic-kit.md etc.) so the kit applies to
# ANY repo on this device, not just one. Appends a single include marker to
# existing CLAUDE.md / AGENTS.md / prompt.md so user instructions are preserved.
if ($resolvedFor) {
    $DeviceWide = $resolvedFor
    $sharedBody = Join-Path $AdaptersRoot "_shared/AGENT-INSTRUCTIONS.md"
    if (-not (Test-Path $sharedBody)) {
        Write-Error "Shared instructions not found at $sharedBody"
        exit 1
    }
    $kitContent = Get-Content $sharedBody -Raw -Encoding UTF8

    function Install-DeviceWideCompanion {
        param(
            [string]$CompanionPath,    # where to write the kit body
            [string]$ExistingPath,     # the user's existing CLI config file (may not exist)
            [string]$Label             # human label for output
        )
        # Write the companion file (always overwrite -- it's the kit's content)
        New-Item -ItemType Directory -Path (Split-Path -Parent $CompanionPath) -Force | Out-Null
        Set-Content -Path $CompanionPath -Value $kitContent -Encoding UTF8
        Write-Host "  $Label companion: $CompanionPath"

        # Append include marker to existing config (if it exists, preserve content)
        $marker = "<!-- agentic-kit:include -->"
        $endMarker = "<!-- /agentic-kit:include -->"
        $includeBlock = @"

$marker
The Caspar Bannink Agentic Coding Kit is installed. Read these rules before
acting on /plan, /build, /review, /redesign, /security-review, or any
agentic workflow:
$CompanionPath
$endMarker
"@

        if (Test-Path $ExistingPath) {
            $existing = Get-Content $ExistingPath -Raw -Encoding UTF8
            if ($existing -match [regex]::Escape($marker)) {
                Write-Host "  $Label include: already present (skipped)"
            } else {
                $backup = "$ExistingPath.before-agentic-kit-$(Get-Date -Format 'yyyyMMdd-HHmmss')"
                Copy-Item -Force $ExistingPath $backup
                Add-Content -Path $ExistingPath -Value $includeBlock -Encoding UTF8
                Write-Host "  $Label include: appended to $ExistingPath (backup: $backup)"
            }
        } else {
            New-Item -ItemType Directory -Path (Split-Path -Parent $ExistingPath) -Force | Out-Null
            Set-Content -Path $ExistingPath -Value $includeBlock.TrimStart() -Encoding UTF8
            Write-Host "  $Label include: created $ExistingPath"
        }
    }

    # `all` covers every CLI that has a meaningful device-wide install location,
    # plus the generic AGENTS.md for any tool that reads the canonical home file.
    # copilot and kilocode have no device-wide config (Copilot reads
    # `.github/copilot-instructions.md` from the workspace; Kilo Code reads
    # `.kilocode/rules/*.md` from the workspace) -- they short-circuit with a
    # message pointing at -TargetRepo.
    $targets = if ($DeviceWide -eq "all") {
        @("claude", "codex", "opencode", "generic")
    } else {
        # Allow comma-separated lists too: "claude,opencode"
        @(($DeviceWide -split '[,;]' | ForEach-Object { $_.Trim() } | Where-Object { $_ }))
    }

    Write-Host ""
    Write-Host "Device-wide install ($($targets -join ', ')):"

    foreach ($t in $targets) {
        switch ($t) {
            "claude" {
                Install-DeviceWideCompanion `
                    -CompanionPath (Join-Path $HomeRoot ".claude/agentic-kit.md") `
                    -ExistingPath  (Join-Path $HomeRoot ".claude/CLAUDE.md") `
                    -Label "Claude Code"

                # Install slash commands -- ~/.claude/commands/<name>.md is
                # auto-mounted by Claude Code in every session.
                Install-DeviceWideCommands `
                    -SourceDir (Join-Path $AdaptersRoot "claude-code/.claude/commands") `
                    -DestDir   (Join-Path $HomeRoot ".claude/commands") `
                    -Label     "Claude Code"

                # Wire SessionEnd hooks via the merger (honor HomeRoot)
                $merger  = Join-Path $AgentsRoot "tools/merge-claude-settings.ps1"
                $snippet = Join-Path $AdaptersRoot "claude-code/.claude/settings.snippet.json"
                $settingsPath = Join-Path $HomeRoot ".claude/settings.json"
                if ((Test-Path $merger) -and (Test-Path $snippet)) {
                    Write-Host "  Claude Code hooks: wiring..."
                    $shell = if (Get-Command pwsh -ErrorAction SilentlyContinue) { "pwsh" } else { "powershell" }
                    & $shell -NoProfile -File $merger -SnippetPath $snippet -SettingsPath $settingsPath
                }
            }
            "codex" {
                Install-DeviceWideCompanion `
                    -CompanionPath (Join-Path $HomeRoot ".codex/agentic-kit.md") `
                    -ExistingPath  (Join-Path $HomeRoot ".codex/AGENTS.md") `
                    -Label "Codex CLI"
            }
            "opencode" {
                Install-DeviceWideCompanion `
                    -CompanionPath (Join-Path $HomeRoot ".config/opencode/agentic-kit.md") `
                    -ExistingPath  (Join-Path $HomeRoot ".config/opencode/prompt.md") `
                    -Label "OpenCode"

                # Install slash commands -- ~/.config/opencode/commands/<name>.md
                # is auto-mounted by OpenCode in every session.
                Install-DeviceWideCommands `
                    -SourceDir (Join-Path $AdaptersRoot "opencode/.config/opencode/commands") `
                    -DestDir   (Join-Path $HomeRoot ".config/opencode/commands") `
                    -Label     "OpenCode"

                # Drop the lifecycle plugin into the user-level plugins dir
                $pluginSrc = Join-Path $AdaptersRoot "opencode/.opencode/plugins/agentic-kit.ts"
                $pluginDst = Join-Path $HomeRoot ".config/opencode/plugins/agentic-kit.ts"
                if (Test-Path $pluginSrc) {
                    New-Item -ItemType Directory -Path (Split-Path -Parent $pluginDst) -Force | Out-Null
                    Copy-Item -Force $pluginSrc $pluginDst
                    Write-Host "  OpenCode plugin: $pluginDst"
                }
            }
            "generic" {
                # Tool-neutral AGENTS.md. Aider, Cline, Cursor (via .cursorrules
                # link), and most "agentic" CLIs check this canonical home file.
                Install-DeviceWideCompanion `
                    -CompanionPath (Join-Path $HomeRoot ".agentic-kit/AGENTS.md") `
                    -ExistingPath  (Join-Path $HomeRoot "AGENTS.md") `
                    -Label "Generic AGENTS.md"
            }
            "copilot" {
                Write-Host "  GitHub Copilot has no device-wide config -- it reads"
                Write-Host "  .github/copilot-instructions.md from each workspace."
                Write-Host "  Per-repo install:"
                Write-Host "    pwsh ./install.ps1 -TargetRepo <path> -InstallAdapter copilot"
            }
            "kilocode" {
                Write-Host "  Kilo Code has no device-wide config -- it reads"
                Write-Host "  .kilocode/rules/*.md from each workspace."
                Write-Host "  Per-repo install:"
                Write-Host "    pwsh ./install.ps1 -TargetRepo <path> -InstallAdapter kilocode"
            }
            "kilo" {
                Write-Host "  Kilo Code has no device-wide config -- it reads"
                Write-Host "  .kilocode/rules/*.md from each workspace."
                Write-Host "  Per-repo install:"
                Write-Host "    pwsh ./install.ps1 -TargetRepo <path> -InstallAdapter kilocode"
            }
            default {
                Write-Host "  Unknown target: $t (use claude, codex, opencode, copilot, kilocode, generic, or all)"
            }
        }
    }
    Write-Host ""
    Write-Host "Device-wide install complete."
    Write-Host "Restart your CLI for changes to take effect."
}
