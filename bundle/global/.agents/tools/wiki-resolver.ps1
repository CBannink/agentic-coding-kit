#!/usr/bin/env pwsh
# wiki-resolver.ps1 -- the lazy-loader for .wiki/sections/.
#
# Why: bulk-loading the whole .wiki/ tree into every session is bloat.
# This tool returns ONLY the section pages relevant to the current task,
# matched by:
#   1. "Key files" in the section page overlapping with the changed-file
#      set (highest signal)
#   2. Section name appearing in the task description (fallback signal)
#
# Skills embed only the returned pages in subagent prompts. If nothing
# matches, return empty -- skills proceed without wiki context.
#
# Usage:
#   pwsh wiki-resolver.ps1 -Task "fix proxy import bug" -ChangedFiles "src/proxy/import.ts,src/proxy/parser.ts" -RepoRoot .
#   pwsh wiki-resolver.ps1 -Task "add new endpoint" -RepoRoot .   # task-only, no file list
#
# Output (JSON):
#   {
#     ok: true,
#     wiki_present: true,
#     matched_sections: [
#       { name: "proxy", path: ".wiki/sections/proxy.md", reason: "files: src/proxy/import.ts" },
#       { name: "api", path: ".wiki/sections/api.md", reason: "task: 'endpoint'" }
#     ],
#     prompt_block: "<text to embed verbatim in subagent prompts>",
#     stats: { total_sections: 8, matched: 2 }
#   }
#
# Exit codes:
#   0 = ok (matched or not, both fine)
#   1 = error
#   2 = wiki not present

param(
    [Parameter(Mandatory=$true)][string]$Task,
    [string]$ChangedFiles = "",
    [string]$RepoRoot = (Get-Location).Path,
    [int]$MaxSections = 5,
    [int]$MaxLinesPerSection = 200,
    [switch]$VerboseLog
)

function Out-Json {
    param([hashtable]$Data, [int]$ExitCode = 0)
    $Data | ConvertTo-Json -Compress -Depth 6 | Write-Output
    exit $ExitCode
}

$wikiDir = Join-Path $RepoRoot ".wiki"
$sectionsDir = Join-Path $wikiDir "sections"

if (-not (Test-Path $wikiDir)) {
    Out-Json @{
        ok = $true
        wiki_present = $false
        matched_sections = @()
        prompt_block = ""
        suggestion = "No .wiki/ in this repo. Run /wiki-init to bootstrap one."
        stats = @{ total_sections = 0; matched = 0 }
    } 2
}

$sections = @()
if (Test-Path $sectionsDir) {
    $sections = @(Get-ChildItem -Path $sectionsDir -Filter "*.md" -File)
}

if ($sections.Count -eq 0) {
    Out-Json @{
        ok = $true
        wiki_present = $true
        matched_sections = @()
        prompt_block = ""
        suggestion = "No section pages in .wiki/sections/. Re-run /wiki-init or add pages manually."
        stats = @{ total_sections = 0; matched = 0 }
    } 0
}

# Tokenize task for section-name matching
$taskLower = $Task.ToLower()
$changedList = @()
if ($ChangedFiles) {
    $changedList = @($ChangedFiles -split '[,;\n]' | ForEach-Object { $_.Trim() } | Where-Object { $_ })
}

$matches = @()

foreach ($s in $sections) {
    $name = [System.IO.Path]::GetFileNameWithoutExtension($s.Name)
    $content = Get-Content $s.FullName -Raw -Encoding UTF8

    # Extract "Key files" entries -- look for lines under "## Key files" until next header
    $keyFiles = @()
    $keySection = ($content -split '##\s+Key files', 2)[1]
    if ($keySection) {
        $keySection = ($keySection -split '##\s+', 2)[0]
        # Match `path/to/file.ext` or `path/to/dir/` in backticks
        $keyMatches = [regex]::Matches($keySection, '`([^`]+)`')
        foreach ($m in $keyMatches) {
            $kf = $m.Groups[1].Value.Trim().TrimEnd('/')
            if ($kf) { $keyFiles += $kf }
        }
    }

    $matchedReasons = @()

    # Signal 1: changed files overlap with key files (substring match either way)
    foreach ($cf in $changedList) {
        $cfNorm = $cf -replace '\\', '/'
        foreach ($kf in $keyFiles) {
            $kfNorm = $kf -replace '\\', '/'
            if ($cfNorm -eq $kfNorm -or $cfNorm.StartsWith("$kfNorm/") -or $kfNorm.StartsWith("$cfNorm/") -or
                ($kfNorm.Contains('/') -and $cfNorm.Contains($kfNorm)) -or
                ($cfNorm.Contains('/') -and $kfNorm.Contains($cfNorm))) {
                $matchedReasons += "files: $cf"
                break
            }
        }
        if ($matchedReasons.Count -gt 0) { break }
    }

    # Signal 2: section name appears in task description (whole word, lowercase)
    if ($matchedReasons.Count -eq 0) {
        $nameLower = $name.ToLower()
        if ($taskLower -match "\b$([regex]::Escape($nameLower))\b") {
            $matchedReasons += "task: '$nameLower'"
        }
    }

    if ($matchedReasons.Count -gt 0) {
        # Truncate content to size budget
        $lines = $content -split "`r?`n"
        $excerpt = if ($lines.Count -le $MaxLinesPerSection) {
            $content
        } else {
            ($lines[0..($MaxLinesPerSection - 1)] -join "`n") + "`n`n[...truncated for context budget; read full at $($s.FullName.Substring($RepoRoot.Length + 1))...]"
        }

        $matches += @{
            name = $name
            path = $s.FullName.Substring($RepoRoot.Length + 1) -replace '\\', '/'
            reason = ($matchedReasons -join "; ")
            excerpt = $excerpt
            lines = $lines.Count
        }
    }
}

# Cap to MaxSections (highest priority by reason quality: file matches first)
$matches = $matches | Sort-Object @{ Expression = { if ($_.reason -match '^files:') { 0 } else { 1 } } } | Select-Object -First $MaxSections

# Build the prompt block
$promptBlock = ""
if ($matches.Count -gt 0) {
    $sb = New-Object System.Text.StringBuilder
    [void]$sb.AppendLine("## Wiki context (relevant sections only)")
    [void]$sb.AppendLine("")
    foreach ($m in $matches) {
        [void]$sb.AppendLine("### $($m.name) -- $($m.path)")
        [void]$sb.AppendLine("(matched: $($m.reason))")
        [void]$sb.AppendLine("")
        [void]$sb.AppendLine($m.excerpt)
        [void]$sb.AppendLine("")
    }
    $promptBlock = $sb.ToString()
}

Out-Json @{
    ok = $true
    wiki_present = $true
    matched_sections = @($matches | ForEach-Object { @{ name = $_.name; path = $_.path; reason = $_.reason; lines = $_.lines } })
    prompt_block = $promptBlock
    stats = @{ total_sections = $sections.Count; matched = $matches.Count }
}
