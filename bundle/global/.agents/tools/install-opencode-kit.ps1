# install-opencode-kit.ps1
# Installs the kit into OpenCode (~/.config/opencode/).
# - Syncs agent .md files (frontmatter normalized for OpenCode: description unquoted, no tools field)
# - Syncs the canonical block into prompt.md using <!-- agentic-kit:begin/end --> markers
#
# Idempotent. Detects existing kit install + prompts before overwrite.

[CmdletBinding()]
param([switch]$DryRun, [switch]$Force, [switch]$NoBackup)
$ErrorActionPreference = 'Stop'

$ClaudeRoot   = Join-Path $HOME ".claude"
$AgentsRoot   = Join-Path $HOME ".agents"
$OpenCodeRoot = Join-Path $HOME ".config\opencode"
$Stamp = Get-Date -Format 'yyyyMMdd-HHmmss'

if (-not (Test-Path $ClaudeRoot))   { throw "No ~/.claude -- nothing to port from." }
if (-not (Test-Path $OpenCodeRoot)) { New-Item -ItemType Directory -Path $OpenCodeRoot -Force | Out-Null }

function Say([string]$msg, [string]$color='White') { Write-Host $msg -ForegroundColor $color }
function Skip([string]$msg) { Say "  SKIP  $msg" 'DarkGray' }
function Do-It([string]$msg) { Say "  DO    $msg" 'Green' }
function Warn([string]$msg) { Say "  WARN  $msg" 'Yellow' }

$Utf8NoBom = New-Object System.Text.UTF8Encoding($false)
function Write-NoBom([string]$path, [string]$content) {
    [System.IO.File]::WriteAllText($path, $content, $Utf8NoBom)
}

# ---------- detect existing install ----------
$Fingerprints = @(
    Join-Path $OpenCodeRoot 'agents'
    Join-Path $OpenCodeRoot 'prompt.md'
)
$existing = @($Fingerprints | Where-Object { Test-Path $_ })
$staleBackups = @(Get-ChildItem -LiteralPath $OpenCodeRoot -Filter '*.before-*-kit-*' -Force -ErrorAction SilentlyContinue) +
                @(Get-ChildItem -LiteralPath $OpenCodeRoot -Filter '*.before-inline-rules-*' -Force -ErrorAction SilentlyContinue)

if ($existing.Count -gt 0 -or $staleBackups.Count -gt 0) {
    Say "`nExisting OpenCode kit footprint detected in $OpenCodeRoot." 'Yellow'
    foreach ($p in $existing) { Say "    - $p" 'DarkYellow' }
    if ($staleBackups.Count -gt 0) { Say "  Stale backups: $($staleBackups.Count)" 'Yellow' }
    Say "  Continuing will OVERWRITE prompt.md (canonical block only) and refresh agents/. Stale backups deleted." 'Yellow'

    if ($DryRun)    { Say "  (dry run -- skipping prompt)" 'DarkGray' }
    elseif ($Force) { Say "  -Force given -- proceeding without prompt." 'DarkGray' }
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

# ---------- 1. prompt.md (canonical block via markers) ----------
Say "`n[1/3] prompt.md (sync canonical block)" 'Cyan'
$promptPath = Join-Path $OpenCodeRoot 'prompt.md'
$canonical = Get-Content -Raw -Encoding utf8 -LiteralPath (Join-Path $AgentsRoot 'global-instructions.md')

if (-not (Test-Path $promptPath)) {
    if ($DryRun) { Skip "would create $promptPath" }
    else { Write-NoBom $promptPath $canonical; Do-It "created $promptPath" }
} else {
    $current = Get-Content -Raw -Encoding utf8 -LiteralPath $promptPath
    $beginMarker = '<!-- agentic-kit:begin -->'
    $endMarker   = '<!-- agentic-kit:end -->'
    $legacyMarker = '<!-- agentic-kit:include -->'

    if ($current -match [regex]::Escape($beginMarker)) {
        $pattern = "(?s)" + [regex]::Escape($beginMarker) + ".*?" + [regex]::Escape($endMarker)
        $updated = [regex]::Replace($current, $pattern, $canonical.TrimEnd())
        if ($DryRun) { Skip "would replace canonical block in $promptPath" }
        else { Write-NoBom $promptPath $updated; Do-It "replaced canonical block in $promptPath" }
    } elseif ($current -match [regex]::Escape($legacyMarker)) {
        # Replace from legacy marker to end-of-file with the new canonical block
        $idx = $current.IndexOf($legacyMarker)
        $preamble = $current.Substring(0, $idx).TrimEnd()
        $updated = $preamble + "`r`n`r`n" + $canonical.TrimEnd() + "`r`n"
        if ($DryRun) { Skip "would migrate legacy <!-- agentic-kit:include --> block in $promptPath" }
        else { Write-NoBom $promptPath $updated; Do-It "migrated legacy include marker -> begin/end block" }
    } else {
        # Prepend canonical at top
        $updated = $canonical.TrimEnd() + "`r`n`r`n" + $current
        if ($DryRun) { Skip "would prepend canonical block to $promptPath" }
        else { Write-NoBom $promptPath $updated; Do-It "prepended canonical block to $promptPath" }
    }
}

# ---------- 2. agents (sync md, normalize frontmatter for OpenCode) ----------
Say "`n[2/3] Agents (sync .md, OpenCode-normalized frontmatter)" 'Cyan'
$claudeAgents   = Join-Path $ClaudeRoot   'agents'
$opencodeAgents = Join-Path $OpenCodeRoot 'agents'

if (Test-Path $claudeAgents) {
    if (Test-Path $opencodeAgents) {
        if ($NoBackup -or $Force) {
            if (-not $DryRun) { Remove-Item -LiteralPath $opencodeAgents -Recurse -Force; Do-It "cleared existing $opencodeAgents" }
        } else {
            $bk = "$opencodeAgents.before-opencode-kit-$Stamp"
            if (-not $DryRun) { Move-Item -LiteralPath $opencodeAgents -Destination $bk -Force; Do-It "backed up agents -> $bk" }
        }
    }
    if (-not $DryRun) { New-Item -ItemType Directory -Path $opencodeAgents -Force | Out-Null }

    Get-ChildItem -LiteralPath $claudeAgents -Filter *.md -File | ForEach-Object {
        $raw = Get-Content -Raw -LiteralPath $_.FullName

        # Normalize frontmatter for OpenCode:
        # - strip surrounding quotes from description value
        # - drop tools: line (OpenCode uses permission globs in opencode.jsonc)
        if ($raw -match "(?s)^---\s*\r?\n(.*?)\r?\n---\s*\r?\n(.*)$") {
            $fm   = $matches[1]
            $body = $matches[2]
            $fmLines = $fm -split "\r?\n"
            $newFm = @()
            foreach ($line in $fmLines) {
                if ($line -match '^\s*tools\s*:') { continue }
                if ($line -match '^(\s*description\s*:\s*)"(.+)"\s*$') {
                    $newFm += "$($matches[1])$($matches[2])"
                } elseif ($line -match "^(\s*description\s*:\s*)'(.+)'\s*$") {
                    $newFm += "$($matches[1])$($matches[2])"
                } else {
                    $newFm += $line
                }
            }
            $normalized = "---`r`n" + ($newFm -join "`r`n").TrimEnd() + "`r`n---`r`n" + $body
        } else {
            $normalized = $raw
        }

        $outPath = Join-Path $opencodeAgents $_.Name
        if ($DryRun) { Skip "would write $outPath" }
        else { Write-NoBom $outPath $normalized; Do-It "/$([System.IO.Path]::GetFileNameWithoutExtension($_.Name))" }
    }
} else { Warn "no ~/.claude/agents found" }

# ---------- 3. verify ----------
Say "`n[3/3] Verify" 'Cyan'
if ($DryRun) {
    Say "  (dry run)" 'DarkGray'
} else {
    $count = @(Get-ChildItem -LiteralPath $opencodeAgents -Filter *.md -ErrorAction SilentlyContinue).Count
    Say "  -> $count OpenCode agents under $opencodeAgents" 'DarkGray'
    Say "  -> Run 'opencode' and try /agents to confirm they're loaded" 'DarkGray'
}

Say "`nDone." 'Green'
