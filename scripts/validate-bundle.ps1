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
Write-Host "[1/7] PowerShell parse check"
$psFiles = @(
    Get-ChildItem -Path $Bundle -Recurse -Filter "*.ps1"
    Get-ChildItem -Path $ScriptRoot -Recurse -Filter "*.ps1"
) | Sort-Object FullName -Unique
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
Write-Host "[2/7] Em-dash encoding bomb check"
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
Write-Host "[3/7] Hardcoded user path check"
$pathHits = 0
$badPatterns = @(
    'C:\\Users\\Caspar\.Bannink',
    'C:\\Users\\CasparBannink\\\.copilot',
    'C:\\Users\\Caspar\.Bannink\\\.codex',
    # Catch any maintainer-specific Downloads/<repo> path. Bundled scripts must
    # never embed the maintainer's checkout location -- they ship to other
    # users' machines.
    'Downloads[\\/]caspar_bannink_agentic_coding',
    'Downloads[\\/]agentic-coding-kit',
    # Personal email domains that should never appear in installed scripts.
    'caspar\.christiaan@'
)
$searchExt = @("*.ps1", "*.md", "*.json", "*.tmpl")
$searchRoots = @($Bundle, $ScriptRoot)
foreach ($ext in $searchExt) {
    $files = foreach ($root in $searchRoots) {
        Get-ChildItem -Path $root -Recurse -Filter $ext -ErrorAction SilentlyContinue
    }
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
Write-Host "[4/7] Load-bearing tool presence check"
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
    "review-evidence.ps1", "_run-ps.sh",
    "merge-codex-config.ps1",
    "auto-apply-reflect.ps1",
    "reflection-emitter-stats.ps1",
    "specialist-memory-append.ps1",
    "kit-health-digest.ps1",
    "hooks/pretool-bash-dispatcher.ps1",
    "hooks/pretool-read-delegation-gate.ps1",
    "hooks/pretool-write-gateguard.ps1",
    "hooks/pretool-task-orchestrator-gate.ps1",
    "hooks/posttool-bash-verify-mark.ps1"
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

# --- Check 5: skill frontmatter is safe for strict YAML loaders ---------------
Write-Host ""
Write-Host "[5/7] Skill frontmatter YAML safety check"
$skillFiles = Get-ChildItem -Path $Bundle -Recurse -Filter "SKILL.md" -ErrorAction SilentlyContinue
$skillFrontmatterIssues = 0
foreach ($f in $skillFiles) {
    $content = Get-Content $f.FullName -Raw -Encoding UTF8 -ErrorAction SilentlyContinue
    if (-not $content) { continue }
    if ($content -notmatch '(?s)^---\r?\n(.*?)\r?\n---') { continue }
    $frontmatter = $Matches[1]
    foreach ($line in ($frontmatter -split "`r?`n")) {
        if ($line -match '^\s*description:\s+(.+)$') {
            $value = $Matches[1].Trim()
            $isQuoted = ($value.StartsWith('"') -and $value.EndsWith('"')) -or
                        ($value.StartsWith("'") -and $value.EndsWith("'")) -or
                        ($value -match '^[>|]')
            if (-not $isQuoted -and $value -match ':\s') {
                $skillFrontmatterIssues++
                Add-Error "Unquoted description contains YAML colon: $($f.FullName.Replace($RepoRoot, '.'))"
            }
        }
    }
}
if ($skillFrontmatterIssues -eq 0) { Add-Pass "$($skillFiles.Count) SKILL.md frontmatter blocks are YAML-safe" }

# --- Check 6: repo-template workflow brief placeholders are explicit ---------
Write-Host ""
Write-Host "[6/7] Workflow brief placeholder check"
$briefDir = Join-Path $Bundle "repo-template/.kit/context/workflow-briefs"
$requiredBriefs = @(
    "workflow-explorer.md",
    "workflow-implementer.md",
    "workflow-reviewer.md",
    "workflow-skeptic.md",
    "workflow-ui-qa.md",
    "prompt-synthesizer.md"
)
$briefIssues = 0
foreach ($brief in $requiredBriefs) {
    $path = Join-Path $briefDir $brief
    if (-not (Test-Path $path)) {
        $briefIssues++
        Add-Error "Workflow brief template missing: $brief"
        continue
    }
    $raw = Get-Content -Path $path -Raw -Encoding UTF8
    if ($raw -notmatch 'PLACEHOLDER' -or $raw -notmatch '_not yet detected_') {
        $briefIssues++
        Add-Error "Workflow brief template must be explicit placeholder: $brief"
    }
}
if ($briefIssues -eq 0) { Add-Pass "$($requiredBriefs.Count) workflow brief templates present and placeholder-marked" }

# --- Check 7: every adapter dir has at least one instruction file ------------
Write-Host ""
Write-Host "[7/7] Adapter completeness check"
$adapterRoots = Get-ChildItem -Path (Join-Path $Bundle "adapters") -Directory | Where-Object { $_.Name -ne "_shared" }
$adapterIssues = 0
foreach ($a in $adapterRoots) {
    $hasInstruction = (Get-ChildItem -Path $a.FullName -Recurse -Filter "*.md" -ErrorAction SilentlyContinue).Count -gt 0
    if (-not $hasInstruction) {
        $adapterIssues++
        Add-Error "Adapter '$($a.Name)' has no instruction .md file"
    }
}
$requiredSharedTemplates = @(
    "workflow-commands/analyze.md",
    "workflow-commands/bootstrap-harness.md",
    "workflow-commands/build.md",
    "workflow-commands/goal.md",
    "workflow-commands/investigate.md",
    "workflow-commands/kit-init.md",
    "workflow-commands/kit-migrate.md",
    "workflow-commands/plan.md",
    "workflow-commands/redesign.md",
    "workflow-commands/refactor.md",
    "workflow-commands/review.md",
    "workflow-commands/security-review.md",
    "workflow-commands/wiki-init.md",
    "workflow-agents/workflow-explorer.md",
    "workflow-agents/workflow-implementer.md",
    "workflow-agents/workflow-reviewer.md",
    "workflow-agents/workflow-skeptic.md",
    "workflow-agents/workflow-ui-qa.md",
    "specialist-agents/adversarial-reviewer.md",
    "specialist-agents/goal-orchestrator.md",
    "specialist-agents/pr-reviewer.md"
)
$sharedRoot = Join-Path $Bundle "adapters/_shared"
$missingSharedTemplates = 0
foreach ($template in $requiredSharedTemplates) {
    $fullPath = Join-Path $sharedRoot $template
    if (-not (Test-Path $fullPath)) {
        $missingSharedTemplates++
        Add-Error "Shared workflow template missing: $template"
    }
}
if ($adapterIssues -eq 0 -and $missingSharedTemplates -eq 0) {
    Add-Pass "all $($adapterRoots.Count) adapters have instruction files and $($requiredSharedTemplates.Count) shared workflow templates exist"
}

# --- Verdict -----------------------------------------------------------------
Write-Host ""
Write-Host "================================================================="
Write-Host "Errors:   $($errors.Count)"
Write-Host "Warnings: $($warnings.Count)"
Write-Host ""

if ($errors.Count -gt 0) { exit 1 }
if ($Strict -and $warnings.Count -gt 0) { exit 1 }
exit 0
