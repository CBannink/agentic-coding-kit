#!/usr/bin/env pwsh
# auto-apply-reflect.ps1 -- tiered auto-application of reflection findings.
#
# Runs from post-session.ps1 after detectors have appended to reflections.md.
# Auto-applies findings in SAFE buckets only; gates everything else for /reflect.
#
# Safe auto-apply buckets:
#   1. specialist-memory accretion -- append "in THIS repo, X is intentional"
#      to .kit/context/agent-memory/{role}.md when same finding observed 3+ times
#      and was [SUPERSEDED] or marked false-positive each time.
#   2. conventions.md refinements -- update detected git/arch patterns when
#      observed PR merges contradict the existing detection.
#   3. per-tier spawn-budget tweaks -- repo-scoped only (.kit/workflows/build.md),
#      never global ~/.agents/.
#
# All auto-applied changes are snapshotted to ~/.agents/context/auto-applied-snapshots/
# Next session's pre-session.ps1 measures verification-pass-rate delta; if a snap
# correlates with a regression, it auto-reverts.
#
# Unsafe (still gated for /reflect):
#   - Slash command body restructuring
#   - Tool/hook PowerShell logic
#   - Global agent prompt rewrites
#
# Exit: 0 = applied N changes (or 0); 1 = error (does NOT block session-end).

param(
    [string]$RepoRoot = (Get-Location).Path,
    [int]$ConsistencyThreshold = 3,
    [switch]$DryRun
)

. (Join-Path $PSScriptRoot "_paths.ps1")

$reflectionsPath = Join-Path $env:USERPROFILE ".agents/context/reflections.md"
$snapshotsDir    = Join-Path $env:USERPROFILE ".agents/context/auto-applied-snapshots"
$auditPath       = Join-Path $env:USERPROFILE ".agents/context/auto-applied.md"

if (-not (Test-Path $reflectionsPath)) {
    Write-Output "auto-apply-reflect: no reflections.md, nothing to do"
    exit 0
}

New-Item -ItemType Directory -Path $snapshotsDir -Force | Out-Null

$content = Get-Content $reflectionsPath -Raw -Encoding UTF8
$entries = $content -split "(?m)^## " | Where-Object { $_.Trim() } | ForEach-Object { "## $_" }

# Bucket 1: specialist-memory accretion -- find findings repeated 3+ times by signature.
$signaturePattern = '(?m)^- (?:\[SUPERSEDED\]|\[FALSE-POSITIVE\]) (\S+:\d+:\S+) by (\S+)'
$signatureCounts = @{}
foreach ($e in $entries) {
    foreach ($m in [regex]::Matches($e, $signaturePattern)) {
        $sig = "$($m.Groups[2].Value)|$($m.Groups[1].Value)"
        if (-not $signatureCounts.ContainsKey($sig)) { $signatureCounts[$sig] = 0 }
        $signatureCounts[$sig]++
    }
}

$applied = [System.Collections.ArrayList]::new()

foreach ($sig in $signatureCounts.Keys) {
    if ($signatureCounts[$sig] -lt $ConsistencyThreshold) { continue }
    $parts = $sig -split '\|', 2
    $role = $parts[0]
    $finding = $parts[1]
    $memoryPath = Join-Path $RepoRoot ".kit/context/agent-memory/$role.md"
    if (-not (Test-Path (Split-Path $memoryPath))) { continue }

    $note = "- AUTO-APPLIED $(Get-Date -Format 'yyyy-MM-dd'): finding `"$finding`" superseded $($signatureCounts[$sig])x in this repo. Skip flagging unless context changes."
    $existing = if (Test-Path $memoryPath) { Get-Content $memoryPath -Raw -Encoding UTF8 } else { "# $role memory (this repo)`n`n## Auto-applied dampeners`n" }
    if ($existing -match [regex]::Escape($finding)) { continue }  # already noted

    if (-not $DryRun) {
        $snapPath = Join-Path $snapshotsDir "$(Get-Date -Format 'yyyyMMdd-HHmmss')_$role.md"
        Set-Content -Path $snapPath -Value $existing -Encoding utf8 -NoNewline
        $new = if ($existing -match "## Auto-applied dampeners") { $existing + "`n$note" } else { $existing + "`n`n## Auto-applied dampeners`n$note" }
        [System.IO.File]::WriteAllText($memoryPath, $new, [System.Text.UTF8Encoding]::new($false))
    }
    [void]$applied.Add("specialist-memory: $role <- $finding ($($signatureCounts[$sig])x)")
}

# Bucket 2: prompt pattern accumulation -- additive reflections with count >= 2
# and a valid Suggested-target file get a marked block appended.
# Parses entries in the same way as auto-consolidate.ps1 and prompt-improver.ps1.

function Parse-AdditiveEntries([string]$path) {
    if (-not (Test-Path $path)) { return @() }
    $out = @()
    $lines = Get-Content $path -Encoding UTF8
    $cur = $null
    for ($i = 0; $i -lt $lines.Count; $i++) {
        $l = $lines[$i]
        if ($l -match "^- \[(\d{4}-\d{2}-\d{2})\].*?\[class:([^\]]+)\]") {
            if ($cur) { $out += $cur }
            $cnt = 1
            if ($l -match "\[seen (\d+)x\]") { $cnt = [int]$Matches[1] }
            $cur = [pscustomobject]@{ class=$Matches[2]; pattern=""; target=""; count=$cnt }
        } elseif ($cur) {
            if ($l -match "^\s*Pattern:\s*(.*)$")               { $cur.pattern = $Matches[1].Trim() }
            elseif ($l -match "^\s*Suggested target:\s*(.*)$")  { $cur.target  = $Matches[1].Trim() }
            elseif ($l -match "^- \[" -or $l -match "^##\s")   { $out += $cur; $cur = $null; $i-- }
            elseif ($l.Trim() -eq "" -and $cur.pattern)        { $out += $cur; $cur = $null }
        }
    }
    if ($cur) { $out += $cur }
    return @($out | Where-Object { $_.class -eq "additive" -and $_.count -ge 2 -and $_.target })
}

$globalReflect = Join-Path $env:USERPROFILE ".agents/context/reflections.md"
$repoReflect   = Join-Path $RepoRoot ".kit/context/reflections.md"

foreach ($rPath in @($globalReflect, $repoReflect)) {
    foreach ($entry in (Parse-AdditiveEntries $rPath)) {
        # Resolve target path (expand ~ and relative paths)
        $tRaw = $entry.target
        $tPath = $tRaw -replace "^~", $env:USERPROFILE
        if (-not [System.IO.Path]::IsPathRooted($tPath)) {
            $tPath = Join-Path $RepoRoot $tPath
        }
        if (-not (Test-Path $tPath)) { continue }

        # Skip if pattern already present in target
        $targetContent = Get-Content $tPath -Raw -Encoding UTF8
        $checkStr = $entry.pattern.Substring(0, [Math]::Min(60, $entry.pattern.Length))
        if ($targetContent -match [regex]::Escape($checkStr)) { continue }

        $date = Get-Date -Format "yyyy-MM-dd"
        $block = "`n<!-- auto-reflected prompt improvement ($date) -->`n$($entry.pattern)`n"

        if (-not $DryRun) {
            $snapPath = Join-Path $snapshotsDir "$(Get-Date -Format 'yyyyMMdd-HHmmss')_prompt-patch.md"
            Set-Content -Path $snapPath -Value $targetContent -Encoding utf8 -NoNewline
            [System.IO.File]::AppendAllText($tPath, $block, [System.Text.UTF8Encoding]::new($false))
        }
        [void]$applied.Add("prompt-pattern: $tPath <- $($entry.pattern.Substring(0,[Math]::Min(60,$entry.pattern.Length))) ($($entry.count)x)")
    }
}

# Audit log
if ($applied.Count -gt 0 -and -not $DryRun) {
    $stamp = Get-Date -Format 'o'
    $logEntry = "## $stamp`n" + (($applied | ForEach-Object { "- $_" }) -join "`n") + "`n`n"
    Add-Content -Path $auditPath -Value $logEntry -Encoding utf8
}

Write-Output "auto-apply-reflect: applied=$($applied.Count) threshold=$ConsistencyThreshold dry-run=$DryRun"
foreach ($a in $applied) { Write-Output "  - $a" }
exit 0
