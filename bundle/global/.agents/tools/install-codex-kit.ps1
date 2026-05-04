# install-codex-kit.ps1
# Installs the Caspar Bannink Agentic Coding Kit into OpenAI's Codex CLI.
# Mirrors the Gemini installer: agents (.md -> .toml conversion!), AGENTS.md
# (canonical block synced via agentic-kit:begin/end markers), settings.
#
# Codex requires agents in TOML format under ~/.codex/agents/ with fields:
#   name, description, developer_instructions (body)
#
# Idempotent. Detects existing kit install + prompts before overwrite.
#
# Usage:
#   pwsh ~/.agents/tools/install-codex-kit.ps1
#   pwsh ~/.agents/tools/install-codex-kit.ps1 -DryRun
#   pwsh ~/.agents/tools/install-codex-kit.ps1 -Force

[CmdletBinding()]
param(
    [switch]$DryRun,
    [switch]$Force,
    [switch]$NoBackup
)

$ErrorActionPreference = 'Stop'

$ClaudeRoot = Join-Path $HOME ".claude"
$CodexRoot  = Join-Path $HOME ".codex"
$AgentsRoot = Join-Path $HOME ".agents"
$Stamp = Get-Date -Format 'yyyyMMdd-HHmmss'

if (-not (Test-Path $ClaudeRoot)) { throw "No ~/.claude -- nothing to port from." }
if (-not (Test-Path $CodexRoot))  { New-Item -ItemType Directory -Path $CodexRoot | Out-Null }

function Say([string]$msg, [string]$color='White') { Write-Host $msg -ForegroundColor $color }
function Skip([string]$msg) { Say "  SKIP  $msg" 'DarkGray' }
function Do-It([string]$msg) { Say "  DO    $msg" 'Green' }
function Warn([string]$msg) { Say "  WARN  $msg" 'Yellow' }

$Utf8NoBom = New-Object System.Text.UTF8Encoding($false)
function Write-NoBom([string]$path, [string]$content) {
    [System.IO.File]::WriteAllText($path, $content, $Utf8NoBom)
}

# ---------- detect existing kit install ----------
$Fingerprints = @(
    Join-Path $CodexRoot 'agents'
    Join-Path $CodexRoot 'agentic-kit.md'
)
$existingKit = @($Fingerprints | Where-Object { Test-Path $_ })
$staleBackups = @(Get-ChildItem -LiteralPath $CodexRoot -Filter '*.before-codex-kit-*' -Force -ErrorAction SilentlyContinue) +
                @(Get-ChildItem -LiteralPath $CodexRoot -Filter '*.before-agentic-kit-*' -Force -ErrorAction SilentlyContinue) +
                @(Get-ChildItem -LiteralPath $CodexRoot -Filter '*.before-inline-rules-*' -Force -ErrorAction SilentlyContinue)

if ($existingKit.Count -gt 0 -or $staleBackups.Count -gt 0) {
    Say "`nExisting Codex kit footprint detected in $CodexRoot." 'Yellow'
    if ($existingKit.Count -gt 0) {
        Say "  Live kit paths:" 'Yellow'
        foreach ($p in $existingKit) { Say "    - $p" 'DarkYellow' }
    }
    if ($staleBackups.Count -gt 0) {
        Say "  Stale backups ($($staleBackups.Count)):" 'Yellow'
        foreach ($b in $staleBackups | Select-Object -First 6) { Say "    - $($b.Name)" 'DarkGray' }
        if ($staleBackups.Count -gt 6) { Say "    ... and $($staleBackups.Count - 6) more" 'DarkGray' }
    }
    Say "  Continuing will OVERWRITE the live kit paths and DELETE stale backups." 'Yellow'

    if ($DryRun)      { Say "  (dry run -- skipping prompt)" 'DarkGray' }
    elseif ($Force)   { Say "  -Force given -- proceeding without prompt." 'DarkGray' }
    else {
        $resp = Read-Host "Continue and overwrite? [y/N]"
        if ($resp -notmatch '^(y|yes)$') { Say "Aborted." 'Red'; exit 1 }
    }

    if (-not $DryRun -and $staleBackups.Count -gt 0) {
        foreach ($b in $staleBackups) {
            try { Remove-Item -LiteralPath $b.FullName -Recurse -Force -ErrorAction Stop } catch { Warn "could not remove $($b.FullName): $_" }
        }
        Do-It "removed $($staleBackups.Count) stale backup entries"
    }
}

function Backup-Or-Remove([string]$path) {
    if (-not (Test-Path $path)) { return }
    if ($NoBackup -or $Force) {
        if ($DryRun) { Skip "would remove $path (no backup)" }
        else { Remove-Item -LiteralPath $path -Recurse -Force; Do-It "removed $path (no backup)" }
        return
    }
    $bk = "$path.before-codex-kit-$Stamp"
    if ($DryRun) { Skip "would back up $path -> $bk" }
    else { Move-Item -LiteralPath $path -Destination $bk -Force; Do-It "backed up $path -> $bk" }
}

# ---------- 1. AGENTS.md (canonical block via markers) ----------
Say "`n[1/4] AGENTS.md (sync canonical block)" 'Cyan'
$agentsMdPath = Join-Path $CodexRoot 'AGENTS.md'
$canonical = Get-Content -Raw -Encoding utf8 -LiteralPath (Join-Path $AgentsRoot 'global-instructions.md')

if (-not (Test-Path $agentsMdPath)) {
    if ($DryRun) { Skip "would create $agentsMdPath with canonical block" }
    else { Write-NoBom $agentsMdPath $canonical; Do-It "created $agentsMdPath" }
} else {
    $current = Get-Content -Raw -Encoding utf8 -LiteralPath $agentsMdPath
    $beginMarker = '<!-- agentic-kit:begin -->'
    $endMarker   = '<!-- agentic-kit:end -->'

    if ($current -match [regex]::Escape($beginMarker)) {
        # Replace existing block in-place
        $pattern = "(?s)" + [regex]::Escape($beginMarker) + ".*?" + [regex]::Escape($endMarker)
        $updated = [regex]::Replace($current, $pattern, $canonical.TrimEnd())
        if ($DryRun) { Skip "would replace canonical block in $agentsMdPath" }
        else { Write-NoBom $agentsMdPath $updated; Do-It "replaced canonical block in $agentsMdPath" }
    } else {
        # Prepend canonical block at top
        $updated = $canonical.TrimEnd() + "`r`n`r`n" + $current
        if ($DryRun) { Skip "would prepend canonical block to $agentsMdPath" }
        else { Write-NoBom $agentsMdPath $updated; Do-It "prepended canonical block to $agentsMdPath" }
    }
}

# Copy long-form reference
$kitRefSrc = Join-Path $ClaudeRoot 'agentic-kit.md'
$kitRefDst = Join-Path $CodexRoot 'agentic-kit.md'
if (Test-Path $kitRefSrc) {
    if ($DryRun) { Skip "would copy agentic-kit.md" }
    else { Copy-Item -LiteralPath $kitRefSrc -Destination $kitRefDst -Force; Do-It "copied agentic-kit.md" }
}

# ---------- 2. agents (.md -> .toml conversion) ----------
Say "`n[2/4] Agents (convert .md -> .toml for Codex)" 'Cyan'
$claudeAgents = Join-Path $ClaudeRoot 'agents'
$codexAgents  = Join-Path $CodexRoot  'agents'

if (Test-Path $claudeAgents) {
    Backup-Or-Remove $codexAgents
    if (-not $DryRun) { New-Item -ItemType Directory -Path $codexAgents | Out-Null }

    Get-ChildItem -LiteralPath $claudeAgents -Filter *.md -File | ForEach-Object {
        $raw = Get-Content -LiteralPath $_.FullName -Raw

        # Parse YAML frontmatter (simple: between first --- and second ---)
        $name = ''
        $description = ''
        $body = $raw

        if ($raw -match "(?s)^---\s*\r?\n(.*?)\r?\n---\s*\r?\n(.*)$") {
            $fm   = $matches[1]
            $body = $matches[2]
            if ($fm -match "(?m)^name:\s*(.+)$")        { $name = $matches[1].Trim() -replace '^["'']|["'']$','' }
            if ($fm -match "(?ms)^description:\s*(.+?)(?=^\w|\z)") {
                $description = $matches[1].Trim() -replace '^["'']|["'']$',''
            }
        }

        if (-not $name) { $name = [System.IO.Path]::GetFileNameWithoutExtension($_.Name) }
        if (-not $description) { $description = "$name agent (auto-generated)" }

        # TOML escape: backslash + double-quote in the body
        $bodyEscaped = $body.Trim() -replace '"""', '""\"'
        $descEscaped = $description -replace '"', '\"'

        $toml = @"
# Auto-generated from $($_.Name) by install-codex-kit.ps1
# Edit ~/.claude/agents/$($_.Name) and re-run the installer.

name = "$name"
description = "$descEscaped"

developer_instructions = """
$bodyEscaped
"""
"@
        $outPath = Join-Path $codexAgents "$name.toml"
        if ($DryRun) { Skip "would write $outPath" }
        else { Write-NoBom $outPath $toml; Do-It "/$name (TOML)" }
    }
} else { Warn "no ~/.claude/agents found" }

# ---------- 3. config.toml (ensure multi_agent + agents settings) ----------
Say "`n[3/4] config.toml (multi_agent settings)" 'Cyan'
$cfgPath = Join-Path $CodexRoot 'config.toml'
if (Test-Path $cfgPath) {
    $cfg = Get-Content -Raw -LiteralPath $cfgPath
    $needsUpdate = $false

    if ($cfg -notmatch '(?m)^\[features\]') {
        $cfg += "`r`n[features]`r`nmulti_agent = true`r`n"
        $needsUpdate = $true
    } elseif ($cfg -notmatch '(?m)^multi_agent\s*=') {
        $cfg = $cfg -replace '(?m)^\[features\]', "[features]`r`nmulti_agent = true"
        $needsUpdate = $true
    }

    if ($cfg -notmatch '(?m)^\[agents\]') {
        $cfg += "`r`n[agents]`r`nmax_threads = 6`r`nmax_depth = 1`r`n"
        $needsUpdate = $true
    }

    if ($needsUpdate) {
        if ($DryRun) { Skip "would update config.toml ([features].multi_agent + [agents] section)" }
        else { Write-NoBom $cfgPath $cfg; Do-It "updated config.toml" }
    } else {
        Skip "config.toml already has multi_agent and [agents] section"
    }
} else {
    $newCfg = @"
[features]
multi_agent = true

[agents]
max_threads = 6
max_depth = 1
"@
    if ($DryRun) { Skip "would create config.toml" }
    else { Write-NoBom $cfgPath $newCfg; Do-It "created config.toml" }
}

# ---------- 4. verify ----------
Say "`n[4/4] Verify" 'Cyan'
if ($DryRun) {
    Say "  (dry run -- skipping live checks)" 'DarkGray'
} else {
    $agentCount = @(Get-ChildItem -LiteralPath $codexAgents -Filter *.toml -ErrorAction SilentlyContinue).Count
    Say "  -> $agentCount Codex agents installed under $codexAgents" 'DarkGray'
    Say "  -> Run 'codex' and ask it to spawn one of: $((Get-ChildItem $codexAgents -Filter *.toml | Select-Object -First 3 | ForEach-Object { [System.IO.Path]::GetFileNameWithoutExtension($_.Name) }) -join ', ')" 'DarkGray'
}

Say "`nDone." 'Green'
