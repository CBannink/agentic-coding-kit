#!/usr/bin/env pwsh
# kit-health-digest.ps1 -- weekly maintainer-facing kit health summary.
#
# Surfaces accumulated reflection / auto-apply trends so the manual /reflect
# step has something to act on instead of being theoretical. Runs at most
# once every 7 days (gated by ~/.agents/context/.last-digest); silent when
# nothing actionable.
#
# Wired from post-session.ps1 Phase 2d. Read-only -- never writes prompts.
#
# Output: Markdown digest to stdout, plus full digest archived at
# ~/.agents/context/digests/<date>.md for trend review.

param(
    [int]$WindowDays = 30,
    [int]$IntervalDays = 7,
    [switch]$Force,
    [string]$RepoRoot = (Get-Location).Path
)

. (Join-Path $PSScriptRoot "_paths.ps1")

$lastDigestMarker = Join-Path $env:USERPROFILE ".agents/context/.last-digest"
$digestArchive    = Join-Path $env:USERPROFILE ".agents/context/digests"
$autoAppliedLog   = Join-Path $env:USERPROFILE ".agents/context/auto-applied.md"
$emitterStatsTool = Join-Path $PSScriptRoot "reflection-emitter-stats.ps1"

# Cadence gate -- silent unless interval elapsed (or -Force)
if (-not $Force -and (Test-Path $lastDigestMarker)) {
    $last = Get-Item $lastDigestMarker
    if ((New-TimeSpan -Start $last.LastWriteTime -End (Get-Date)).Days -lt $IntervalDays) {
        exit 0
    }
}

New-Item -ItemType Directory -Path $digestArchive -Force | Out-Null

$now = Get-Date
$lines = [System.Collections.ArrayList]::new()
[void]$lines.Add("# Kit health digest -- $($now.ToString('yyyy-MM-dd'))")
[void]$lines.Add("")
[void]$lines.Add("Window: last $WindowDays days. Cadence: at most every $IntervalDays days.")
[void]$lines.Add("")

# ---- Section 1: auto-applied dampeners (from auto-apply-reflect.ps1) -------
[void]$lines.Add("## Auto-applied (safe-bucket) over window")
[void]$lines.Add("")
$autoAppliedCount = 0
if (Test-Path $autoAppliedLog) {
    $content = Get-Content $autoAppliedLog -Raw -Encoding UTF8
    $cutoff = $now.AddDays(-$WindowDays)
    $matches = [regex]::Matches($content, '(?m)^## (\d{4}-\d{2}-\d{2}T[^\r\n]+)')
    $recentEntries = @()
    foreach ($m in $matches) {
        try {
            $stamp = [datetime]::Parse($m.Groups[1].Value)
            if ($stamp -ge $cutoff) { $recentEntries += $m }
        } catch {}
    }
    $autoAppliedCount = $recentEntries.Count
    if ($autoAppliedCount -gt 0) {
        [void]$lines.Add("- $autoAppliedCount auto-apply event(s) recorded")
        [void]$lines.Add("- See: ``~/.agents/context/auto-applied.md``")
    } else {
        [void]$lines.Add("- No auto-apply events in window.")
    }
} else {
    [void]$lines.Add("- No auto-apply log yet (auto-apply-reflect.ps1 hasn't fired).")
}
[void]$lines.Add("")

# ---- Section 2: per-emitter stats (delegated to reflection-emitter-stats.ps1)
[void]$lines.Add("## Reflection volume by agent")
[void]$lines.Add("")
if (Test-Path $emitterStatsTool) {
    $statsRaw = & $emitterStatsTool -DaysBack $WindowDays -RepoRoot $RepoRoot 2>$null
    if ($statsRaw) {
        # Already markdown-formatted; trim the redundant H2 header it emits
        $statsClean = ($statsRaw -join "`n") -replace '(?m)^## Reflection emitter stats[^\n]*\n+', ''
        [void]$lines.Add($statsClean.Trim())
    }
} else {
    [void]$lines.Add("_emitter stats tool missing -- skipping._")
}
[void]$lines.Add("")

# ---- Section 3: actionable recommendations ----------------------------------
[void]$lines.Add("## Recommended /reflect actions")
[void]$lines.Add("")
$recommendations = [System.Collections.ArrayList]::new()
if (Test-Path $emitterStatsTool) {
    try {
        $statsJson = & $emitterStatsTool -DaysBack $WindowDays -RepoRoot $RepoRoot -Json 2>$null | ConvertFrom-Json
        foreach ($r in @($statsJson.rows)) {
            if ($r.total -ge 5 -and $r.supersession_rate -ge 60) {
                [void]$recommendations.Add("- **Tighten ``$($r.agent)``** -- $($r.supersession_rate)% supersession rate over $($r.total) findings. Likely overzealous in this repo.")
            }
        }
    } catch {}
}
if ($recommendations.Count -eq 0) {
    [void]$lines.Add("_None this window. Kit is behaving._")
} else {
    foreach ($rec in $recommendations) { [void]$lines.Add($rec) }
    [void]$lines.Add("")
    [void]$lines.Add("To act: run ``/reflect`` and review proposals. Auto-apply scope is intentionally narrow -- prompt-level changes still need approval.")
}
[void]$lines.Add("")

# ---- Section 4: pointers ----------------------------------------------------
[void]$lines.Add("## Pointers")
[void]$lines.Add("- Full reflections: ``~/.agents/context/reflections.md``")
[void]$lines.Add("- Auto-apply audit: ``~/.agents/context/auto-applied.md``")
[void]$lines.Add("- Auto-apply snapshots (rollback source): ``~/.agents/context/auto-applied-snapshots/``")
[void]$lines.Add("- This digest: ``$digestArchive/$($now.ToString('yyyy-MM-dd')).md``")

$digest = $lines -join "`n"

# Archive
$archivePath = Join-Path $digestArchive "$($now.ToString('yyyy-MM-dd')).md"
[System.IO.File]::WriteAllText($archivePath, $digest, [System.Text.UTF8Encoding]::new($false))

# Touch marker
Set-Content -Path $lastDigestMarker -Value $now.ToString('o') -Encoding utf8

# Print to stdout (post-session.ps1 surfaces this prominently)
Write-Output $digest
exit 0
