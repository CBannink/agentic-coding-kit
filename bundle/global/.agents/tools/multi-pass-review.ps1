#!/usr/bin/env pwsh
# multi-pass-review.ps1 -- split a git diff into per-file chunks, shuffle the
# file order randomly for each pass, and write each pass to a temp file so
# reviewers can be spawned against independent orderings.
#
# Why: reviewers exhibit ordering bias -- files reviewed later receive less
# attention than files reviewed first. Running N passes with independently
# shuffled file order and then deduplicating findings catches ~2x more bugs
# than a single ordered read (confirmed by empirical multi-agent review
# studies).
#
# Usage:
#   pwsh multi-pass-review.ps1 -SessionId <id> [-DiffSource <src>] [-Passes <n>] [-OutputDir <dir>]
#
# Parameters:
#   -SessionId   (mandatory) session id for locating the session dir
#   -DiffSource  "staged" | "HEAD" | "HEAD~1" | "<file-path>" (default: "HEAD")
#   -Passes      number of shuffled passes to generate (default: 3)
#   -OutputDir   override output directory (default: session dir)
#
# Output (JSON):
#   {
#     "ok": true,
#     "total_files": N,
#     "passes": [
#       { "pass": 1, "path": "/abs/path/review-pass-1.diff", "file_count": N, "file_order": ["a.ts", "b.ts"] },
#       ...
#     ]
#   }
#
# Exit codes:
#   0 = ok
#   1 = error (message on stderr, JSON with ok:false on stdout)

param(
    [Parameter(Mandatory=$true)][string]$SessionId,
    [string]$DiffSource = "HEAD",
    [int]$Passes = 3,
    [string]$OutputDir = ""
)

. (Join-Path $PSScriptRoot "_paths.ps1")

function Out-Error {
    param([string]$Msg)
    Write-Error $Msg
    @{ ok = $false; error = $Msg } | ConvertTo-Json -Compress | Write-Output
    exit 1
}

# Resolve output directory
$sessDir = Get-SessionDir $SessionId
New-Item -ItemType Directory -Path $sessDir -Force | Out-Null

$outDir = if ($OutputDir) { $OutputDir } else { $sessDir }
New-Item -ItemType Directory -Path $outDir -Force | Out-Null

# Obtain raw diff text
$rawDiff = ""

$isFilePath = ($DiffSource -notmatch '^(staged|HEAD.*)$') -and (Test-Path $DiffSource -PathType Leaf)

if ($isFilePath) {
    try {
        $rawDiff = Get-Content -Path $DiffSource -Raw -Encoding UTF8
    } catch {
        Out-Error "Could not read diff file '$DiffSource': $_"
    }
} else {
    $gitArgs = @()
    switch ($DiffSource) {
        "staged"  { $gitArgs = @("diff", "--cached") }
        "HEAD"    { $gitArgs = @("diff", "HEAD") }
        default   { $gitArgs = @("diff", $DiffSource) }
    }
    try {
        $rawDiff = & git @gitArgs 2>&1
        if ($LASTEXITCODE -ne 0) {
            Out-Error "git diff exited $LASTEXITCODE: $rawDiff"
        }
        $rawDiff = $rawDiff -join "`n"
    } catch {
        Out-Error "Failed to run git diff: $_"
    }
}

if (-not $rawDiff -or $rawDiff.Trim().Length -eq 0) {
    Out-Error "Diff is empty. Nothing to review."
}

# Split into per-file sections. Each section starts with "diff --git".
# Keep the header line as part of the section.
$lines = $rawDiff -split "`n"
$sections = [System.Collections.Generic.List[string[]]]::new()
$currentSection = [System.Collections.Generic.List[string]]::new()

foreach ($line in $lines) {
    if ($line -match '^diff --git ') {
        if ($currentSection.Count -gt 0) {
            $sections.Add($currentSection.ToArray())
        }
        $currentSection = [System.Collections.Generic.List[string]]::new()
    }
    $currentSection.Add($line)
}
if ($currentSection.Count -gt 0) {
    $sections.Add($currentSection.ToArray())
}

$totalFiles = $sections.Count
if ($totalFiles -eq 0) {
    Out-Error "Could not parse any per-file sections from diff."
}

# Extract a display name for each section (the a/b path from the header line)
function Get-SectionName([string[]]$Section) {
    $header = $Section[0]
    if ($header -match '^diff --git a/(.+?) b/') {
        return $Matches[1]
    }
    return $header
}

# Fisher-Yates shuffle on an array copy
function Invoke-Shuffle([object[]]$Arr) {
    $copy = [object[]]::new($Arr.Length)
    [Array]::Copy($Arr, $copy, $Arr.Length)
    $rng = [System.Random]::new()
    for ($i = $copy.Length - 1; $i -gt 0; $i--) {
        $j = $rng.Next(0, $i + 1)
        $tmp = $copy[$i]
        $copy[$i] = $copy[$j]
        $copy[$j] = $tmp
    }
    return $copy
}

# Generate passes
$passResults = [System.Collections.Generic.List[hashtable]]::new()

for ($p = 1; $p -le $Passes; $p++) {
    $shuffled = Invoke-Shuffle -Arr $sections.ToArray()
    $fileOrder = @($shuffled | ForEach-Object { Get-SectionName $_ })
    $passContent = ($shuffled | ForEach-Object { $_ -join "`n" }) -join "`n"

    $passFile = Join-Path $outDir "review-pass-$p.diff"
    try {
        $passContent | Set-Content -Path $passFile -Encoding UTF8 -NoNewline
    } catch {
        Out-Error "Failed to write pass file '$passFile': $_"
    }

    $passResults.Add(@{
        pass       = $p
        path       = $passFile
        file_count = $shuffled.Count
        file_order = $fileOrder
    })
}

@{
    ok          = $true
    total_files = $totalFiles
    passes      = $passResults.ToArray()
} | ConvertTo-Json -Depth 6 -Compress | Write-Output
