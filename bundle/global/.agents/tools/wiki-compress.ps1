#!/usr/bin/env pwsh
# wiki-compress.ps1 -- detect bloated .wiki/ pages and report violations.
#
# Why: wiki pages drift toward bloat as people append. The wiki-init skill
# enforces size budgets at creation time; this tool enforces them over time.
# Returns violations -- agent or user condenses surgically.
#
# Does NOT auto-rewrite. Wikis are durable repo memory; auto-condensing is
# too risky. Reports violations + suggests target size; user / /wiki-init
# regenerates the offending sections.
#
# Usage:
#   pwsh wiki-compress.ps1                          # report only, default budgets
#   pwsh wiki-compress.ps1 -RepoRoot <path>
#   pwsh wiki-compress.ps1 -SectionMaxLines 200     # custom budget
#   pwsh wiki-compress.ps1 -Json                    # machine-readable
#
# Default budgets (matching wiki-init/SKILL.md):
#   sections/<name>.md: 150 lines
#   architecture.md:    200 lines
#   features.md:        300 lines
#
# Exit codes:
#   0 = no violations
#   1 = error
#   2 = violations found

param(
    [string]$RepoRoot = (Get-Location).Path,
    [int]$SectionMaxLines = 150,
    [int]$ArchitectureMaxLines = 200,
    [int]$FeaturesMaxLines = 300,
    [int]$IndexMaxLines = 100,
    [switch]$Json
)

$wikiDir = Join-Path $RepoRoot ".wiki"
if (-not (Test-Path $wikiDir)) {
    if ($Json) { @{ ok = $true; wiki_present = $false; violations = @() } | ConvertTo-Json -Compress | Write-Output } else { "No .wiki/ in $RepoRoot. Nothing to compress." }
    exit 0
}

$violations = @()

function Check-File {
    param([string]$Path, [int]$Budget, [string]$Category)
    if (-not (Test-Path $Path)) { return }
    $lineCount = (Get-Content $Path | Measure-Object -Line).Lines
    if ($lineCount -gt $Budget) {
        $script:violations += @{
            path = $Path.Substring($RepoRoot.Length + 1) -replace '\\', '/'
            category = $Category
            lines = $lineCount
            budget = $Budget
            over_by = $lineCount - $Budget
            severity = if ($lineCount -gt ($Budget * 1.5)) { "high" } else { "medium" }
        }
    }
}

# index.md
Check-File -Path (Join-Path $wikiDir "index.md") -Budget $IndexMaxLines -Category "index"

# features.md
Check-File -Path (Join-Path $wikiDir "features.md") -Budget $FeaturesMaxLines -Category "features"

# architecture.md
Check-File -Path (Join-Path $wikiDir "architecture.md") -Budget $ArchitectureMaxLines -Category "architecture"

# sections/*.md
$sectionsDir = Join-Path $wikiDir "sections"
if (Test-Path $sectionsDir) {
    foreach ($f in (Get-ChildItem -Path $sectionsDir -Filter "*.md" -File)) {
        Check-File -Path $f.FullName -Budget $SectionMaxLines -Category "section"
    }
}

# .features count check (should match features.md scope -- not size)
$featuresIdx = Join-Path $wikiDir ".features"
$featuresIdxCount = if (Test-Path $featuresIdx) {
    (Get-Content $featuresIdx | Where-Object { $_ -and -not $_.StartsWith("#") }).Count
} else { 0 }

# Drift signal: .features count vs features.md feature line count rough mismatch
$featuresMdCount = 0
if (Test-Path (Join-Path $wikiDir "features.md")) {
    $featuresMdCount = (Get-Content (Join-Path $wikiDir "features.md") | Where-Object { $_ -match '^\s*-\s' }).Count
}
$drift = $null
if ($featuresIdxCount -gt 0 -and $featuresMdCount -gt 0) {
    $diff = [Math]::Abs($featuresIdxCount - $featuresMdCount)
    if ($diff -gt ($featuresIdxCount * 0.3)) {
        $drift = "features.md has $featuresMdCount bullets, .features has $featuresIdxCount IDs -- $diff difference (>30%). Files may be out of sync."
    }
}

$result = @{
    ok = ($violations.Count -eq 0 -and -not $drift)
    wiki_present = $true
    violations = $violations
    drift = $drift
    stats = @{
        sections_total = if (Test-Path $sectionsDir) { (Get-ChildItem $sectionsDir -Filter "*.md" -File).Count } else { 0 }
        features_md_lines = if (Test-Path (Join-Path $wikiDir "features.md")) { (Get-Content (Join-Path $wikiDir "features.md") | Measure-Object -Line).Lines } else { 0 }
        features_idx_count = $featuresIdxCount
    }
}

if ($Json) {
    $result | ConvertTo-Json -Compress -Depth 5 | Write-Output
} else {
    Write-Host ""
    Write-Host "wiki-compress -- $RepoRoot/.wiki/"
    Write-Host "================================="
    Write-Host ""
    Write-Host "Stats: $($result.stats.sections_total) section pages, features.md=$($result.stats.features_md_lines) lines, .features=$($result.stats.features_idx_count) IDs"
    Write-Host ""

    if ($violations.Count -eq 0) {
        Write-Host "[OK] all pages within budget"
    } else {
        Write-Host "Bloat violations ($($violations.Count)):"
        foreach ($v in $violations) {
            $tag = if ($v.severity -eq "high") { "[HIGH]" } else { "[MED] " }
            Write-Host "  $tag $($v.path) -- $($v.lines) lines (budget $($v.budget); over by $($v.over_by))"
        }
        Write-Host ""
        Write-Host "Recommendation: re-run /wiki-init for the offending sections, OR"
        Write-Host "surgically condense (remove stale notes, merge with sibling, link out)."
    }

    if ($drift) {
        Write-Host ""
        Write-Host "Drift signal: $drift"
    }
}

if ($violations.Count -gt 0 -or $drift) { exit 2 } else { exit 0 }
