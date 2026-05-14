#!/usr/bin/env pwsh
# edit-with-lint.ps1
# Apply a single file edit with linter validation. Refuses to commit changes
# that don't pass the file's linter -- catches syntax errors at the tool layer
# before they hit the test loop.
#
# Pattern from SWE-agent: "the linter runs when an edit command is issued, and
# does not let the edit command go through if the code isn't syntactically
# correct." Single highest-cited specific enforcement pattern in the literature.
#
# Usage:
#   pwsh edit-with-lint.ps1 -Path src/auth.ts -Find "old code" -Replace "new code"
#   pwsh edit-with-lint.ps1 -Path src/auth.ts -Find "x" -Replace "y" -All
#   pwsh edit-with-lint.ps1 -Path file.go -LintCommand "gofmt -d {file}" -Find "..." -Replace "..."
#
# Behavior:
#   1. Read the file. Refuse if Find matches 0 times (not found) or >1 times
#      (ambiguous -- agent must disambiguate, unless -All flag).
#   2. Apply the replacement to a temp file.
#   3. Auto-detect the linter by file extension (overridable via -LintCommand).
#   4. Run the linter on the temp file.
#   5. If lint passes: atomic move temp -> original, return success JSON.
#   6. If lint fails: discard temp, return lint output JSON for the agent.
#
# Exit codes: 0 = applied, 1 = refused (find ambiguous/missing), 2 = lint failed (reverted).

param(
    [Parameter(Mandatory)][string]$Path,
    [Parameter(Mandatory)][string]$Find,
    [Parameter(Mandatory)][string]$Replace,
    [string]$LintCommand = "",
    [string]$Reason = "",
    [switch]$All,
    [switch]$NoLint,
    [switch]$Json
)

. (Join-Path $PSScriptRoot "_paths.ps1")

if (-not (Test-Path $Path)) {
    $err = "File not found: $Path"
    if ($Json) { Write-Output (@{ applied = $false; error = $err } | ConvertTo-Json -Compress) }
    else       { Write-Error $err }
    exit 1
}

# Read original (preserves original encoding via byte-level read)
$origBytes = [System.IO.File]::ReadAllBytes($Path)
$hasBom = ($origBytes.Length -ge 3 -and $origBytes[0] -eq 0xEF -and $origBytes[1] -eq 0xBB -and $origBytes[2] -eq 0xBF)
$origText = if ($hasBom) {
    [System.Text.Encoding]::UTF8.GetString($origBytes, 3, $origBytes.Length - 3)
} else {
    [System.Text.Encoding]::UTF8.GetString($origBytes)
}

# Count occurrences of Find
$matchCount = ($origText.Length - $origText.Replace($Find, '').Length) / [Math]::Max(1, $Find.Length)
$matchCount = [int][Math]::Round($matchCount)

if ($matchCount -eq 0) {
    $err = "Find string not found in $Path. The agent must read the file and use exact existing content."
    if ($Json) { Write-Output (@{ applied = $false; reason = "find_not_found"; error = $err } | ConvertTo-Json -Compress) }
    else       { Write-Error $err }
    exit 1
}
if ($matchCount -gt 1 -and -not $All) {
    $err = "Find string matches $matchCount times in $Path -- ambiguous. Provide more surrounding context to make it unique, or pass -All to replace every occurrence."
    if ($Json) { Write-Output (@{ applied = $false; reason = "find_ambiguous"; matches = $matchCount; error = $err } | ConvertTo-Json -Compress) }
    else       { Write-Error $err }
    exit 1
}

# Apply replacement
$newText = if ($All) {
    $origText.Replace($Find, $Replace)
} else {
    # First-match replacement (since count = 1, .Replace() acts the same anyway, but explicit)
    $idx = $origText.IndexOf($Find)
    $origText.Substring(0, $idx) + $Replace + $origText.Substring($idx + $Find.Length)
}

# Hashes for the audit trail
function Get-Sha256([string]$text) {
    $bytes = [System.Text.Encoding]::UTF8.GetBytes($text)
    $hash = [System.Security.Cryptography.SHA256]::Create().ComputeHash($bytes)
    return ([System.BitConverter]::ToString($hash) -replace '-', '').Substring(0, 16)
}
$beforeSha = Get-Sha256 $origText
$afterSha  = Get-Sha256 $newText

# Write to a temp file for linting
$tempPath = "$Path.tmp.$(Get-Random)"
$writeBytes = [System.Text.Encoding]::UTF8.GetBytes($newText)
if ($hasBom) {
    $bom = [byte[]](0xEF, 0xBB, 0xBF)
    $combined = [byte[]]::new($bom.Length + $writeBytes.Length)
    [Array]::Copy($bom, 0, $combined, 0, $bom.Length)
    [Array]::Copy($writeBytes, 0, $combined, $bom.Length, $writeBytes.Length)
    [System.IO.File]::WriteAllBytes($tempPath, $combined)
} else {
    [System.IO.File]::WriteAllBytes($tempPath, $writeBytes)
}

# Resolve linter
function Get-LinterFor([string]$filePath, [string]$override) {
    if ($override) { return $override }
    if ($NoLint)   { return "" }
    $ext = [System.IO.Path]::GetExtension($filePath).ToLower()
    switch ($ext) {
        '.ts'   { return "node --check {file}" }   # JS/TS syntax check (basic but free, no deps)
        '.tsx'  { return "node --check {file}" }
        '.js'   { return "node --check {file}" }
        '.jsx'  { return "node --check {file}" }
        '.mjs'  { return "node --check {file}" }
        '.cjs'  { return "node --check {file}" }
        '.py'   { return "python -m py_compile {file}" }
        '.json' { return "" }   # python -m json.tool chokes on UTF-8 BOM; skip for now (tests catch real issues)
        '.sh'   { return "bash -n {file}" }
        '.bash' { return "bash -n {file}" }
        '.go'   { return "gofmt -e {file}" }
        '.rs'   { return "" }   # rustfmt --check on a single file is wrong; cargo check is too heavy
        '.ps1'  { return "" }   # PS parses on dot-source which we don't do here
        default { return "" }
    }
}

$lintCmd = Get-LinterFor -filePath $Path -override $LintCommand
$lintStatus = "skipped"
$lintOutput = ""
$lintExit = 0

if ($lintCmd) {
    $resolvedCmd = $lintCmd.Replace("{file}", "`"$tempPath`"")
    $psi = New-Object System.Diagnostics.ProcessStartInfo
    $psi.FileName = "cmd.exe"
    $psi.Arguments = "/c $resolvedCmd"
    $psi.RedirectStandardOutput = $true
    $psi.RedirectStandardError  = $true
    $psi.UseShellExecute = $false
    $psi.CreateNoWindow  = $true
    try {
        $proc = [System.Diagnostics.Process]::Start($psi)
        $outTask = $proc.StandardOutput.ReadToEndAsync()
        $errTask = $proc.StandardError.ReadToEndAsync()
        $proc.WaitForExit(30000) | Out-Null
        $proc.WaitForExit()
        $lintExit = $proc.ExitCode
        $lintOutput = ($outTask.Result + "`n" + $errTask.Result).Trim()
        # Distinguish "linter not installed" from "lint failed". A missing binary
        # should NOT cause us to revert a valid edit.
        $notFoundSignals = @(
            "is not recognized as",
            "command not found",
            "no such file or directory",
            "execvpe",
            "cannot find the path"
        )
        $isNotFound = $false
        foreach ($sig in $notFoundSignals) {
            if ($lintOutput -match [regex]::Escape($sig)) { $isNotFound = $true; break }
        }
        if ($lintExit -eq 9009 -or $lintExit -eq 127 -or $isNotFound) {
            $lintStatus = "skipped"
            $lintOutput = "Linter binary not available: $lintCmd. Install it for syntax-validation; edit applied without lint."
        } elseif ($lintExit -eq 0) {
            $lintStatus = "pass"
        } else {
            $lintStatus = "fail"
        }
    } catch {
        # Failure to even START the process = linter not present. Don't revert.
        $lintStatus = "skipped"
        $lintOutput = "Linter could not be executed: $($_.Exception.Message)"
        $lintExit = -1
    }
}

# Decide: commit or revert
$applied = $false
$reverted = $false
if ($lintStatus -eq "pass" -or $lintStatus -eq "skipped") {
    Move-Item -Force $tempPath $Path
    $applied = $true
} else {
    Remove-Item -Force $tempPath -ErrorAction SilentlyContinue
    $reverted = $true
}

$result = [ordered]@{
    path         = $Path
    applied      = $applied
    reverted     = $reverted
    lint_status  = $lintStatus
    lint_command = $lintCmd
    lint_output  = $lintOutput
    lint_exit    = $lintExit
    matches      = $matchCount
    before_sha   = $beforeSha
    after_sha    = $afterSha
    reason       = $Reason
    ran_at       = (Get-Date -Format "o")
}

if ($Json) {
    Write-Output ($result | ConvertTo-Json -Compress -Depth 4)
} else {
    Write-Output ($result | ConvertTo-Json -Depth 4)
}

if ($applied) { exit 0 } else { exit 2 }
