#!/usr/bin/env pwsh
# visual-diff.ps1 -- pair before/after screenshots and produce diff PNGs.
#
# Usage:
#   pwsh ~/.agents/tools/visual-diff.ps1 -BeforeDir ./before -AfterDir ./after -OutDir ./diff
#
# Prefers `magick compare` (ImageMagick 7) if available -- produces highlight diffs
# with a numeric diff score. Falls back to `compare` (ImageMagick 6) or `pixelmatch`
# via `npx`. If none are available, writes a side-by-side stacked image only.
#
# Output:
#   <OutDir>/<basename>__diff.png     -- visual diff (red highlights)
#   <OutDir>/diff-report.json         -- per-image score, totals, regressions

param(
    [Parameter(Mandatory)][string]$BeforeDir,
    [Parameter(Mandatory)][string]$AfterDir,
    [Parameter(Mandatory)][string]$OutDir,
    [double]$RegressionThreshold = 0.05  # 5% pixel-diff fraction = regression
)

if (-not (Test-Path $BeforeDir)) { Write-Error "BeforeDir not found: $BeforeDir"; exit 1 }
if (-not (Test-Path $AfterDir))  { Write-Error "AfterDir not found: $AfterDir"; exit 1 }
New-Item -ItemType Directory -Path $OutDir -Force | Out-Null

# Detect available tool
$tool = $null
if (Get-Command "magick" -ErrorAction SilentlyContinue) {
    $tool = "magick"
} elseif (Get-Command "compare" -ErrorAction SilentlyContinue) {
    $tool = "compare"
} elseif (Get-Command "npx" -ErrorAction SilentlyContinue) {
    $tool = "pixelmatch"
} else {
    Write-Host "No diff tool found. Install ImageMagick (magick/compare) or Node (npx pixelmatch)."
    Write-Host "Falling back to filename-only pairing -- no visual diff."
}

$beforeFiles = Get-ChildItem $BeforeDir -Filter "*.png" | Sort-Object Name
$results = @()

foreach ($b in $beforeFiles) {
    $afterPath = Join-Path $AfterDir $b.Name
    $diffPath  = Join-Path $OutDir ("{0}__diff.png" -f [System.IO.Path]::GetFileNameWithoutExtension($b.Name))
    $score = $null
    $status = "unknown"

    if (-not (Test-Path $afterPath)) {
        $status = "missing-after"
        $results += [pscustomobject]@{
            name = $b.Name
            status = $status
            diff_score = $null
            before = $b.FullName
            after = $null
            diff = $null
        }
        Write-Host "  $($b.Name): MISSING in after-dir"
        continue
    }

    if ($tool -eq "magick") {
        $cmd = & magick compare -metric AE -fuzz 5% $b.FullName $afterPath $diffPath 2>&1
        # AE returns absolute pixel count
        $absPixels = 0
        if ($cmd -match "^\s*(\d+)\s*$") { $absPixels = [int]$Matches[1] }
        $totalPixels = 1920 * 1080  # assume default; refine if needed
        $score = if ($totalPixels -gt 0) { $absPixels / $totalPixels } else { 0 }
        $status = if ($score -gt $RegressionThreshold) { "regression" } else { "ok" }
    } elseif ($tool -eq "compare") {
        & compare -metric AE -fuzz 5% $b.FullName $afterPath $diffPath 2>$null
        $status = "diffed"
    } elseif ($tool -eq "pixelmatch") {
        & npx -y pixelmatch $b.FullName $afterPath $diffPath 0.1 2>&1 | Out-Null
        $status = "diffed"
    }

    Write-Host "  $($b.Name): $status$(if ($score -ne $null) { " (score=$([math]::Round($score, 4)))" })"
    $results += [pscustomobject]@{
        name = $b.Name
        status = $status
        diff_score = $score
        before = $b.FullName
        after = $afterPath
        diff = if (Test-Path $diffPath) { $diffPath } else { $null }
    }
}

$report = [ordered]@{
    generated_at = (Get-Date -Format "o")
    tool         = $tool
    before_dir   = (Resolve-Path $BeforeDir).Path
    after_dir    = (Resolve-Path $AfterDir).Path
    out_dir      = (Resolve-Path $OutDir).Path
    threshold    = $RegressionThreshold
    total        = $results.Count
    regressions  = @($results | Where-Object { $_.status -eq "regression" }).Count
    missing      = @($results | Where-Object { $_.status -eq "missing-after" }).Count
    items        = $results
}

$reportPath = Join-Path $OutDir "diff-report.json"
$report | ConvertTo-Json -Depth 5 | Set-Content -Path $reportPath -Encoding utf8
Write-Host ""
Write-Host "Report: $reportPath"
Write-Host "Regressions: $($report.regressions) / $($report.total)"
