#!/usr/bin/env pwsh
# frontend-detector.ps1 -- decide whether a diff or file list contains
# user-visible UI changes that should fire the frontend visual gate
# (ux-driver + ui-driver loop) in /build.
#
# Why: scope-classifier picks ISOLATED/SHARED/CRITICAL but doesn't tell
# /build whether to fire the visual loop. This script answers that one
# question with a JSON verdict the build skill keys on.
#
# Usage:
#   pwsh frontend-detector.ps1                     # reads `git diff --name-only HEAD`
#   pwsh frontend-detector.ps1 -Files <comma-sep>  # explicit file list
#   pwsh frontend-detector.ps1 -Json               # default; machine-readable
#
# Output:
#   {
#     frontend: <true|false>,
#     confidence: <high|medium|low>,
#     reason: "<why>",
#     surfaces: ["<file or dir glob hit>", ...],
#     visual_loop_recommended: <true|false>
#   }
#
# Triggers (any one => frontend=true):
#   - Files matching: *.tsx, *.jsx, *.vue, *.svelte, *.astro
#   - Files matching: *.css, *.scss, *.sass, *.less, *.module.css
#   - Files in: app/, pages/, components/, src/ui/, src/components/, src/views/
#   - Files: tailwind.config.*, postcss.config.*, theme.* (if not test)
#   - HTML changes outside test fixtures
#
# visual_loop_recommended is true when frontend=true AND there are screens
# affected (not just style tokens). Token-only changes get verified via
# visual-diff.ps1 across all screens, not via per-screen ux/ui critique.

param(
    [string]$Files = "",
    [switch]$Json
)

function Out-Result {
    param([hashtable]$Data, [int]$ExitCode = 0)
    $Data | ConvertTo-Json -Compress -Depth 5 | Write-Output
    exit $ExitCode
}

# Resolve file list
$fileList = @()
if ($Files) {
    $fileList = @($Files -split '[,;\n]' | ForEach-Object { $_.Trim() } | Where-Object { $_ })
} else {
    try {
        $diffOut = & git diff --name-only HEAD 2>$null
        if ($LASTEXITCODE -eq 0 -and $diffOut) {
            $fileList = @($diffOut -split "`n" | ForEach-Object { $_.Trim() } | Where-Object { $_ })
        }
    } catch {}
    if ($fileList.Count -eq 0) {
        try {
            $statusOut = & git status --porcelain 2>$null
            if ($LASTEXITCODE -eq 0 -and $statusOut) {
                $fileList = @($statusOut -split "`n" | ForEach-Object {
                    $line = $_.Trim()
                    if ($line.Length -ge 3) { $line.Substring(3).Trim() } else { "" }
                } | Where-Object { $_ })
            }
        } catch {}
    }
}

if ($fileList.Count -eq 0) {
    Out-Result @{
        frontend = $false
        confidence = "high"
        reason = "no changed files detected"
        surfaces = @()
        visual_loop_recommended = $false
    }
}

# Patterns
$componentExtPattern = '\.(tsx|jsx|vue|svelte|astro)$'
$styleExtPattern = '\.(css|scss|sass|less)$'
$frontendDirPattern = '(^|/)(app|pages|components|views|screens|routes|src/ui|src/components|src/views|src/pages|src/screens|frontend|web|client)/'
$configFilePattern = '(tailwind\.config|postcss\.config|theme\.|design-tokens\.|stylelint\.config)'
$testFilePattern = '(\.test\.|\.spec\.|__tests__/|fixtures/|__snapshots__/)'

$componentHits = @()
$styleHits = @()
$dirHits = @()
$configHits = @()
$tokenOnly = $true

foreach ($f in $fileList) {
    $isTest = $f -match $testFilePattern
    if ($isTest) { continue }

    if ($f -match $componentExtPattern) {
        $componentHits += $f
        $tokenOnly = $false
    } elseif ($f -match $styleExtPattern) {
        $styleHits += $f
    } elseif ($f -match $frontendDirPattern) {
        $dirHits += $f
        $tokenOnly = $false
    } elseif ($f -match $configFilePattern) {
        $configHits += $f
    }
}

$totalHits = $componentHits.Count + $styleHits.Count + $dirHits.Count + $configHits.Count

if ($totalHits -eq 0) {
    Out-Result @{
        frontend = $false
        confidence = "high"
        reason = "no frontend files in changed set"
        surfaces = @()
        visual_loop_recommended = $false
    }
}

# Confidence
$confidence = if ($componentHits.Count -ge 1) { "high" }
              elseif ($dirHits.Count -ge 1) { "high" }
              elseif ($styleHits.Count -ge 2) { "high" }
              elseif ($styleHits.Count -ge 1 -or $configHits.Count -ge 1) { "medium" }
              else { "low" }

$reasonParts = @()
if ($componentHits.Count -gt 0) { $reasonParts += "$($componentHits.Count) component file(s)" }
if ($styleHits.Count -gt 0)     { $reasonParts += "$($styleHits.Count) style file(s)" }
if ($dirHits.Count -gt 0)       { $reasonParts += "$($dirHits.Count) frontend-dir file(s)" }
if ($configHits.Count -gt 0)    { $reasonParts += "$($configHits.Count) config file(s)" }

$visualLoop = ($componentHits.Count -ge 1) -or ($dirHits.Count -ge 1)

Out-Result @{
    frontend = $true
    confidence = $confidence
    reason = ($reasonParts -join ", ")
    surfaces = @($componentHits + $dirHits + $styleHits + $configHits | Select-Object -Unique)
    component_count = $componentHits.Count
    style_count = $styleHits.Count
    token_only = $tokenOnly
    visual_loop_recommended = $visualLoop
}
