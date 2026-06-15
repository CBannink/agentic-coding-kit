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

# ── Step 3: Optional context availability ─────────────────────────────────────
$contextDir = if ($MemoryPath) { Split-Path $MemoryPath } else { ".kit/context" }
$repoHandoffsPath = Join-Path $contextDir "handoffs.md"
$historyPath = Join-Path $contextDir "history.md"
$repoHandoffsAvailable = Test-Path $repoHandoffsPath
$historyAvailable = Test-Path $historyPath
Write-Host "${DIM}Checking optional context availability...${RESET}"
if ($repoHandoffsAvailable) {
    Write-Host "  Repo handoffs available on demand"
}
if ($historyAvailable) {
    Write-Host "  Repo history available on demand"
}
if (-not $repoHandoffsAvailable -and -not $historyAvailable) {
    Write-Host "  No repo handoff/history files found"
}

# ── Step 3.4: Cross-repo handoff scan (device-wide INDEX.md) ─────────────────
$globalIndex = Get-CrossRepoIndexPath
$globalIndexAvailable = Test-Path $globalIndex
if ($globalIndexAvailable) {
    Write-Host "  Cross-repo index available on demand"
}

# ── Step 3.5: Recent History ─────────────────────────────────────────────────
# History content is on-demand only; do not read it during startup.

# ── Step 3.6: Recent Git Log ──────────────────────────────────────────────────
$gitInRepo = $false

try {
    $gitCheck = git rev-parse --is-inside-work-tree 2>$null
    if ($LASTEXITCODE -eq 0) {
        $gitInRepo = $true
        Write-Host "  Git history available on demand"
    }
} catch {
    Write-Host "  ${DIM}Not in a git repo or git unavailable${RESET}"
}


Write-Host ""

# ── Step 3.7: Reflection Backlog Notice ────────────────────────────────────────
# Reflection maintenance is manual-only. Surface the count for awareness, but do
# not gate normal build/review/refactor/redesign work on it.
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
$reflectNeeded = $false
if ($reflectCount -gt 0) {
    Write-Host "  Reflections: $reflectCount unaddressed (repo=$reflectCountRepo, global=$reflectCountGlobal) -- manual maintenance only"
}

# ── Step 3.8: Wiki + Build Brief Detection ───────────────────────────────────────
$wikiDir = Join-Path (Get-Location).Path ".wiki"
$wikiIndexPath = $null
if (Test-Path $wikiDir -PathType Container) {
    $wikiIndexPath = Get-ChildItem -LiteralPath $wikiDir -File |
        Where-Object { $_.Name -ieq "index.md" } |
        Select-Object -ExpandProperty FullName -First 1
}
$wikiFeaturesExists = Test-Path ".wiki/features.md"
$wikiExists = [bool]$wikiIndexPath -and $wikiFeaturesExists
$wikiIndexName = if ($wikiIndexPath) { Split-Path $wikiIndexPath -Leaf } else { "index.md" }
$buildBriefAvailable = ($Mode -eq "build" -and (Test-Path ".kit/context/handoffs.md"))
if ($wikiExists) {
    Write-Host "  Wiki: .wiki/$wikiIndexName + features.md exist"
} else {
    # Loud, actionable warning. Mandatory per global always-on rules.
    Write-Host "${YELLOW}  WIKI: MISSING -- .wiki/ does not exist in this repo.${RESET}"
    Write-Host "${YELLOW}        The kit's always-on rules require .wiki/index.md (any casing) and .wiki/features.md before non-trivial work.${RESET}"
    Write-Host "${YELLOW}        Run /wiki-init to bootstrap it from real code evidence.${RESET}"
}

# Codex tree detection -- the kit's runtime memory artifacts. Skills assume
# .kit/context/memory.md and friends exist; without them they no-op.
$codexExists = Test-Path ".kit/context/memory.md"
$patternsExists = Test-Path ".kit/context/patterns.md"
if ($codexExists) {
    if ($patternsExists) {
        Write-Host "  KIT: .kit/context/memory.md + patterns.md exist"
    } else {
        Write-Host "${YELLOW}  KIT: .kit/context/memory.md exists, but patterns.md is missing (legacy repo guidance surface).${RESET}"
    }
} else {
    Write-Host "${YELLOW}  KIT: MISSING -- .kit/ runtime memory tree not initialized in this repo.${RESET}"
    Write-Host "${YELLOW}         Skills (/build, /plan, /review) will silently skip context-load steps.${RESET}"
    Write-Host "${YELLOW}         Run /kit-init to bootstrap memory.md + handoffs.md + patterns.md (agent-memory/ stays legacy read-only).${RESET}"
}
if ($buildBriefAvailable) { Write-Host "  Prior build briefs may be available on demand in .kit/context/handoffs.md" }

# ── Step 3.9: Parallel Instance Check ───────────────────────────────────────────
$parallelWarning = ""
# Keep startup cheap and context-light. Do not parse handoffs.md here; handoffs
# are on-demand context, not a default lifecycle input.

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
- REFLECT_NEEDED: no ($reflectCount entries; manual maintenance only)
- WIKI: $(if ($wikiExists) { "yes -- read .wiki/$wikiIndexName FIRST (TOC, ~100 lines), then load only the smallest relevant architecture/codebase/features/principles page. NEVER bulk-read .wiki/sections/." } else { "MISSING -- run /wiki-init to bootstrap (mandatory per global rules)" })
- KIT: $(if ($codexExists) { "yes -- optional focused context only. Use .kit/context/patterns.md for repo-specific agent guidance when needed; memory.md, handoffs.md, and agent-memory/ are not startup context. agent-memory/ is legacy read-only opt-in via specialist-memory-resolver.ps1 -IncludeLegacyRoleMemory." } else { "MISSING -- run /kit-init to bootstrap repo memory tree (memory.md + handoffs index + patterns.md)" })
- BUILD_BRIEF: $(if ($buildBriefAvailable) { "prior build briefs may exist in .kit/context/handoffs.md -- load only if this task explicitly resumes or depends on prior work" } else { "none" })
- PARALLEL_INSTANCE: $(if ($parallelWarning) { $parallelWarning } else { "none detected" })
- STATE_FILE: $(if ($stateInitialized) { Join-Path (Get-SessionDir $SessionId) "state.json" } else { "not initialized for /$Mode" })
"@

if ($repoHandoffsAvailable) {
    $brief += "`n`n## Prior Sessions"
    $brief += "`n  Repo handoffs exist. Do not load by default; inspect .kit/context/handoffs.md only when the current task explicitly resumes prior work or overlaps a known prior area."
}

if ($globalIndexAvailable) {
    $brief += "`n`n## Cross-Repo Matches"
    $brief += "`n  Global index exists. Do not load by default; use only for explicit maintenance or clearly overlapping work."
}

if ($historyAvailable) {
    $brief += "`n`n## Recent History"
    $brief += "`n  Repo history exists. Do not scan by default; consult .kit/context/history.md only when the task touches a known fragile area or explicitly asks for historical context."
}

if ($gitInRepo) {
    $brief += "`n`n## Git History"
    $brief += "`n  Git history is available for on-demand archaeology only; do not read recent commits by default."
}

$brief += @"

## Your task
/$Mode $Task

## Instructions to orchestrator
- PRIOR SESSIONS / HISTORY: do not load by default. Use them only when the task explicitly resumes prior work, references a prior decision, or touches a known fragile area.
- GIT LOG: optional archaeology only. Use when history is relevant to the task, not as startup context.
- Follow the /$Mode workflow in ~/.agents/skills/$Mode/SKILL.md.
- TIER_REC in brief is machine-classified. Start with this tier. Override UPWARD only if you have concrete evidence the scope is larger.
- REFLECT_NEEDED is never a normal-work gate. Run /reflect only when explicitly doing maintenance.
- WIKI in brief: if yes, read .wiki/$wikiIndexName first, then load the smallest relevant wiki file for the task.
- BUILD_BRIEF in brief: load only when the task explicitly resumes or depends on that prior work.
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

# Context bloat guard -- report only. Self-improvement maintenance is manual-only.
$bloatGuard = & $script:AgentsShell -NoProfile -File "$TOOLS/context-bloat-guard.ps1" -RepoRoot (Get-Location).Path -Json 2>$null
if ($bloatGuard) {
    try {
        $bg = $bloatGuard | ConvertFrom-Json
        if ($bg.status -eq "critical") {
            Write-Host "WARN: context files exceed hard limits -- run manual maintenance when convenient. Check $($bg.total_critical) file(s)."
        } elseif ($bg.status -eq "warn") {
            Write-Host "Note: $($bg.total_warnings) context file(s) approaching soft limit."
        }
    } catch {}
}

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
