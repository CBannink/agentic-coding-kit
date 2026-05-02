#!/usr/bin/env pwsh
# compress-memory.ps1
# Mechanical pass over kit-managed memory files. Stops them turning into slop
# while NEVER losing the actual signal -- archive, never delete; dedup, never
# rewrite. Anything requiring judgment surfaces for /reflect.
#
# Targets:
#   1. Old session-state dirs (~/.agents/session-state/<id>/) -- archive after age
#   2. history.md entries -- archive after age (per repo)
#   3. memory.md duplicate sections -- dedup
#   4. Skill memory files (~/.agents/skills/*/memory.md) -- dedup
#   5. handoffs.md shared tags -- already capped to 20 by handoff-register
#   6. Cross-repo INDEX.md -- archive rows pointing to archived sessions
#
# What it does NOT do (judgment-heavy, surface for /reflect):
#   - Summarize prose into bullets
#   - Merge similar-but-not-identical patterns
#   - Decide what's "still relevant"
#   - Touch user-owned files (CLAUDE.md, AGENTS.md, instructions.md)
#
# Output: JSON summary. Always exits 0 unless input parsing fails.

param(
    [string]$RepoRoot = "",
    [int]$SessionStateAgeDays = 60,    # archive session-state dirs older than N days
    [int]$HistoryAgeDays = 90,          # archive history.md entries older than N days
    [int]$ReflectionsAgeDays = 180,     # archive un-promoted reflections.md entries older than N days
    [int]$ProposalsAgeDays = 90,        # archive decided proposals older than N days
    [int]$SkillMemorySoftLimit = 200,   # warn at this line count, suggest /reflect for compression
    [int]$MemorySoftLimit = 300,        # warn at this line count for memory.md
    [switch]$DryRun,
    [switch]$Json
)

. (Join-Path $PSScriptRoot "_paths.ps1")

if (-not $RepoRoot) { $RepoRoot = (Get-Location).Path }

$summary = [ordered]@{
    sessions_archived           = 0
    history_entries_archived    = 0
    reflections_archived        = 0
    proposals_archived          = 0
    memory_dedups               = 0
    skill_memory_dedups         = 0
    soft_limits_hit             = [System.Collections.ArrayList]::new()
    actions                     = [System.Collections.ArrayList]::new()
    dry_run                     = [bool]$DryRun
}

$today = Get-Date

function Move-ToArchive {
    param([string]$SourcePath, [string]$ArchiveDir)
    if ($DryRun) { return }
    New-Item -ItemType Directory -Path $ArchiveDir -Force | Out-Null
    $dst = Join-Path $ArchiveDir (Split-Path -Leaf $SourcePath)
    Move-Item -Force $SourcePath $dst
}

# --- 1. Session-state dirs older than threshold ---
$sessionDirs = Get-ChildItem $script:SessionRoot -Directory -ErrorAction SilentlyContinue |
    Where-Object { $_.Name -ne ".archive" -and $_.Name -match "^\d{4}-\d{2}-\d{2}" }

$sessionArchive = Join-Path $script:SessionRoot ".archive"
foreach ($dir in $sessionDirs) {
    # Parse date from session id (format: yyyy-MM-dd--HHmmss or yyyy-MM-dd)
    if ($dir.Name -match "^(\d{4}-\d{2}-\d{2})") {
        try {
            $sessionDate = [datetime]::ParseExact($Matches[1], "yyyy-MM-dd", $null)
            $age = ($today - $sessionDate).Days
            if ($age -gt $SessionStateAgeDays) {
                Move-ToArchive -SourcePath $dir.FullName -ArchiveDir $sessionArchive
                $summary.sessions_archived++
                [void]$summary.actions.Add("archive-session: $($dir.Name) (age=$age days)")
            }
        } catch {}
    }
}

# --- 2. history.md aging ---
# Walk entries (each starts with "## YYYY-MM-DD"); buckets each into kept or
# archived by age. Inlined state instead of nested $script: function for clarity.
$historyPath = Join-Path $RepoRoot ".kit/context/history.md"
$historyArchive = Join-Path $RepoRoot ".kit/context/history.archive.md"
if (Test-Path $historyPath) {
    $lines = Get-Content $historyPath -Encoding UTF8
    $kept = New-Object System.Collections.ArrayList
    $archived = New-Object System.Collections.ArrayList
    $entriesArchived = 0

    # Group lines into entries (entry = ## YYYY-MM-DD line + following lines until next H2)
    $entries = New-Object System.Collections.ArrayList   # list of [pscustomobject]@{Date, Lines}
    $headerLines = New-Object System.Collections.ArrayList   # anything before the first dated H2
    $current = $null
    foreach ($line in $lines) {
        if ($line -match "^## (\d{4}-\d{2}-\d{2})") {
            if ($current) { [void]$entries.Add($current) }
            $d = $null
            try { $d = [datetime]::ParseExact($Matches[1], "yyyy-MM-dd", $null) } catch {}
            $current = [pscustomobject]@{ Date = $d; Lines = (New-Object System.Collections.ArrayList) }
            [void]$current.Lines.Add($line)
        } elseif ($current) {
            [void]$current.Lines.Add($line)
        } else {
            [void]$headerLines.Add($line)
        }
    }
    if ($current) { [void]$entries.Add($current) }

    foreach ($l in $headerLines) { [void]$kept.Add($l) }
    foreach ($e in $entries) {
        $isOld = $false
        if ($e.Date) {
            $age = ($today - $e.Date).Days
            if ($age -gt $HistoryAgeDays) { $isOld = $true }
        }
        if ($isOld) {
            foreach ($l in $e.Lines) { [void]$archived.Add($l) }
            $entriesArchived++
        } else {
            foreach ($l in $e.Lines) { [void]$kept.Add($l) }
        }
    }

    if ($entriesArchived -gt 0) {
        $summary.history_entries_archived = $entriesArchived
        [void]$summary.actions.Add("archive-history: $entriesArchived entries older than $HistoryAgeDays days")
        if (-not $DryRun) {
            if (Test-Path $historyArchive) {
                Add-Content -Path $historyArchive -Value ("`n" + ($archived -join "`n")) -Encoding UTF8
            } else {
                Set-Content -Path $historyArchive -Value (($archived -join "`n")) -Encoding UTF8
            }
            Set-Content -Path $historyPath -Value (($kept -join "`n")) -Encoding UTF8
        }
    }
}

# --- 3. memory.md duplicate-line dedup (within the same H2 section) ---
function Dedup-MemoryFile {
    param([string]$Path)
    if (-not (Test-Path $Path)) { return 0 }
    $lines = Get-Content $Path -Encoding UTF8
    $out = New-Object System.Collections.ArrayList
    $sectionSeen = @{ "_root" = @{} }   # init root section for files with no H2
    $currentSection = "_root"
    $duped = 0
    foreach ($line in $lines) {
        if ($line -match "^## ") {
            $currentSection = $line
            if (-not $sectionSeen.ContainsKey($currentSection)) {
                $sectionSeen[$currentSection] = @{}
            }
            [void]$out.Add($line)
            continue
        }
        # Only dedup non-empty content lines that look like list/fact entries.
        # Skip table rows (|...|), short lines, and lines that look like prose.
        if ($line.Trim() -and $line -notmatch "^\s*\|" -and $line.Length -gt 20) {
            # Normalize: collapse whitespace and strip trailing punctuation so
            # "X migrations." and "X migrations" hash to the same key.
            $key = ($line.Trim() -replace '\s+', ' ').TrimEnd('.', ',', ';', ':')
            if ($sectionSeen[$currentSection].ContainsKey($key)) {
                $duped++
                [void]$summary.actions.Add("dedup-memory ($Path): '$($key.Substring(0, [Math]::Min(60, $key.Length)))...'")
                continue
            }
            $sectionSeen[$currentSection][$key] = $true
        }
        [void]$out.Add($line)
    }
    if ($duped -gt 0 -and -not $DryRun) {
        Set-Content -Path $Path -Value ($out -join "`n") -Encoding UTF8
    }
    return $duped
}

$repoMemory = Join-Path $RepoRoot ".kit/context/memory.md"
$summary.memory_dedups = Dedup-MemoryFile -Path $repoMemory

# --- 4. Skill memory dedup ---
$skillDir = Join-Path $script:AgentsRoot "skills"
if (Test-Path $skillDir) {
    Get-ChildItem $skillDir -Directory | ForEach-Object {
        $smPath = Join-Path $_.FullName "memory.md"
        if (Test-Path $smPath) {
            $duped = Dedup-MemoryFile -Path $smPath
            $summary.skill_memory_dedups += $duped
        }
    }
}

# --- 5. Soft-limit checks (don't compress, just flag for /reflect) ---
function Check-SoftLimit {
    param([string]$Path, [int]$Limit, [string]$Label)
    if (-not (Test-Path $Path)) { return }
    $lc = (Get-Content $Path -Encoding UTF8).Count
    if ($lc -gt $Limit) {
        [void]$summary.soft_limits_hit.Add(@{
            file = $Path
            label = $Label
            line_count = $lc
            limit = $Limit
            recommended_action = "review and run /reflect to consolidate, or split into archive"
        })
        [void]$summary.actions.Add("soft-limit: $Label has $lc lines (limit $Limit) -- consider /reflect")
    }
}

Check-SoftLimit -Path $repoMemory -Limit $MemorySoftLimit -Label "memory.md"
if (Test-Path $skillDir) {
    Get-ChildItem $skillDir -Directory | ForEach-Object {
        $smPath = Join-Path $_.FullName "memory.md"
        Check-SoftLimit -Path $smPath -Limit $SkillMemorySoftLimit -Label "skill:$($_.Name)/memory.md"
    }
}

# --- 6. INDEX.md cleanup: drop rows pointing to archived sessions ---
$globalIndex = Join-Path $script:SessionRoot "INDEX.md"
if ((Test-Path $globalIndex) -and (Test-Path $sessionArchive)) {
    $lines = Get-Content $globalIndex -Encoding UTF8
    $out = New-Object System.Collections.ArrayList
    $droppedRows = 0
    foreach ($line in $lines) {
        if ($line -match "^\| \d{4}-\d{2}-\d{2} \|.*?\|\s*([^\|]+\.md)\s*\|") {
            $handoffPath = $Matches[1].Trim()
            if (-not (Test-Path $handoffPath)) {
                $droppedRows++
                continue
            }
        }
        [void]$out.Add($line)
    }
    if ($droppedRows -gt 0 -and -not $DryRun) {
        Set-Content -Path $globalIndex -Value ($out -join "`n") -Encoding UTF8
        [void]$summary.actions.Add("cleanup-index: removed $droppedRows row(s) pointing to archived sessions")
    }
}

# --- 7. Reflections aging: archive un-promoted entries older than threshold ---
# Reflections.md grows unboundedly without this. Entries that didn't reach the
# promotion threshold AND are old enough are moved to reflections.archive.md
# (not deleted -- recoverable if needed).
$globalReflPath    = Join-Path $script:AgentsRoot "context/reflections.md"
$globalReflArchive = Join-Path $script:AgentsRoot "context/reflections.archive.md"
$repoReflPath      = Join-Path $RepoRoot ".kit/context/reflections.md"
$repoReflArchive   = Join-Path $RepoRoot ".kit/context/reflections.archive.md"

function Archive-AgedReflections {
    param([string]$Source, [string]$ArchiveDest, [int]$AgeDays, [string]$Label)
    if (-not (Test-Path $Source)) { return 0 }
    $cutoff = $today.AddDays(-$AgeDays)
    $lines = Get-Content $Source -Encoding UTF8
    $kept = New-Object System.Collections.ArrayList
    $archived = New-Object System.Collections.ArrayList
    $currentEntry = New-Object System.Collections.ArrayList
    $currentDate = $null
    $entriesArchived = 0

    function Decide {
        if ($script:currentEntry.Count -eq 0) { return }
        $isOld = $false
        if ($script:currentDate) {
            if (($today - $script:currentDate).Days -gt $AgeDays) { $isOld = $true }
        }
        if ($isOld) {
            foreach ($l in $script:currentEntry) { [void]$script:archived.Add($l) }
            $script:entriesArchived++
        } else {
            foreach ($l in $script:currentEntry) { [void]$script:kept.Add($l) }
        }
        $script:currentEntry = New-Object System.Collections.ArrayList
        $script:currentDate = $null
    }

    foreach ($line in $lines) {
        if ($line -match "^- \[(\d{4}-\d{2}-\d{2})\]") {
            Decide
            try { $script:currentDate = [datetime]::ParseExact($Matches[1], "yyyy-MM-dd", $null) } catch {}
            [void]$script:currentEntry.Add($line)
        } elseif ($script:currentEntry.Count -gt 0) {
            [void]$script:currentEntry.Add($line)
        } else {
            [void]$kept.Add($line)
        }
    }
    Decide

    if ($entriesArchived -gt 0 -and -not $DryRun) {
        if (Test-Path $ArchiveDest) {
            Add-Content -Path $ArchiveDest -Value ("`n" + ($archived -join "`n")) -Encoding UTF8
        } else {
            Set-Content -Path $ArchiveDest -Value ($archived -join "`n") -Encoding UTF8
        }
        Set-Content -Path $Source -Value ($kept -join "`n") -Encoding UTF8
    }
    if ($entriesArchived -gt 0) {
        [void]$summary.actions.Add("archive-reflections ($Label): $entriesArchived entries older than $AgeDays days")
    }
    return $entriesArchived
}

$summary.reflections_archived += Archive-AgedReflections -Source $globalReflPath -ArchiveDest $globalReflArchive -AgeDays $ReflectionsAgeDays -Label "global"
$summary.reflections_archived += Archive-AgedReflections -Source $repoReflPath   -ArchiveDest $repoReflArchive   -AgeDays $ReflectionsAgeDays -Label "repo"

# --- 8. Proposals archival: move decided proposals older than threshold ---
# ~/.agents/proposals/ accumulates .md files indefinitely. Decided ones (accept
# /reject/defer recorded in decisions.jsonl) older than threshold are moved
# to ~/.agents/proposals/.archive/ to keep the active dir scannable.
$proposalsDir = Join-Path $script:AgentsRoot "proposals"
$proposalsArchive = Join-Path $proposalsDir ".archive"
$decisionsLog = Join-Path $proposalsDir "decisions.jsonl"

if ((Test-Path $proposalsDir) -and (Test-Path $decisionsLog)) {
    $cutoff = $today.AddDays(-$ProposalsAgeDays)
    $decisions = @{}
    foreach ($l in Get-Content $decisionsLog -Encoding UTF8 -ErrorAction SilentlyContinue) {
        try {
            $d = $l | ConvertFrom-Json
            if ($d.proposal_id -and $d.decided_at) {
                $decided = [datetime]::Parse($d.decided_at)
                if ($decided -lt $cutoff) {
                    $decisions[$d.proposal_id] = $true
                }
            }
        } catch {}
    }
    if ($decisions.Count -gt 0) {
        New-Item -ItemType Directory -Path $proposalsArchive -Force | Out-Null
        foreach ($pid in $decisions.Keys) {
            $src = Join-Path $proposalsDir "$pid.md"
            if (Test-Path $src) {
                if (-not $DryRun) { Move-Item -Force $src (Join-Path $proposalsArchive "$pid.md") }
                $summary.proposals_archived++
                [void]$summary.actions.Add("archive-proposal: $pid (decided >$ProposalsAgeDays days ago)")
            }
        }
    }
}

if ($Json) {
    Write-Output (($summary | ConvertTo-Json -Depth 5 -Compress))
} else {
    Write-Host "compress-memory: sessions=$($summary.sessions_archived) history=$($summary.history_entries_archived) reflections=$($summary.reflections_archived) proposals=$($summary.proposals_archived) memory_dedups=$($summary.memory_dedups) skill_dedups=$($summary.skill_memory_dedups) soft_limits=$($summary.soft_limits_hit.Count)"
    if ($summary.actions.Count -gt 0) {
        Write-Host ""
        foreach ($a in $summary.actions) { Write-Host "  - $a" }
    }
}
exit 0
