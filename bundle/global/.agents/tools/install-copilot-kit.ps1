# install-copilot-kit.ps1
# Installs the kit into GitHub Copilot CLI.
#
# Copilot CLI reads user-global instructions from $HOME/.copilot (override
# with COPILOT_HOME env var). Per official docs:
#   ~/.copilot/copilot-instructions.md            -- main personal instructions
#   ~/.copilot/instructions/*.instructions.md     -- additional topic-scoped
#
# Copilot CLI has no native subagent / hook system, so this installer only
# syncs the canonical block via <!-- agentic-kit:begin/end --> markers and
# optionally drops the kit's MODEL-ROUTING guidance as an instructions file.
#
# Idempotent. Detects existing footprint + prompts before overwrite.

[CmdletBinding()]
param([switch]$DryRun, [switch]$Force, [switch]$NoBackup)
$ErrorActionPreference = 'Stop'

$AgentsRoot  = Join-Path $HOME '.agents'
$RepoRoot    = Join-Path $HOME 'Downloads\caspar_bannink_agentic_coding\caspar_bannink_agentic_coding'
$CopilotRoot = if ($env:COPILOT_HOME) { $env:COPILOT_HOME } else { Join-Path $HOME '.copilot' }
$Stamp = Get-Date -Format 'yyyyMMdd-HHmmss'

if (-not (Test-Path $CopilotRoot)) { New-Item -ItemType Directory -Path $CopilotRoot -Force | Out-Null }

function Say([string]$msg, [string]$color='White') { Write-Host $msg -ForegroundColor $color }
function Skip([string]$msg) { Say "  SKIP  $msg" 'DarkGray' }
function Do-It([string]$msg) { Say "  DO    $msg" 'Green' }
function Warn([string]$msg) { Say "  WARN  $msg" 'Yellow' }

$Utf8NoBom = New-Object System.Text.UTF8Encoding($false)
function Write-NoBom([string]$path, [string]$content) {
    [System.IO.File]::WriteAllText($path, $content, $Utf8NoBom)
}

# ---------- detect existing install ----------
$instructionsFile = Join-Path $CopilotRoot 'copilot-instructions.md'
$instructionsDir  = Join-Path $CopilotRoot 'instructions'

$Fingerprints = @($instructionsFile, $instructionsDir) | Where-Object { Test-Path $_ }
if ($Fingerprints.Count -gt 0) {
    Say "`nExisting Copilot kit footprint detected in $CopilotRoot." 'Yellow'
    foreach ($p in $Fingerprints) { Say "    - $p" 'DarkYellow' }
    Say "  Continuing will OVERWRITE the canonical block in copilot-instructions.md." 'Yellow'

    if ($DryRun)    { Say "  (dry run -- skipping prompt)" 'DarkGray' }
    elseif ($Force) { Say "  -Force given -- proceeding without prompt." 'DarkGray' }
    else {
        $resp = Read-Host "Continue and overwrite? [y/N]"
        if ($resp -notmatch '^(y|yes)$') { Say "Aborted." 'Red'; exit 1 }
    }
}

# ---------- 1. copilot-instructions.md (canonical block via markers) ----------
Say "`n[1/2] copilot-instructions.md (sync canonical block)" 'Cyan'
$canonical = Get-Content -Raw -Encoding utf8 -LiteralPath (Join-Path $AgentsRoot 'global-instructions.md')

if (-not (Test-Path $instructionsFile)) {
    if ($DryRun) { Skip "would create $instructionsFile" }
    else { Write-NoBom $instructionsFile $canonical; Do-It "created $instructionsFile" }
} else {
    $current = Get-Content -Raw -Encoding utf8 -LiteralPath $instructionsFile
    $beginMarker = '<!-- agentic-kit:begin -->'
    $endMarker   = '<!-- agentic-kit:end -->'

    if ($current -match [regex]::Escape($beginMarker)) {
        $pattern = "(?s)" + [regex]::Escape($beginMarker) + ".*?" + [regex]::Escape($endMarker)
        $updated = [regex]::Replace($current, $pattern, $canonical.TrimEnd())
        if ($DryRun) { Skip "would replace canonical block in $instructionsFile" }
        else { Write-NoBom $instructionsFile $updated; Do-It "replaced canonical block in $instructionsFile" }
    } else {
        $updated = $canonical.TrimEnd() + "`r`n`r`n" + $current
        if ($DryRun) { Skip "would prepend canonical block to $instructionsFile" }
        else { Write-NoBom $instructionsFile $updated; Do-It "prepended canonical block (existing host content preserved below)" }
    }
}

# ---------- 2. instructions/ topic files (optional MODEL-ROUTING.md) ----------
Say "`n[2/2] instructions/ topic files" 'Cyan'
$modelRoutingSrc = Join-Path $RepoRoot 'bundle\adapters\copilot-cli\MODEL-ROUTING.md'
if (Test-Path $modelRoutingSrc) {
    if (-not $DryRun) { New-Item -ItemType Directory -Path $instructionsDir -Force | Out-Null }
    $modelRoutingDst = Join-Path $instructionsDir 'model-routing.instructions.md'
    if ($DryRun) { Skip "would copy MODEL-ROUTING.md -> $modelRoutingDst" }
    else { Copy-Item -LiteralPath $modelRoutingSrc -Destination $modelRoutingDst -Force; Do-It "$modelRoutingDst" }
} else {
    Skip "no bundle/adapters/copilot-cli/MODEL-ROUTING.md found at $modelRoutingSrc -- skipping topic files"
}

# ---------- verify ----------
Say "`nVerify" 'Cyan'
if ($DryRun) { Say "  (dry run)" 'DarkGray' }
else {
    Say "  -> Run 'gh copilot suggest' or 'gh copilot explain' inside a repo and verify the canonical kit rules influence behavior." 'DarkGray'
    Say "  -> Override location: set COPILOT_HOME=<path> before running this installer." 'DarkGray'
}

Say "`nDone." 'Green'
