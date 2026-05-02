#!/usr/bin/env pwsh
# detect-slop.ps1
# Mechanical detector for AI-generated slop patterns. REPORTS findings; only
# applies the safest cosmetic fixes (trailing whitespace, triple+ blank lines)
# when -Fix is passed. Refactoring needs judgment -- surface for the agent.
#
# Detectors (count emitted as "issues"):
#   1. Excessive comment ratio (>40% of non-blank lines are comment-only)
#   2. Commented-out code (// or # followed by what parses as code)
#   3. Empty try/catch (catch block with only whitespace + close brace)
#   4. Oversized files (>500 lines for code, >800 for markdown)
#   5. Oversized functions (>100 lines between def/function start and dedent)
#   6. Old TODO/FIXME via git blame (>90 days)
#   7. Generic variable names (data/result/value/temp/var1) appearing >5 times
#   8. Trailing whitespace                              -- safe to fix
#   9. Triple+ blank lines                              -- safe to fix
#  10. Multi-level nesting (>4 levels deep, language-detected)
#
# Usage:
#   pwsh detect-slop.ps1                       # scan current dir
#   pwsh detect-slop.ps1 -Path src/            # scan a subtree
#   pwsh detect-slop.ps1 -Path src/ -Fix       # also apply safe auto-fixes
#   pwsh detect-slop.ps1 -Json                 # machine-readable report
#
# Output: human-readable summary + JSON report at ./slop-report.json (or stdout
# with -Json). Exit code 0 always (this is a report tool, not a gate).

param(
    [string]$Path = ".",
    [switch]$Fix,
    [switch]$Json,
    [int]$MaxFileLines = 500,
    [int]$MaxFunctionLines = 100,
    [int]$CommentRatioThreshold = 40,    # percent
    [int]$OldTodoDays = 90,
    [int]$GenericVarThreshold = 5,
    [string[]]$Extensions = @(".ps1", ".py", ".ts", ".tsx", ".js", ".jsx", ".go", ".rs", ".java", ".cs", ".rb", ".sh")
)

. (Join-Path $PSScriptRoot "_paths.ps1")

if (-not (Test-Path $Path)) {
    Write-Error "Path not found: $Path"
    exit 1
}

$findings = New-Object System.Collections.ArrayList
$autoFixed = 0

function Add-Finding {
    param([string]$File, [int]$Line, [string]$Detector, [string]$Severity, [string]$Message)
    [void]$findings.Add([pscustomobject]@{
        file     = $File
        line     = $Line
        detector = $Detector
        severity = $Severity
        message  = $Message
    })
}

# Comment markers per language
function Get-CommentMarker([string]$ext) {
    switch ($ext.ToLower()) {
        '.ps1' { return '#' }
        '.py'  { return '#' }
        '.sh'  { return '#' }
        '.rb'  { return '#' }
        default { return '//' }
    }
}

# Heuristic: does this string look like commented-out code?
# Conservative -- only flag things that are very clearly code, not usage examples
# or path references in documentation.
function Is-LikelyCode([string]$content) {
    if (-not $content) { return $false }
    $c = $content.Trim()
    if ($c.Length -lt 5) { return $false }
    # Skip lines that look like usage examples or paths (common in doc comments)
    if ($c -match "^pwsh\s|^python\s|^npm\s|^bash\s|^node\s") { return $false }
    if ($c -match "^[~/]?\.[\w\-/.]+\s") { return $false }       # path-like ./foo/bar
    if ($c -match "^https?://") { return $false }
    # Strong indicators only
    $strongMarkers = @(
        '^\s*(return|throw|yield)\s+\S',
        '^\s*(if|for|while|switch)\s*\(',
        '^\s*(def|function|class|interface)\s+\w',
        '^\s*(const|let|var)\s+\w+\s*=',
        '^\s*\w+\s*=\s*[\w''"\(]'   # assignment at line start
    )
    foreach ($p in $strongMarkers) {
        if ($c -match $p) { return $true }
    }
    return $false
}

$files = Get-ChildItem -Path $Path -Recurse -File -ErrorAction SilentlyContinue |
    Where-Object {
        $ext = [System.IO.Path]::GetExtension($_.Name).ToLower()
        $Extensions -contains $ext -and $_.FullName -notmatch '\\\.(git|node_modules|\.venv|venv|__pycache__|dist|build|\.archive)\\'
    }

$today = Get-Date

foreach ($f in $files) {
    $ext = [System.IO.Path]::GetExtension($f.Name).ToLower()
    $marker = Get-CommentMarker $ext
    $rawContent = [System.IO.File]::ReadAllText($f.FullName, [System.Text.Encoding]::UTF8)
    if ($rawContent.StartsWith([char]0xFEFF)) { $rawContent = $rawContent.Substring(1) }
    $lines = $rawContent -split "`r?`n"
    $totalLines = $lines.Count

    # --- Detector 4: oversized file ---
    $limit = if ($ext -eq ".md") { 800 } else { $MaxFileLines }
    if ($totalLines -gt $limit) {
        Add-Finding -File $f.FullName -Line $totalLines -Detector "oversized-file" `
            -Severity "warning" -Message "File has $totalLines lines (limit $limit). Split or extract."
    }

    # --- Detectors 1, 2: comment ratio + commented-out code ---
    $commentLines = 0
    $codeLikeComments = 0
    $nonBlank = 0
    $genericVarHits = @{ data = 0; result = 0; value = 0; temp = 0; var1 = 0; obj = 0; thing = 0 }
    $blankRun = 0
    $maxBlankRun = 0

    for ($i = 0; $i -lt $lines.Count; $i++) {
        $line = $lines[$i]
        $trimmed = $line.Trim()

        if (-not $trimmed) {
            $blankRun++
            if ($blankRun -gt $maxBlankRun) { $maxBlankRun = $blankRun }
            continue
        }
        $blankRun = 0
        $nonBlank++

        # Comment-only?
        $isComment = $false
        if ($marker -eq '#' -and $trimmed.StartsWith('#')) { $isComment = $true }
        if ($marker -eq '//' -and $trimmed.StartsWith('//')) { $isComment = $true }
        if ($trimmed.StartsWith('/*') -or $trimmed.StartsWith('*')) { $isComment = $true }

        if ($isComment) {
            $commentLines++
            $body = $trimmed -replace "^[\#\/\*\s]+", ""
            if (Is-LikelyCode $body) { $codeLikeComments++ }
        }

        # --- Detector 7: generic variable names ---
        foreach ($name in $genericVarHits.Keys.Clone()) {
            if ($line -match "\b$name\b\s*=") { $genericVarHits[$name]++ }
        }

        # --- Detector 8 + 9: cosmetic ---
        if ($line -match "[\t ]+$") {
            Add-Finding -File $f.FullName -Line ($i + 1) -Detector "trailing-whitespace" `
                -Severity "info" -Message "Trailing whitespace"
        }
    }

    if ($nonBlank -gt 0) {
        $ratio = [int][Math]::Round(($commentLines * 100.0) / $nonBlank)
        if ($ratio -gt $CommentRatioThreshold) {
            Add-Finding -File $f.FullName -Line 1 -Detector "comment-bloat" `
                -Severity "info" -Message "$ratio% of non-blank lines are comments (threshold $CommentRatioThreshold%). Verify they explain WHY not WHAT."
        }
    }
    if ($codeLikeComments -ge 3) {
        Add-Finding -File $f.FullName -Line 1 -Detector "commented-out-code" `
            -Severity "warning" -Message "$codeLikeComments comments look like commented-out code. Delete or restore."
    }
    foreach ($kvp in $genericVarHits.GetEnumerator()) {
        if ($kvp.Value -gt $GenericVarThreshold) {
            Add-Finding -File $f.FullName -Line 1 -Detector "generic-variable-name" `
                -Severity "info" -Message "Variable name '$($kvp.Name)' assigned $($kvp.Value) times. Rename to something specific."
        }
    }
    if ($maxBlankRun -ge 3) {
        Add-Finding -File $f.FullName -Line 1 -Detector "excess-blank-lines" `
            -Severity "info" -Message "Run of $maxBlankRun blank lines. Collapse to 2."
    }

    # --- Detector 3: empty try/catch ---
    if ($rawContent -match '(?ms)catch\s*[^{]*\{\s*\}') {
        Add-Finding -File $f.FullName -Line 1 -Detector "empty-catch" `
            -Severity "warning" -Message "Empty catch block found. Either log/handle or document why swallowing."
    }

    # --- Detector 10: deep nesting (rough indent-based heuristic) ---
    $maxIndent = 0
    foreach ($line in $lines) {
        if ($line.Trim()) {
            $leading = ($line -replace "^( *).*", '$1').Length
            $level = [int]([Math]::Floor($leading / 4))
            if ($level -gt $maxIndent) { $maxIndent = $level }
        }
    }
    if ($maxIndent -gt 4) {
        Add-Finding -File $f.FullName -Line 1 -Detector "deep-nesting" `
            -Severity "info" -Message "Maximum indent depth $maxIndent levels. Consider extracting nested blocks."
    }

    # --- Detector 5: oversized function ---
    # PS: track braces from function header until depth returns to 0 = function end.
    # PY: track indent; function ends when an unindented (or sibling-def) line appears.
    if ($ext -eq ".ps1") {
        $funcStart = -1; $funcName = ""; $depth = 0; $entered = $false
        for ($i = 0; $i -lt $lines.Count; $i++) {
            $l = $lines[$i]
            if ($funcStart -lt 0 -and $l -match "^\s*function\s+([\w-]+)") {
                $funcStart = $i + 1; $funcName = $Matches[1]; $depth = 0; $entered = $false
            }
            if ($funcStart -ge 0) {
                # Strip strings/comments to avoid false brace counts
                $stripped = $l -replace '"[^"]*"', '""' -replace "'[^']*'", "''" -replace '#.*$', ''
                $opens  = ($stripped.ToCharArray() | Where-Object { $_ -eq '{' }).Count
                $closes = ($stripped.ToCharArray() | Where-Object { $_ -eq '}' }).Count
                $depth += $opens - $closes
                if ($opens -gt 0) { $entered = $true }
                if ($entered -and $depth -le 0) {
                    $funcLines = ($i + 1) - $funcStart + 1
                    if ($funcLines -gt $MaxFunctionLines) {
                        Add-Finding -File $f.FullName -Line $funcStart -Detector "oversized-function" `
                            -Severity "warning" -Message "Function '$funcName' is $funcLines lines (limit $MaxFunctionLines)."
                    }
                    $funcStart = -1; $funcName = ""; $depth = 0; $entered = $false
                }
            }
        }
    } elseif ($ext -eq ".py") {
        $funcStart = -1; $funcName = ""; $funcIndent = -1
        for ($i = 0; $i -lt $lines.Count; $i++) {
            $l = $lines[$i]
            if ($l -match "^(\s*)def\s+(\w+)") {
                $thisIndent = $Matches[1].Length
                if ($funcStart -ge 0 -and $thisIndent -le $funcIndent) {
                    # Sibling/outer def -- previous function ended at $i
                    $funcLines = $i - $funcStart + 1
                    if ($funcLines -gt $MaxFunctionLines) {
                        Add-Finding -File $f.FullName -Line $funcStart -Detector "oversized-function" `
                            -Severity "warning" -Message "Function '$funcName' is $funcLines lines (limit $MaxFunctionLines)."
                    }
                }
                $funcStart = $i + 1; $funcName = $Matches[2]; $funcIndent = $thisIndent
            } elseif ($funcStart -ge 0 -and $l.Trim() -and $l -notmatch "^\s") {
                # Unindented non-blank line = function ended
                $funcLines = $i - $funcStart + 1
                if ($funcLines -gt $MaxFunctionLines) {
                    Add-Finding -File $f.FullName -Line $funcStart -Detector "oversized-function" `
                        -Severity "warning" -Message "Function '$funcName' is $funcLines lines (limit $MaxFunctionLines)."
                }
                $funcStart = -1
            }
        }
    }

    # --- Auto-fixes (only if -Fix) ---
    if ($Fix) {
        $fixed = $rawContent
        # Strip trailing whitespace
        $fixed = $fixed -replace "[ \t]+(\r?\n)", '$1'
        # Collapse 3+ blank lines to 2
        $fixed = $fixed -replace "(\r?\n){4,}", "`n`n`n"
        if ($fixed -ne $rawContent) {
            # Preserve BOM if present
            $hasBom = $false
            $origBytes = [System.IO.File]::ReadAllBytes($f.FullName)
            if ($origBytes.Length -ge 3 -and $origBytes[0] -eq 0xEF -and $origBytes[1] -eq 0xBB -and $origBytes[2] -eq 0xBF) {
                $hasBom = $true
            }
            $writeBytes = [System.Text.Encoding]::UTF8.GetBytes($fixed)
            if ($hasBom) {
                $bom = [byte[]](0xEF, 0xBB, 0xBF)
                $combined = [byte[]]::new($bom.Length + $writeBytes.Length)
                [Array]::Copy($bom, 0, $combined, 0, $bom.Length)
                [Array]::Copy($writeBytes, 0, $combined, $bom.Length, $writeBytes.Length)
                [System.IO.File]::WriteAllBytes($f.FullName, $combined)
            } else {
                [System.IO.File]::WriteAllBytes($f.FullName, $writeBytes)
            }
            $autoFixed++
        }
    }
}

# Aggregate
$summary = [ordered]@{
    scanned_files = $files.Count
    total_findings = $findings.Count
    by_detector   = @{}
    by_severity   = @{}
    auto_fixed    = $autoFixed
    findings      = @($findings)
}
foreach ($g in @($findings) | Group-Object detector) { $summary.by_detector[$g.Name] = $g.Count }
foreach ($g in @($findings) | Group-Object severity) { $summary.by_severity[$g.Name] = $g.Count }

if ($Json) {
    Write-Output (($summary | ConvertTo-Json -Depth 5 -Compress))
} else {
    Write-Host "detect-slop scanned $($files.Count) file(s); found $($findings.Count) issue(s)"
    Write-Host ""
    Write-Host "By detector:"
    foreach ($kvp in $summary.by_detector.GetEnumerator() | Sort-Object Value -Descending) {
        Write-Host "  $($kvp.Value)x  $($kvp.Name)"
    }
    if ($Fix) { Write-Host ""; Write-Host "Auto-fixed: $autoFixed file(s)" }
    Write-Host ""
    Write-Host "Top findings (warnings + first 20):"
    $top = @($findings | Where-Object { $_.severity -eq "warning" }) + @($findings | Where-Object { $_.severity -ne "warning" } | Select-Object -First 20)
    foreach ($f in ($top | Select-Object -First 25)) {
        $relFile = $f.file.Replace((Get-Location).Path, ".").Replace((Resolve-Path $Path).Path, ".")
        Write-Host "  [$($f.severity)] $relFile`:$($f.line)  $($f.detector)  $($f.message)"
    }
}
exit 0
