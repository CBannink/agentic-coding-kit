#!/usr/bin/env pwsh
# prompt-improver.ps1 -- analyze accumulated reflections and produce concrete prompt patches.
#
# Reads reflections.md (repo or global), groups by class, and applies improvements:
#   - class=additive  count>=2: append patch to target file directly
#   - class=gating    count>=3: write proposal file to ~/.agents/proposals/ for review
#   - class=noise     count>=2: append suppression rule to .kit/context/agent-memory/{role}.md
#   - class=correction count>=2: treat as additive, append to global instructions
#
# All applied improvements are tracked in ~/.agents/context/prompt-improvements.md
#
# Exit: 0 = success; 1 = error.

param(
    [string]$RepoRoot = (Get-Location).Path,
    [ValidateSet("repo","global")]
    [string]$Scope = "repo",
    [switch]$DryRun,
    [switch]$Json
)

. (Join-Path $PSScriptRoot "_paths.ps1")

$improvementsLog = Join-Path $script:AgentsRoot "context/prompt-improvements.md"
$proposalsDir    = Join-Path $script:AgentsRoot "proposals"
$snapshotsDir    = Join-Path $script:AgentsRoot "context/auto-applied-snapshots"

if ($Scope -eq "repo") {
    $reflectionsPath = Join-Path $RepoRoot ".kit/context/reflections.md"
} else {
    $reflectionsPath = Join-Path $script:AgentsRoot "context/reflections.md"
}

$result = [ordered]@{
    applied    = 0
    proposed   = 0
    suppressed = 0
    skipped    = 0
    improvements = [System.Collections.ArrayList]::new()
}

if (-not (Test-Path $reflectionsPath)) {
    if ($Json) { Write-Output ($result | ConvertTo-Json -Depth 5 -Compress) }
    else { Write-Output "prompt-improver: no reflections.md at $reflectionsPath, nothing to do" }
    exit 0
}

if (-not $DryRun) {
    foreach ($d in @($proposalsDir, $snapshotsDir, (Split-Path $improvementsLog))) {
        New-Item -ItemType Directory -Path $d -Force | Out-Null
    }
}

# --- Parse entries (reuse same pattern as auto-consolidate.ps1) ---------------
function Parse-Entries([string]$path) {
    if (-not (Test-Path $path)) { return @() }
    $entries = @()
    $lines = Get-Content $path -Encoding UTF8
    $current = $null
    for ($i = 0; $i -lt $lines.Count; $i++) {
        $l = $lines[$i]
        if ($l -match "^- \[(\d{4}-\d{2}-\d{2})\].*?\[class:([^\]]+)\]") {
            if ($current) { $entries += $current }
            $count = 1
            if ($l -match "\[seen (\d+)x\]") { $count = [int]$Matches[1] }
            $current = [pscustomobject]@{
                date     = $Matches[1]
                class    = $Matches[2]
                header   = $l
                pattern  = ""
                evidence = ""
                target   = ""
                count    = $count
            }
        } elseif ($current) {
            if ($l -match "^\s*Pattern:\s*(.*)$")            { $current.pattern  = $Matches[1].Trim() }
            elseif ($l -match "^\s*Evidence:\s*(.*)$")       { $current.evidence = $Matches[1].Trim() }
            elseif ($l -match "^\s*Suggested target:\s*(.*)$") { $current.target = $Matches[1].Trim() }
            elseif ($l -match "^- \[" -or $l -match "^##\s") {
                $entries += $current; $current = $null; $i--
            } elseif ($l.Trim() -eq "" -and $current.pattern) {
                $entries += $current; $current = $null
            }
        }
    }
    if ($current) { $entries += $current }
    return @($entries | Where-Object { $_.pattern })
}

function Resolve-TargetPath([string]$rawTarget, [string]$repoRoot) {
    if (-not $rawTarget) { return "" }
    # Expand ~ to $HOME
    $t = $rawTarget -replace "^~", $HOME
    if (-not [System.IO.Path]::IsPathRooted($t)) {
        $t = Join-Path $repoRoot $t
    }
    return $t
}

function Snapshot-File([string]$targetPath) {
    if (-not (Test-Path $targetPath)) { return }
    $stamp = Get-Date -Format "yyyyMMdd-HHmmss"
    $leaf = [System.IO.Path]::GetFileNameWithoutExtension($targetPath)
    $snapPath = Join-Path $snapshotsDir "${stamp}_${leaf}.md"
    Copy-Item -Path $targetPath -Destination $snapPath -Force
}

function Append-ToTarget([string]$targetPath, [string]$block) {
    [System.IO.File]::AppendAllText($targetPath, $block, [System.Text.UTF8Encoding]::new($false))
}

function Already-Applied([string]$targetPath, [string]$pattern) {
    if (-not (Test-Path $targetPath)) { return $false }
    $content = Get-Content $targetPath -Raw -Encoding UTF8
    return $content -match [regex]::Escape($pattern.Substring(0, [Math]::Min(60, $pattern.Length)))
}

function Log-Improvement([string]$type, [string]$target, [string]$action, [string]$pattern, [string]$proposalId = "") {
    $date = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
    $logLine = "## $date | $type | $action`n- Target: $target`n- Pattern: $pattern"
    if ($proposalId) { $logLine += "`n- Proposal: $proposalId" }
    $logLine += "`n`n"
    if (-not $DryRun) {
        Add-Content -Path $improvementsLog -Value $logLine -Encoding utf8
    }
}

# --- Main loop ----------------------------------------------------------------
$entries = Parse-Entries $reflectionsPath

# Group by (class, pattern) -- entries parsed from file may already be deduped
# by auto-consolidate, but handle both deduped and raw form.
$grouped = $entries | Group-Object -Property { "$($_.class)|$($_.pattern)" }

foreach ($g in $grouped) {
    $e = $g.Group | Sort-Object count -Descending | Select-Object -First 1
    # Sum counts across duplicates that may not yet be deduped
    $totalCount = ($g.Group | Measure-Object -Property count -Sum).Sum

    $targetRaw = $e.target
    $targetPath = Resolve-TargetPath $targetRaw $RepoRoot
    $class = $e.class
    $pattern = $e.pattern
    $evidence = $e.evidence

    # ---- additive: append to target file directly (count >= 2) ---------------
    if (($class -eq "additive" -or $class -eq "correction") -and $totalCount -ge 2) {
        if (-not $targetPath) {
            $result.skipped++
            [void]$result.improvements.Add([ordered]@{type=$class; target="(none)"; action="skipped-no-target"; pattern=$pattern})
            continue
        }
        if (-not (Test-Path $targetPath)) {
            $result.skipped++
            [void]$result.improvements.Add([ordered]@{type=$class; target=$targetPath; action="skipped-target-missing"; pattern=$pattern})
            continue
        }
        if (Already-Applied $targetPath $pattern) {
            $result.skipped++
            [void]$result.improvements.Add([ordered]@{type=$class; target=$targetPath; action="skipped-already-present"; pattern=$pattern})
            continue
        }
        $date = Get-Date -Format "yyyy-MM-dd"
        $block = "`n<!-- auto-reflected prompt improvement ($date) -->`n$pattern`n"
        if (-not $DryRun) {
            Snapshot-File $targetPath
            Append-ToTarget $targetPath $block
            Log-Improvement $class $targetPath "appended" $pattern
        }
        $result.applied++
        [void]$result.improvements.Add([ordered]@{type=$class; target=$targetPath; action="appended"; pattern=$pattern})
        continue
    }

    # ---- gating: write proposal (count >= 3) ----------------------------------
    if ($class -eq "gating" -and $totalCount -ge 3) {
        $proposalId = "proposal-$(Get-Date -Format 'yyyyMMdd-HHmmss')-$([System.IO.Path]::GetRandomFileName().Split('.')[0])"
        $proposalFile = Join-Path $proposalsDir "$proposalId.md"
        $proposalContent = @"
# Prompt Improvement Proposal: $proposalId

Generated: $(Get-Date -Format 'o')
Class: gating
Count: $totalCount
Source: $reflectionsPath

## Pattern

$pattern

## Evidence

$evidence

## Suggested target

$targetRaw

## Action required

Review and manually apply this workflow/gating change. It was observed $totalCount times
and qualifies for promotion but requires human judgment before modifying workflow contracts.

Apply by editing the target file above and removing this proposal file when done.
"@
        if (-not $DryRun) {
            [System.IO.File]::WriteAllText($proposalFile, $proposalContent, [System.Text.UTF8Encoding]::new($false))
            $effectiveTarget = if ($targetPath) { $targetPath } else { $targetRaw }
            Log-Improvement $class $effectiveTarget "proposed" $pattern $proposalId
        }
        $result.proposed++
        $effectiveTarget = if ($targetPath) { $targetPath } else { $targetRaw }
        [void]$result.improvements.Add([ordered]@{type=$class; target=$effectiveTarget; action="proposed"; proposal_id=$proposalId; pattern=$pattern})
        continue
    }

    # ---- noise: append suppression to agent-memory (count >= 2) ---------------
    if ($class -eq "noise" -and $totalCount -ge 2) {
        # Derive role from evidence field (emitter hints) or target path
        $role = "unattributed"
        $emitterHints = @(
            'code-quality-reviewer','security-reviewer','modularity-expert',
            'adversarial-reviewer','final-verifier','spec-reviewer','qa-reviewer',
            'pr-reviewer','workflow-reviewer','workflow-skeptic','ux-driver','ui-driver'
        )
        foreach ($hint in $emitterHints) {
            if ($evidence -match [regex]::Escape($hint) -or $targetRaw -match [regex]::Escape($hint)) {
                $role = $hint; break
            }
        }
        $memPath = Join-Path $RepoRoot ".kit/context/agent-memory/$role.md"
        $note = "- AUTO-SUPPRESSED $(Get-Date -Format 'yyyy-MM-dd'): noise pattern observed ${totalCount}x -- `"$($pattern.Substring(0,[Math]::Min(120,$pattern.Length)))`". Suppress unless context changes."
        $existing = if (Test-Path $memPath) { Get-Content $memPath -Raw -Encoding UTF8 } else { "# $role memory (this repo)`n`n" }
        if ($existing -match [regex]::Escape($pattern.Substring(0, [Math]::Min(60,$pattern.Length)))) {
            $result.skipped++
            [void]$result.improvements.Add([ordered]@{type=$class; target=$memPath; action="skipped-already-present"; pattern=$pattern})
            continue
        }
        if (-not $DryRun) {
            $dir = Split-Path $memPath
            New-Item -ItemType Directory -Path $dir -Force | Out-Null
            Snapshot-File $memPath
            $new = if ($existing -match "## Auto-applied suppression") {
                $existing + "`n$note"
            } else {
                $existing + "`n## Auto-applied suppression`n$note"
            }
            [System.IO.File]::WriteAllText($memPath, $new, [System.Text.UTF8Encoding]::new($false))
            Log-Improvement $class $memPath "suppressed" $pattern
        }
        $result.suppressed++
        [void]$result.improvements.Add([ordered]@{type=$class; target=$memPath; action="suppressed"; pattern=$pattern})
        continue
    }

    # Did not meet any threshold
    $result.skipped++
    $effectiveTarget = if ($targetPath) { $targetPath } else { $targetRaw }
    [void]$result.improvements.Add([ordered]@{type=$class; target=$effectiveTarget; action="skipped-below-threshold"; pattern=$pattern; count=$totalCount})
}

if ($Json) {
    Write-Output ($result | ConvertTo-Json -Depth 5 -Compress)
} else {
    Write-Output "prompt-improver: applied=$($result.applied) proposed=$($result.proposed) suppressed=$($result.suppressed) skipped=$($result.skipped) dry-run=$DryRun"
    foreach ($i in $result.improvements) {
        $line = "  [$($i.type)] $($i.action)"
        if ($i.target) { $line += " -> $($i.target)" }
        if ($i.proposal_id) { $line += " (proposal: $($i.proposal_id))" }
        Write-Output $line
    }
}

exit 0
