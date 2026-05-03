#!/usr/bin/env pwsh
# pre-session.ps1
# Run BEFORE opening a /plan, /build, /review, /analyze, /investigate, or /refactor session.
# Does scope classification, state initialization, handoff index scan,
# and generates a BUILD BRIEF to paste as the first message in Copilot CLI.
#
# Usage:
#   pwsh ~/.agents/tools/pre-session.ps1 -Mode plan -Task "add JWT auth module"
#   pwsh ~/.agents/tools/pre-session.ps1 -Mode build -Task "add JWT auth module"
#   pwsh ~/.agents/tools/pre-session.ps1 -Mode review -Task "review auth PR"
#   pwsh ~/.agents/tools/pre-session.ps1 -Mode analyze -Task "analyze perf bottlenecks"
#
# Output: a BRIEF block to paste as first message in Copilot CLI

param(
    [ValidateSet("plan","build","review","analyze","refactor","investigate")][string]$Mode = "build",
    [string]$Task = "",
    [string]$SessionId = "",
    [string]$MemoryPath = ".kit/context/memory.md"
)

. (Join-Path $PSScriptRoot "_paths.ps1")
$TOOLS = $PSScriptRoot
$CYAN  = "`e[96m"
$GREEN = "`e[92m"
$YELLOW = "`e[93m"
$RESET = "`e[0m"
$BOLD  = "`e[1m"
$DIM   = "`e[2m"

# Generate session ID if not provided -- datetime format for human searchability
if (-not $SessionId) {
    $SessionId = Get-Date -Format "yyyy-MM-dd--HHmmss"
}

# Resolve task slug
$taskSlug = if ($Task) {
    $cleaned = ($Task -replace '[^a-zA-Z0-9\s]', '' -replace '\s+', '-').ToLower()
    $cleaned.Substring(0, [Math]::Min(30, $cleaned.Length))
} else {
    "$Mode-$(Get-Date -Format 'MMddHHmm')"
}

Write-Host ""
Write-Host "${BOLD}${CYAN}╔══════════════════════════════════════════════╗${RESET}"
Write-Host "${BOLD}${CYAN}║  AGENT SESSION HARNESS -- pre-session         ║${RESET}"
Write-Host "${BOLD}${CYAN}╚══════════════════════════════════════════════╝${RESET}"
Write-Host ""

# ── Step 1: Scope Classification (build mode only) ──────────────────────────
$scope = "N/A"
$scopeReason = "N/A"
$fileCount = 0

if ($Mode -eq "build" -or $Mode -eq "refactor") {
    Write-Host "${DIM}Running scope classifier...${RESET}"
    $scopeRaw = & $script:AgentsShell -NoProfile -File "$TOOLS/scope-classifier.ps1" 2>$null
    if ($scopeRaw) {
        $scopeJson = $scopeRaw | ConvertFrom-Json
        $scope = $scopeJson.scope
        $scopeReason = $scopeJson.reason
        $fileCount = $scopeJson.file_count
        Write-Host "  Scope:  ${BOLD}$scope${RESET} -- $scopeReason"
    } else {
        $scope = "SHARED"
        $scopeReason = "classifier failed -- defaulting upward to SHARED"
        Write-Host "  ${YELLOW}⚠ Scope classifier returned no output -- defaulting to SHARED${RESET}"
    }
} else {
    Write-Host "  Scope classification: skipped for /$Mode"
}


# ── Step 1.5: Tier Recommendation ──────────────────────────────────────────────
$tierRec = "TARGETED"
$tierReason = "default"
if ($Mode -eq "build" -or $Mode -eq "refactor") {
    if ($scope -eq "CRITICAL") {
        $tierRec = "FULL";     $tierReason = "CRITICAL scope always runs FULL"
    } elseif ($scope -eq "SHARED" -and $fileCount -gt 8) {
        $tierRec = "FULL";     $tierReason = "SHARED scope + $fileCount files -- use FULL"
    } elseif ($scope -eq "SHARED") {
        $tierRec = "TARGETED"; $tierReason = "SHARED scope, manageable file count"
    } elseif ($scope -eq "ISOLATED" -and $fileCount -le 3) {
        $tierRec = "INLINE";   $tierReason = "ISOLATED scope, 1-3 files"
    } else {
        $tierRec = "TARGETED"; $tierReason = "ISOLATED scope, 4+ files"
    }
    Write-Host "  Tier rec: ${BOLD}$tierRec${RESET} -- $tierReason"
    Write-Host "  (Orchestrator may override UPWARD only -- never downward)"
}

# ── Step 1.6: Swarm Eligibility ────────────────────────────────────────────────
# SWARM is the third tier axis. Only fires when verb is parallel-safe AND scope
# is fan-out-able AND user opted in. Consults swarm-classifier.ps1.
$swarmMode = "sequential"
$swarmReason = "default"
$optIn = ($env:AGENTS_SWARM -eq "1") -or ($Task -match "(?i)\bswarm\b")
$swarmRaw = & $script:AgentsShell -NoProfile -File "$TOOLS/swarm-classifier.ps1" -Task $Task -Scope $scope -FileCount $fileCount $(if ($optIn) { "-OptIn" }) 2>$null
if ($swarmRaw) {
    $swarmJson = $swarmRaw | ConvertFrom-Json
    $swarmMode = $swarmJson.mode
    $swarmReason = $swarmJson.reason
    if ($swarmMode -eq "swarm-fanout") {
        $tierRec = "SWARM"
        $tierReason = "swarm classifier: $swarmReason"
        Write-Host "  Swarm:    ${BOLD}swarm-fanout${RESET} -- $swarmReason"
    } elseif ($swarmMode -eq "swarm-review") {
        Write-Host "  Swarm:    parallel-reviewers (sequential implementer + N concurrent reviewers)"
        Write-Host "  Reason:   $swarmReason"
    }
}

# ── Step 2: Initialize State ─────────────────────────────────────────────────
$stateInitialized = $false
if ($Mode -eq "build" -or $Mode -eq "refactor") {
    Write-Host "${DIM}Initializing session state...${RESET}"
    $result = & $script:AgentsShell -NoProfile -File "$TOOLS/state-init.ps1" -SessionId $SessionId -Task $taskSlug -Scope $scope -ScopeReason $scopeReason 2>&1
    if ($LASTEXITCODE -eq 0) {
        $stateInitialized = $true
        Write-Host "  ${GREEN}✅ State initialized${RESET}"
    } else {
        Write-Host "  ${YELLOW}⚠ State init failed: $result${RESET}"
    }
}

# ── Step 3: Scan Session Handoff Index ───────────────────────────────────────
Write-Host "${DIM}Scanning session handoff index...${RESET}"
$relevantHandoffs = @()

if (Test-Path $MemoryPath) {
    $memLines = Get-Content $MemoryPath
    $inIndex = $false
    $inTable = $false

    foreach ($line in $memLines) {
        if ($line -match "^## Session Handoff Index") { $inIndex = $true; continue }
        if ($inIndex -and $line -match "^## ") { break }
        if ($inIndex -and $line -match "^\| Date") { $inTable = $true; continue }
        if ($inIndex -and $line -match "^\|[-| ]+\|") { continue }
        if ($inTable -and $line -match "^\| \d{4}-\d{2}-\d{2}") {
            $parts = $line -split '\|' | ForEach-Object { $_.Trim() } | Where-Object { $_ }
            if ($parts.Count -ge 4) {
                $relevantHandoffs += [PSCustomObject]@{
                    Date    = $parts[0]
                    Task    = $parts[1]
                    Summary = $parts[2]
                    Path    = $parts[3]
                }
            }
        }
    }

    if ($relevantHandoffs.Count -eq 0) {
        Write-Host "  No prior sessions found in index"
    } else {
        Write-Host "  Found $($relevantHandoffs.Count) prior session(s) in index"
    }
} else {
    Write-Host "  ${YELLOW}⚠ memory.md not found at $MemoryPath -- handoff index unavailable${RESET}"
}

# ── Step 3.4: Cross-repo handoff scan (global INDEX.md) ──────────────────────
# Surface up to 5 most recent rows from the device-wide INDEX.md, optionally
# filtered by keyword overlap with the current task. This is the agent's
# trigger to pull in similar work done in other repos.
$globalIndex = Join-Path $script:SessionRoot "INDEX.md"
$globalMatches = @()
if (Test-Path $globalIndex) {
    Write-Host "${DIM}Scanning global cross-repo INDEX.md...${RESET}"
    $taskWords = @($Task -split '\s+' | Where-Object { $_.Length -ge 4 } | ForEach-Object { $_.ToLower() })
    $rows = Get-Content $globalIndex | Where-Object { $_ -match "^\| \d{4}-\d{2}-\d{2} \|" }
    foreach ($r in $rows) {
        $score = 0
        foreach ($w in $taskWords) {
            if ($r.ToLower() -like "*$w*") { $score++ }
        }
        if ($score -gt 0 -or $taskWords.Count -eq 0) {
            $globalMatches += [PSCustomObject]@{ Score = $score; Row = $r }
        }
    }
    $globalMatches = @($globalMatches | Sort-Object Score -Descending | Select-Object -First 5)
    if ($globalMatches.Count -gt 0) {
        Write-Host "  Found $($globalMatches.Count) cross-repo match(es) in global index"
    }
}

# ── Step 3.5: Recent History ─────────────────────────────────────────────────
$historyPath = if ($MemoryPath) { Join-Path (Split-Path $MemoryPath) "history.md" } else { ".kit/context/history.md" }
$recentHistoryEntries = @()

if (Test-Path $historyPath) {
    Write-Host "${DIM}Reading recent history.md...${RESET}"
    $histLines = Get-Content $historyPath
    $currentEntry = @()
    $entryCount = 0
    $maxEntries = 5   # Show last 5 history entries in the brief

    foreach ($line in $histLines) {
        if ($line -match "^## \d{4}-\d{2}-\d{2}") {
            if ($currentEntry.Count -gt 0) {
                $recentHistoryEntries = @([PSCustomObject]@{ Text = ($currentEntry -join "`n").Trim() }) + $recentHistoryEntries
                $currentEntry = @()
                $entryCount++
                if ($entryCount -ge $maxEntries) { break }
            }
            $currentEntry = @($line)
        } elseif ($currentEntry.Count -gt 0) {
            $currentEntry += $line
        }
    }
    if ($currentEntry.Count -gt 0 -and $entryCount -lt $maxEntries) {
        $recentHistoryEntries = @([PSCustomObject]@{ Text = ($currentEntry -join "`n").Trim() }) + $recentHistoryEntries
    }

    if ($recentHistoryEntries.Count -gt 0) {
        Write-Host "  Found $($recentHistoryEntries.Count) recent history entry/entries"
    } else {
        Write-Host "  history.md exists but no dated entries found"
    }
} else {
    Write-Host "  ${DIM}history.md not found -- no prior history context${RESET}"
}

# ── Step 3.6: Recent Git Log ──────────────────────────────────────────────────
$gitLog = @()
$gitLogStr = ""
$gitInRepo = $false

try {
    $gitCheck = git rev-parse --is-inside-work-tree 2>$null
    if ($LASTEXITCODE -eq 0) {
        $gitInRepo = $true
        Write-Host "${DIM}Reading recent git log...${RESET}"
        $gitLog = git log --oneline -20 2>$null
        $gitLogStr = if ($gitLog) { $gitLog -join "`n" } else { "(no commits yet)" }
        Write-Host "  Got $($gitLog.Count) recent commit(s)"
    }
} catch {
    Write-Host "  ${DIM}Not in a git repo or git unavailable${RESET}"
}


Write-Host ""

# ── Step 3.7: Reflections Gate ─────────────────────────────────────────────────
# Scans BOTH repo-local and global reflections. 5+ unaddressed = mandatory /reflect
# before this session can ship. This is the self-improvement loop hard gate.
$repoReflectionsPath   = ".kit/context/reflections.md"
$globalReflectionsPath = Join-Path $script:AgentsRoot "context/reflections.md"
$reflectCountRepo = 0
$reflectCountGlobal = 0

function Count-Unaddressed-Reflections([string]$path) {
    if (-not (Test-Path $path)) { return 0 }
    return (Get-Content $path | Where-Object { $_ -match "^- " -and $_ -notmatch "promoted|archived" }).Count
}

$reflectCountRepo   = Count-Unaddressed-Reflections $repoReflectionsPath
$reflectCountGlobal = Count-Unaddressed-Reflections $globalReflectionsPath
$reflectCount = $reflectCountRepo + $reflectCountGlobal
$reflectNeeded = $reflectCount -ge 5
$reflectSoft   = ($reflectCount -ge 3) -and -not $reflectNeeded

if ($reflectCount -gt 0 -or $reflectNeeded) {
    $rSuffix = if ($reflectNeeded) { " -- REFLECT NEEDED (>=5 unaddressed)" }
               elseif ($reflectSoft) { " -- soft warning (>=3 unaddressed)" }
               else { "" }
    Write-Host "  Reflections: $reflectCount unaddressed (repo=$reflectCountRepo, global=$reflectCountGlobal)$rSuffix"
}

# ── Step 3.8: Wiki + Build Brief Detection ───────────────────────────────────────
$wikiExists = Test-Path ".wiki/features.md"
$buildBriefPath = ""
$buildBriefSource = ""
if ($Mode -eq "build") {
    $briefJson = & $script:AgentsShell -NoProfile -File "$TOOLS/brief-resolver.ps1" -Date (Get-Date -Format "yyyy-MM-dd") -SharedHandoffsPath ".kit/context/handoffs.md" 2>$null
    if ($briefJson) {
        try {
            $brief = $briefJson | ConvertFrom-Json
            if ($brief.found) {
                $buildBriefPath = $brief.handoff_path
                $buildBriefSource = $brief.source
            }
        } catch {}
    }
}
if ($wikiExists) {
    Write-Host "  Wiki: .wiki/features.md exists"
} else {
    # Loud, actionable warning. Mandatory per global always-on rules.
    Write-Host "${YELLOW}  WIKI: MISSING -- .wiki/ does not exist in this repo.${RESET}"
    Write-Host "${YELLOW}        The kit's always-on rules require .wiki/features.md before non-trivial work.${RESET}"
    Write-Host "${YELLOW}        Run /wiki-init to bootstrap it from real code evidence.${RESET}"
}

# Codex tree detection -- the kit's runtime memory artifacts. Skills assume
# .kit/context/memory.md and friends exist; without them they no-op.
$codexExists = Test-Path ".kit/context/memory.md"
if ($codexExists) {
    Write-Host "  KIT: .kit/context/memory.md exists"
} else {
    Write-Host "${YELLOW}  KIT: MISSING -- .kit/ runtime memory tree not initialized in this repo.${RESET}"
    Write-Host "${YELLOW}         Skills (/build, /plan, /review) will silently skip context-load steps.${RESET}"
    Write-Host "${YELLOW}         Run /kit-init to bootstrap memory.md + handoffs.md + agent-memory/.${RESET}"
}
if ($buildBriefPath)    { Write-Host "  Prior build brief from today ($buildBriefSource): $buildBriefPath" }

# ── Step 3.9: Parallel Instance Check ───────────────────────────────────────────
$parallelWarning = ""
if (Test-Path ".kit/context/handoffs.md") {
    $nowPt = Get-Date
    foreach ($hLine in (Get-Content ".kit/context/handoffs.md")) {
        if ($hLine -match "SESSION: (\d{4}-\d{2}-\d{2}--\d{6}).*Task: ([^|]+)\|") {
            try {
                $sDt = [datetime]::ParseExact($Matches[1].Trim(), "yyyy-MM-dd--HHmmss", $null)
                $oTask = $Matches[2].Trim()
                $minsAgo = [int](($nowPt - $sDt).TotalMinutes)
                if ($minsAgo -le 60 -and $oTask -ne $taskSlug) {
                    $parallelWarning = "PARALLEL: task=$oTask was active ${minsAgo}min ago -- append-only mode"
                    Write-Host "  WARNING: $parallelWarning"
                }
            } catch {}
        }
    }
}

Write-Host "${BOLD}${GREEN}╔══════════════════════════════════════════════════════════╗${RESET}"
Write-Host "${BOLD}${GREEN}║  PASTE THIS AS YOUR FIRST MESSAGE IN COPILOT CLI         ║${RESET}"
Write-Host "${BOLD}${GREEN}╚══════════════════════════════════════════════════════════╝${RESET}"
Write-Host ""

$brief = @"
## Agent Session Brief
- SESSION_ID: $SessionId
- MODE: /$Mode
- TASK: $Task
- SCOPE: $scope ($scopeReason)
- TIER_REC: $tierRec ($tierReason -- orchestrator may override UPWARD only)
- REFLECT_NEEDED: $(if ($reflectNeeded) { "YES ($reflectCount unaddressed entries -- run /reflect first)" } else { "no ($reflectCount entries)" })
- WIKI: $(if ($wikiExists) { "yes -- read .wiki/index.md FIRST (TOC, ~100 lines), then use wiki-resolver.ps1 for on-demand section loading. NEVER bulk-read .wiki/sections/." } else { "MISSING -- run /wiki-init to bootstrap (mandatory per global rules)" })
- KIT: $(if ($codexExists) { "yes -- read .kit/context/memory.md + handoffs.md + agent-memory/shared.md per skill 'Load Context First' steps. Use specialist-memory-resolver.ps1 for per-role memory." } else { "MISSING -- run /kit-init to bootstrap repo memory tree (memory.md + handoffs index + agent-memory/)" })
- BUILD_BRIEF: $(if ($buildBriefPath) { "YES -- read handoff at $buildBriefPath BEFORE planning (source: $buildBriefSource)" } else { "none" })
- PARALLEL_INSTANCE: $(if ($parallelWarning) { $parallelWarning } else { "none detected" })
- STATE_FILE: $(if ($stateInitialized) { Join-Path (Get-SessionDir $SessionId) "state.json" } else { "not initialized for /$Mode" })
"@

if ($relevantHandoffs.Count -gt 0) {
    $brief += "`n`n## Prior Sessions (this repo -- load if relevant to your task)"
    foreach ($h in $relevantHandoffs) {
        $brief += "`n  [$($h.Date)] $($h.Task): $($h.Summary)"
        $brief += "`n  -> $($h.Path)"
    }
}

if ($globalMatches.Count -gt 0) {
    $brief += "`n`n## Cross-Repo Matches (global INDEX.md -- semantically related work in OTHER repos)"
    $brief += "`n  Read these handoffs only if your task overlaps -- different repo, different conventions."
    foreach ($m in $globalMatches) {
        $brief += "`n  $($m.Row)"
    }
}

if ($recentHistoryEntries.Count -gt 0) {
    $brief += "`n`n## Recent History (last $($recentHistoryEntries.Count) entries from history.md)"
    $brief += "`n  Scan this BEFORE planning. Do not re-implement or re-break what's listed here."
    foreach ($entry in $recentHistoryEntries) {
        # Indent each line of the entry for readability
        $indented = ($entry.Text -split "`n" | ForEach-Object { "  $_" }) -join "`n"
        $brief += "`n$indented"
    }
}

if ($gitInRepo -and $gitLogStr) {
    $brief += "`n`n## Recent Git Log (last 20 commits)"
    $brief += "`n  Cross-reference with history.md to understand what changed and when."
    $indentedLog = ($gitLog | ForEach-Object { "  $_" }) -join "`n"
    $brief += "`n$indentedLog"
}

$brief += @"

## Your task
/$Mode $Task

## Instructions to orchestrator
- PRIOR SESSIONS: for each entry above, decide if its summary is relevant to this task. If yes, read its handoff path before planning.
- RECENT HISTORY: read the history entries above before planning. If your task touches an area mentioned in history, understand what was done and why before changing it. Do not re-implement something already built. Do not re-introduce a bug already fixed.
- GIT LOG: cross-reference with history. A fix commit followed shortly by a revert = fragile area -- treat with extra caution and flag to user.
- Follow the /$Mode workflow in ~/.agents/skills/$Mode/SKILL.md.
- TIER_REC in brief is machine-classified. Start with this tier. Override UPWARD only if you have concrete evidence the scope is larger.
- REFLECT_NEEDED in brief: if YES, run /reflect before starting implementation. This is mandatory.
- WIKI in brief: if yes, read .wiki/features.md as your first read -- it replaces most explore-phase work.
- BUILD_BRIEF in brief: if YES, read the handoff at the path given immediately. Use it as the primary prior-session brief.
- PARALLEL_INSTANCE in brief: if detected, treat .kit/context/ files as append-only for this session.
"@

if ($Mode -eq "build" -or $Mode -eq "refactor") {
    $brief += "`n- Scope is already classified: $scope. Use this -- do not re-run scope classifier."
} else {
    $brief += "`n- No pre-session scope classification ran for /$Mode. Classify scope inline only if that workflow requires it."
}

if ($stateInitialized) {
    $brief += "`n- AGENT_TRACKING: after each sub-agent spawn, run:"
    $brief += "`n  ``pwsh ~/.agents/tools/state-gate.ps1 -SessionId $SessionId -AddAgent ""{name}"" -EnforceAgentCap``"
    $brief += "`n  This updates state.json and hard-blocks if the tier cap is exceeded."
    $brief += "`n- State file already initialized at path above. Mark gates as you complete them."
    $brief += "`n- Run: ``pwsh ~/.agents/tools/state-gate.ps1 -SessionId $SessionId`` at any time to see gate status."
} else {
    $brief += "`n- No state-backed agent tracking was initialized for /$Mode. Record spawned agents via workflow-evidence instead."
    $brief += "`n- No workflow state file was initialized for /$Mode."
}

Write-Host $brief
Write-Host ""
Write-Host "${DIM}─────────────────────────────────────────────────────────${RESET}"
Write-Host "${DIM}Session ID saved. Run post-session when done:${RESET}"
Write-Host "${YELLOW}  pwsh ~/.agents/tools/post-session.ps1 -SessionId $SessionId -Mode $Mode -Task `"$taskSlug`"${RESET}"
Write-Host ""

# Save session metadata for post-session to use
$metaDir = Get-SessionDir $SessionId
New-Item -ItemType Directory -Path $metaDir -Force | Out-Null
@{
    session_id = $SessionId
    mode       = $Mode
    task       = $taskSlug
    task_full  = $Task
    scope      = $scope
    started_at = (Get-Date -Format "o")
    tier_rec   = $tierRec
    memory_path = $MemoryPath
} | ConvertTo-Json | Set-Content "$metaDir/session-meta.json" -Encoding utf8

& $script:AgentsShell -NoProfile -File "$TOOLS/session-start-hook.ps1" -SessionId $SessionId -Mode $Mode -Task $taskSlug -RepoRoot (Get-Location).Path | Out-Null
