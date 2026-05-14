#!/usr/bin/env pwsh
# scope-classifier.ps1
# Machine-enforceable scope classification for /build Step 0.
# Analyzes changed files and outputs ISOLATED / SHARED / CRITICAL with a reason.
#
# Usage:
#   scope-classifier.ps1                         # auto-detect from git diff
#   scope-classifier.ps1 -Files "a.ts","b.ts"   # explicit file list
#   scope-classifier.ps1 -GitBase "main"         # diff against specific ref
#
# Output: JSON { scope, reason, file_count, files }

param(
    [string[]]$Files,
    [string]$GitBase = "HEAD"
)

function Normalize-Pattern([string]$pattern) {
    return ($pattern -replace '\\', '/') -replace '\*\*', '*'
}

function Matches-IgnorePattern([string]$file, [string[]]$patterns) {
    $normalizedFile = ($file -replace '\\', '/')
    foreach ($pattern in $patterns) {
        $normalizedPattern = Normalize-Pattern $pattern
        if ($normalizedFile -like $normalizedPattern) {
            return $true
        }
    }
    return $false
}

# Auto-detect changed files if not provided
if (-not $Files) {
    $detectedFiles = [System.Collections.ArrayList]::new()

    foreach ($file in @(git diff --name-only $GitBase 2>$null)) {
        if ($file -and -not $detectedFiles.Contains($file)) {
            [void]$detectedFiles.Add($file)
        }
    }

    foreach ($file in @(git diff --cached --name-only 2>$null)) {
        if ($file -and -not $detectedFiles.Contains($file)) {
            [void]$detectedFiles.Add($file)
        }
    }

    foreach ($file in @(git status --short 2>$null | ForEach-Object { $_.Trim().Split(" ")[-1] })) {
        if ($file -and -not $detectedFiles.Contains($file)) {
            [void]$detectedFiles.Add($file)
        }
    }

    $Files = @($detectedFiles)
}

$ignorePatterns = @()
$ignoredFiles = @()
# Prefer tool-neutral .scopeignore; fall back to legacy .copilot-scopeignore
$scopeIgnorePath = Join-Path (Get-Location) ".scopeignore"
if (-not (Test-Path $scopeIgnorePath)) {
    $legacy = Join-Path (Get-Location) ".copilot-scopeignore"
    if (Test-Path $legacy) { $scopeIgnorePath = $legacy }
}
if (Test-Path $scopeIgnorePath) {
    $ignorePatterns = Get-Content $scopeIgnorePath | Where-Object {
        $_ -and $_.Trim() -and -not $_.Trim().StartsWith("#")
    } | ForEach-Object { $_.Trim() }
}

if ($ignorePatterns.Count -gt 0) {
    $keptFiles = @()
    foreach ($file in $Files) {
        if (Matches-IgnorePattern -file $file -patterns $ignorePatterns) {
            $ignoredFiles += $file
        } else {
            $keptFiles += $file
        }
    }
    $Files = $keptFiles
}

$fileCount = ($Files | Measure-Object).Count
$scope = "ISOLATED"
$reason = "Small isolated change"
$hitFile = $null

# --- CRITICAL triggers ---
# Auth, schema, public API, guarded cross-module contracts
$criticalPatterns = @(
    "auth", "permission", "role", "schema", "migration",
    "packages/types", "types/src/index", "models.py", "api.py",
    "db.ts", "prisma", "middleware", "gateway",
    ".env.local", ".env.production", ".env.secrets"  # .env.example excluded -- not a secret file
)

foreach ($file in $Files) {
    foreach ($pat in $criticalPatterns) {
        if ($file -like "*$pat*") {
            $scope = "CRITICAL"
            $hitFile = $file
            $reason = "Touches guarded/schema/auth file: $file (matched pattern: $pat)"
            break
        }
    }
    if ($scope -eq "CRITICAL") { break }
}

# --- SHARED triggers ---
# Shared interfaces, packages, services, hooks, context providers
if ($scope -ne "CRITICAL") {
    $sharedPatterns = @(
        "packages/", "shared/", "common/", "utils/", "config/",
        "routes/", "services/", "hooks/", "context/", "store/",
        "providers/", "adapters/", "clients/"
    )

    foreach ($file in $Files) {
        foreach ($pat in $sharedPatterns) {
            if ($file -like "*$pat*") {
                $scope = "SHARED"
                $hitFile = $file
                $reason = "Touches shared interface or service: $file (matched pattern: $pat)"
                break
            }
        }
        if ($scope -eq "SHARED") { break }
    }

    # File count alone can push to SHARED
    if ($scope -eq "ISOLATED" -and $fileCount -gt 5) {
        $scope = "SHARED"
        $reason = "$fileCount files changed -- exceeds ISOLATED threshold of 5"
    }
}

# --- ISOLATED confirmation ---
if ($scope -eq "ISOLATED") {
    if ($fileCount -eq 1) {
        $reason = "Single isolated file: $($Files[0])"
    } elseif ($fileCount -eq 0) {
        $reason = "No changed files detected -- defaulting to ISOLATED"
    } else {
        $reason = "$fileCount isolated files, no shared interfaces"
    }
}

$result = [ordered]@{
    scope      = $scope
    reason     = $reason
    file_count = $fileCount
    files      = @($Files)
    ignored_count = @($ignoredFiles).Count
    ignored_files = @($ignoredFiles)
}

Write-Output ($result | ConvertTo-Json -Compress)
