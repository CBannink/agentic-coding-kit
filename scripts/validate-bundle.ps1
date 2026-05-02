#!/usr/bin/env pwsh
# validate-bundle.ps1 -- self-check the kit before shipping or installing.
#
# Catches the bug class we hit in development:
#   - em-dash bombs in PowerShell string literals
#   - hardcoded user paths that won't resolve on the install target
#   - tools documented in skills but missing from disk
#   - adapter dirs missing required files
#   - .ps1 files that don't even parse
#
# Run before every commit and at install time.
#
# Usage:
#   pwsh ./scripts/validate-bundle.ps1
#   pwsh ./scripts/validate-bundle.ps1 -Strict   # exit 1 on any warning
#
# Exit codes: 0 = clean, 1 = errors (or warnings under -Strict).

param(
    [switch]$Strict
)

$ScriptRoot = Split-Path -Parent $MyInvocation.MyCommand.Path
$RepoRoot   = Split-Path -Parent $ScriptRoot
$Bundle     = Join-Path $RepoRoot "bundle"
$ToolsDir   = Join-Path $Bundle "global/.agents/tools"

$errors   = [System.Collections.ArrayList]::new()
$warnings = [System.Collections.ArrayList]::new()

function Add-Error([string]$msg)   { [void]$errors.Add($msg);   Write-Host "[ERROR] $msg" -ForegroundColor Red }
function Add-Warn([string]$msg)    { [void]$warnings.Add($msg); Write-Host "[WARN]  $msg" -ForegroundColor Yellow }
function Add-Pass([string]$msg)    { Write-Host "[OK]    $msg" -ForegroundColor Green }

Write-Host ""
Write-Host "validate-bundle.ps1 -- checking $RepoRoot"
Write-Host "================================================================="
Write-Host ""

# --- Check 1: every .ps1 parses ----------------------------------------------
Write-Host "[1/5] PowerShell parse check"
$psFiles = Get-ChildItem -Path $Bundle -Recurse -Filter "*.ps1"
$parseFailures = 0
foreach ($f in $psFiles) {
    # Read explicitly as UTF-8 so PS5.1 doesn't misinterpret as cp1252.
    # The kit targets pwsh 7+ but the validator should work under either.
    $src = [System.IO.File]::ReadAllText($f.FullName, [System.Text.Encoding]::UTF8)
    $tokens = $null; $errs = $null
    [void][System.Management.Automation.Language.Parser]::ParseInput($src, $f.FullName, [ref]$tokens, [ref]$errs)
    if ($errs.Count -gt 0) {
        $parseFailures++
        Add-Error "Parse failed: $($f.FullName)"
        foreach ($e in $errs | Select-Object -First 3) {
            Write-Host "         line $($e.Extent.StartLineNumber): $($e.Message)"
        }
    }
}
if ($parseFailures -eq 0) { Add-Pass "$($psFiles.Count) .ps1 files parse cleanly" }

# --- Check 2: em-dash bomb in string literals --------------------------------
# Em-dash (U+2014) inside string literals breaks under encoding-strict shells.
# Most code-comment em-dashes are fine, but heuristic: flag any .ps1 that has them
# inside double-quoted strings on the same line.
Write-Host ""
Write-Host "[2/5] Em-dash encoding bomb check"
$emDash = [char]0x2014
$emDashHits = 0
foreach ($f in $psFiles) {
    $content = Get-Content $f.FullName -Raw -Encoding UTF8
    # Heuristic: any line containing both a double-quote and an em-dash is suspect.
    # Em-dashes in comments are fine; in string literals they explode under PS5.1.
    foreach ($line in ($content -split "`r?`n")) {
        if ($line.Contains($emDash) -and $line.Contains('"') -and $line -notmatch '^\s*#') {
            $emDashHits++
            Add-Warn "Possible em-dash inside string literal: $($f.Name) -- $($line.Trim())"
            break
        }
    }
}
if ($emDashHits -eq 0) { Add-Pass "no em-dashes in PowerShell string literals" }

# --- Check 3: hardcoded user paths -------------------------------------------
Write-Host ""
Write-Host "[3/5] Hardcoded user path check"
$pathHits = 0
$badPatterns = @(
    'C:\\Users\\Caspar\.Bannink',
    'C:\\Users\\CasparBannink\\\.copilot',
    'C:\\Users\\Caspar\.Bannink\\\.codex'
)
$searchExt = @("*.ps1", "*.md", "*.json", "*.tmpl")
foreach ($ext in $searchExt) {
    $files = Get-ChildItem -Path $Bundle -Recurse -Filter $ext
    foreach ($f in $files) {
        $content = Get-Content $f.FullName -Raw -Encoding UTF8 -ErrorAction SilentlyContinue
        if (-not $content) { continue }
        foreach ($pat in $badPatterns) {
            if ($content -match $pat) {
                $pathHits++
                Add-Warn "Hardcoded path in $($f.FullName.Replace($RepoRoot, '.'))"
                break
            }
        }
    }
}
if ($pathHits -eq 0) { Add-Pass "no hardcoded user paths in bundle/" }

# --- Check 4: load-bearing tools exist on disk -------------------------------
Write-Host ""
Write-Host "[4/5] Load-bearing tool presence check"
$requiredTools = @(
    "_paths.ps1", "scope-classifier.ps1", "swarm-classifier.ps1",
    "state-init.ps1", "state-gate.ps1", "specialist-memory-resolver.ps1",
    "pre-session.ps1", "post-session.ps1", "reflect-trigger.ps1",
    "auto-consolidate.ps1", "compress-memory.ps1", "test-loop.ps1", "edit-with-lint.ps1",
    "detect-slop.ps1", "harness-propose.ps1", "harness-review.ps1",
    "handoff-register.ps1", "run-packet.ps1", "workflow-evidence.ps1",
    "playwright-runner.ps1", "playwright-runner.py", "visual-diff.ps1",
    "dev-server-runner.ps1", "frontend-detector.ps1", "design-fetcher.ps1",
    "bulk-fetch-inspiration.ps1", "wiki-resolver.ps1", "wiki-compress.ps1",
    "review-evidence.ps1", "_run-ps.sh"
)
$missingTools = 0
foreach ($t in $requiredTools) {
    $p = Join-Path $ToolsDir $t
    if (-not (Test-Path $p)) {
        $missingTools++
        Add-Error "Tool missing: $t"
    }
}
if ($missingTools -eq 0) { Add-Pass "all $($requiredTools.Count) load-bearing tools present" }

# --- Check 5: every adapter dir has at least one instruction file ------------
Write-Host ""
Write-Host "[5/5] Adapter completeness check"
$adapterRoots = Get-ChildItem -Path (Join-Path $Bundle "adapters") -Directory | Where-Object { $_.Name -ne "_shared" }
$adapterIssues = 0
foreach ($a in $adapterRoots) {
    $hasInstruction = (Get-ChildItem -Path $a.FullName -Recurse -Filter "*.md" -ErrorAction SilentlyContinue).Count -gt 0
    if (-not $hasInstruction) {
        $adapterIssues++
        Add-Error "Adapter '$($a.Name)' has no instruction .md file"
    }
}
if ($adapterIssues -eq 0) { Add-Pass "all $($adapterRoots.Count) adapters have instruction files" }

# --- Verdict -----------------------------------------------------------------
Write-Host ""
Write-Host "================================================================="
Write-Host "Errors:   $($errors.Count)"
Write-Host "Warnings: $($warnings.Count)"
Write-Host ""

if ($errors.Count -gt 0) { exit 1 }
if ($Strict -and $warnings.Count -gt 0) { exit 1 }
exit 0
