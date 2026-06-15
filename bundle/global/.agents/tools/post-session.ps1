#!/usr/bin/env pwsh
# post-session.ps1
# Run AFTER a /plan, /build, /review, /analyze, /investigate, or /refactor session ends.
# Checks which gates were completed, warns on required-but-missed gates,
# prompts for a handoff summary, and registers the handoff in memory.md.
#
# Usage:
#   pwsh ~/.agents/tools/post-session.ps1 -SessionId "abc123"
#   pwsh ~/.agents/tools/post-session.ps1 -SessionId "abc123" -Summary "JWT auth done, 3 tests fixed"
#   pwsh ~/.agents/tools/post-session.ps1  # auto-detects last session

param(
    [string]$SessionId = "",
    [string]$Summary = "",
    [string]$Task = "",
    [string]$Mode = "",
    [string]$MemoryPath = "",
    [string]$WhatWasDone = "",
    [string]$OpenItems = "",
    [string]$Outcome = "",
    [string]$Keywords = "",
    [string]$Files = "",
    [switch]$NonInteractive,
    [switch]$AutoApprove
)

$TOOLS = "$HOME/.agents/tools"
$GREEN  = "`e[92m"
$YELLOW = "`e[93m"
$RED    = "`e[91m"
$CYAN   = "`e[96m"
$RESET  = "`e[0m"
$BOLD   = "`e[1m"
$DIM    = "`e[2m"
$globalReflectionsPath = Join-Path $HOME ".agents\context\reflections.md"
$workflowEvidencePath = ""

. (Join-Path $PSScriptRoot "_paths.ps1")

function Append-JsonlIndexLine {
    param(
        [string]$IndexPath,
        [hashtable]$Record
    )
    $lines = @()
    if (Test-Path $IndexPath) {
        $lines = Get-Content $IndexPath | Where-Object { $_ -and ($_ -notmatch ('"session_id"\s*:\s*"' + [regex]::Escape($Record.session_id) + '"')) }
    }
    $lines += ($Record | ConvertTo-Json -Compress)
    Set-Content -Path $IndexPath -Value ($lines -join "`n") -Encoding utf8
}

function Append-ReflectionEntry {
    param(
        [string]$Path,
        [string]$Class,
        [string]$Pattern,
        [string]$Evidence,
        [string]$Target = $script:InstructionsPath
    )
    if (-not (Test-Path $Path)) {
        New-Item -ItemType File -Path $Path -Force | Out-Null
    }
    $date = Get-Date -Format "yyyy-MM-dd"
    $entry = @"
- [$date] [source:harness-auto] [scope:global] [class:$Class]
  Pattern: $Pattern
  Evidence: $Evidence
  Suggested target: $Target
"@
    Add-Content -Path $Path -Value "`n$entry" -Encoding utf8
}

Write-Host ""
Write-Host "${BOLD}${CYAN}╔══════════════════════════════════════════════╗${RESET}"
Write-Host "${BOLD}${CYAN}║  AGENT SESSION HARNESS -- post-session        ║${RESET}"
Write-Host "${BOLD}${CYAN}╚══════════════════════════════════════════════╝${RESET}"
Write-Host ""

# ── Auto-detect last session if SessionId not provided ───────────────────────
if (-not $SessionId) {
    $sessionBase = $script:SessionRoot
    if (Test-Path $sessionBase) {
        $latest = Get-ChildItem $sessionBase -Directory |
            Where-Object { Test-Path "$($_.FullName)/session-meta.json" } |
            Sort-Object LastWriteTime -Descending |
            Select-Object -First 1
        if ($latest) {
            $SessionId = $latest.Name
        Write-Host "${DIM}Auto-detected session: $SessionId${RESET}"
        } else {
            Write-Error "❌ No session found. Provide -SessionId explicitly."
            exit 1
        }
    }
}

# ── Load session metadata ─────────────────────────────────────────────────────
$metaPath = Join-Path (Get-SessionDir $SessionId) "session-meta.json"
$meta = $null
if (Test-Path $metaPath) {
    $meta = Get-Content $metaPath -Raw | ConvertFrom-Json
    if (-not $Task)       { $Task = $meta.task }
    if (-not $Mode)       { $Mode = $meta.mode }
    if (-not $MemoryPath) { $MemoryPath = $meta.memory_path }
}
if (-not $MemoryPath) { $MemoryPath = ".kit/context/memory.md" }
$workflowEvidencePath = Join-Path (Get-SessionDir $SessionId) "workflow-evidence.json"

Write-Host "  Session:  $SessionId"
Write-Host "  Mode:     /$Mode"
Write-Host "  Task:     $Task"
Write-Host ""

$workflowEvidence = $null
if (Test-Path $workflowEvidencePath) {
    $workflowEvidence = Get-Content $workflowEvidencePath -Raw | ConvertFrom-Json
}

# ── Step 1: Gate Check ────────────────────────────────────────────────────────
$statePath = Join-Path (Get-SessionDir $SessionId) "state.json"
$gateWarnings = @()
$gateBlocking = $false

if (Test-Path $statePath) {
    $state = Get-Content $statePath -Raw | ConvertFrom-Json
    $scope = $state.scope

    # Normal completion is gated only on fresh verification evidence.
    # Memory, wiki, handoff, reflection, and writeback artifacts are optional
    # maintenance surfaces, not build/review completion gates.
    $required = @("verification_evidence")

Write-Host "${BOLD}Gate Status (scope: $scope)${RESET}"
    foreach ($g in $state.gates.PSObject.Properties) {
        $isRequired = $required -contains $g.Name
        if ($g.Value) {
        Write-Host "  ${GREEN}✅${RESET} $($g.Name)"
        } elseif ($isRequired) {
        Write-Host "  ${RED}✗  $($g.Name)${RESET} ${RED}← REQUIRED for $scope${RESET}"
            $gateWarnings += $g.Name
            if ($g.Name -eq "verification_evidence") { $gateBlocking = $true }
        } else {
        Write-Host "  ${DIM}⬜ $($g.Name) (optional for $scope)${RESET}"
        }
    }

    if ($state.agents_run.Count -gt 0) {
    Write-Host ""
    Write-Host "  ${DIM}Agents run: $($state.agents_run -join ', ')${RESET}"
    }
Write-Host ""
} else {
Write-Host "${YELLOW}  ⚠ No state.json found -- gate check skipped (pre-session may not have run)${RESET}"
Write-Host ""
}

# ── Step 2: Warn / Block ──────────────────────────────────────────────────────
if ($gateWarnings.Count -gt 0) {
Write-Host "${YELLOW}${BOLD}⚠ $($gateWarnings.Count) required gate(s) not completed:${RESET}"
    foreach ($w in $gateWarnings) { Write-Host "  ${YELLOW}• $w${RESET}" }
Write-Host ""

    if ($gateBlocking) {
    Write-Host "${RED}${BOLD}🚫 IRON LAW VIOLATION: verification_evidence not marked.${RESET}"
    Write-Host "${RED}   Tests/build output must be captured before claiming completion.${RESET}"
    Write-Host ""
        if ($NonInteractive -and -not $AutoApprove) {
        Write-Host "Exiting. Complete verification first, then re-run post-session with -AutoApprove only if intentional."
            exit 1
        }
        if (-not $NonInteractive -and -not $AutoApprove) {
            $confirm = Read-Host "Override and register handoff anyway? (y/N)"
            if ($confirm -ne "y") {
            Write-Host "Exiting. Complete verification first, then re-run post-session."
                exit 1
            }
        }
    } else {
        if ($NonInteractive -and -not $AutoApprove) {
        Write-Host "Exiting. Complete verification first, then re-run post-session."
            exit 1
        }
        if (-not $NonInteractive -and -not $AutoApprove) {
            $confirm = Read-Host "Incomplete gates detected. Register handoff anyway? (y/N)"
            if ($confirm -ne "y") {
            Write-Host "Exiting. Complete the session first."
                exit 1
            }
        }
    }
}

# ── Step 3: Prompt for Summary + Handoff Body ────────────────────────────────
if (-not $Summary) {
    if ($NonInteractive) {
        $Summary = if ($Task) { "$Task session handoff" } else { "session handoff" }
    } else {
    Write-Host "${BOLD}Handoff summary${RESET} (≤15 words -- be specific: what changed, what's open, key decisions)"
    Write-Host "${DIM}Example: 'JWT auth middleware, token refresh route, bcrypt, 3 failing tests fixed'${RESET}"
        $Summary = Read-Host "Summary"
    }
}

if (-not $Summary) {
    Write-Error "❌ Summary required. Re-run with -Summary '...'"
    exit 1
}

if (-not $WhatWasDone) {
    if ($NonInteractive) {
        $WhatWasDone = "*(not recorded -- non-interactive post-session)*"
    } else {
    Write-Host ""
    Write-Host "${BOLD}What was done${RESET} (paste key decisions, changed files, outcomes -- blank line to finish):"
        $doneLines = @()
        while ($true) {
            $line = Read-Host ""
            if ($line -eq "") { break }
            $doneLines += $line
        }
        $WhatWasDone = if ($doneLines.Count -gt 0) { $doneLines -join "`n" } else { "*(not recorded)*" }
    }
}

if (-not $OpenItems) {
    if ($NonInteractive) {
        $OpenItems = "*(none recorded -- non-interactive post-session)*"
    } else {
    Write-Host ""
    Write-Host "${BOLD}Open items / next steps${RESET} (anything unresolved -- blank line to finish):"
        $openLines = @()
        while ($true) {
            $line = Read-Host ""
            if ($line -eq "") { break }
            $openLines += $line
        }
        $OpenItems = if ($openLines.Count -gt 0) { $openLines -join "`n" } else { "*(none)*" }
    }
}

# ── Step 4: Write Private Handoff ────────────────────────────────────────────
$handoffDir = Get-SessionDir $SessionId
$handoffPath = "$handoffDir/handoffs.md"
New-Item -ItemType Directory -Path $handoffDir -Force | Out-Null

$handoffContent = @"
## Session Handoff -- $SessionId
- Date: $(Get-Date -Format "yyyy-MM-dd HH:mm")
- Mode: /$Mode
- Task: $Task
- Scope: $(if ($statePath -and (Test-Path $statePath)) { (Get-Content $statePath -Raw | ConvertFrom-Json).scope } else { "unknown" })
- Summary: $Summary
- Outcome: $(if ($Outcome) { $Outcome } else { "not recorded" })
- Keywords: $(if ($Keywords) { $Keywords } else { "not recorded" })
- Files: $(if ($Files) { $Files } else { "not recorded" })

## What was done
$WhatWasDone

## Open items / next steps
$OpenItems
"@

if ($workflowEvidence) {
    $workflowLines = @(
        "",
        "## Workflow Evidence",
        "- Mode sequence: $(if ($workflowEvidence.mode_sequence.Count -gt 0) { (@($workflowEvidence.mode_sequence) | ForEach-Object { '/' + $_ }) -join ' -> ' } else { 'not recorded' })",
        "- Tier: $(if ($workflowEvidence.tier) { $workflowEvidence.tier } else { 'not recorded' })",
        "- Tier reason: $(if ($workflowEvidence.tier_reason) { $workflowEvidence.tier_reason } else { 'not recorded' })",
        "- Scope: $(if ($workflowEvidence.scope) { $workflowEvidence.scope } else { 'not recorded' })",
        "- Scope reason: $(if ($workflowEvidence.scope_reason) { $workflowEvidence.scope_reason } else { 'not recorded' })",
        "- Build brief used: $(if ($workflowEvidence.build_brief_used) { $workflowEvidence.build_brief_used } else { 'not recorded' })",
        "- Repo context used: $(if ($workflowEvidence.repo_context_used.Count -gt 0) { @($workflowEvidence.repo_context_used) -join ', ' } else { 'not recorded' })",
        "- Agents spawned: $(if ($workflowEvidence.agents_spawned.Count -gt 0) { @($workflowEvidence.agents_spawned) -join '; ' } else { 'none recorded' })",
        "- Agents skipped: $(if ($workflowEvidence.agents_skipped.Count -gt 0) { @($workflowEvidence.agents_skipped) -join '; ' } else { 'none recorded' })",
        "- Mode decisions: $(if ($workflowEvidence.mode_decisions.Count -gt 0) { @($workflowEvidence.mode_decisions) -join '; ' } else { 'none recorded' })",
        "- Review checks: $(if ($workflowEvidence.review_checks.Count -gt 0) { @($workflowEvidence.review_checks) -join '; ' } else { 'none recorded' })",
        "- Verification commands: $(if ($workflowEvidence.verification_commands.Count -gt 0) { @($workflowEvidence.verification_commands) -join ', ' } else { 'not recorded' })",
        "- Memory decision: $(if ($workflowEvidence.write_decisions.memory) { $workflowEvidence.write_decisions.memory } else { 'not recorded' })",
        "- History decision: $(if ($workflowEvidence.write_decisions.history) { $workflowEvidence.write_decisions.history } else { 'not recorded' })",
        "- Wiki decision: $(if ($workflowEvidence.write_decisions.wiki) { $workflowEvidence.write_decisions.wiki } else { 'not recorded' })"
    )
    $handoffContent += "`n" + ($workflowLines -join "`n")
}

if (-not (Test-Path $handoffPath)) {
    Set-Content -Path $handoffPath -Value $handoffContent -Encoding utf8
} else {
    Add-Content -Path $handoffPath -Value "`n---`n$handoffContent" -Encoding utf8
}
Write-Host "${GREEN}✅ Private handoff written: $handoffPath${RESET}"
Sync-EvalArtifactMirror -SessionId $SessionId -SourcePath $handoffPath -TargetName "handoffs.md"
if (Test-Path $statePath) {
    & $script:AgentsShell -NoProfile -File "$TOOLS/state-gate.ps1" -SessionId $SessionId -Mark "handoff_written" | Out-Null
}

# ── Step 5: Register in Memory Index ─────────────────────────────────────────
if (Test-Path $MemoryPath) {
Write-Host "${DIM}Registering in memory.md session index...${RESET}"
    & $script:AgentsShell -NoProfile -File "$TOOLS/handoff-register.ps1" -SessionId $SessionId -Task $Task -Summary $Summary -MemoryPath $MemoryPath
} else {
Write-Host "${YELLOW}⚠ memory.md not found at $MemoryPath -- skipping index registration${RESET}"
Write-Host "${DIM}  (Run handoff-register.ps1 manually when in the repo directory)${RESET}"
}

# ── Step 5b: Append to device-wide INDEX.md (cross-repo retrieval) ───────────
# This is the device-wide handoff index. Lets pre-session in any repo find
# semantically-relevant prior work across all repos you've touched.
$globalIndex = Get-CrossRepoIndexPath
$globalIndexDir = Split-Path -Parent $globalIndex
New-Item -ItemType Directory -Path $globalIndexDir -Force | Out-Null

if (-not (Test-Path $globalIndex)) {
    @"
# Global Session Handoff Index

Cross-repo handoff index. Auto-appended by post-session.ps1. Newest entries
at the bottom. Pre-session in any repo scans this for semantically-relevant
prior work.

| Date | Repo | Mode | Task | Keywords | Path |
|------|------|------|------|----------|------|
"@ | Set-Content -Path $globalIndex -Encoding utf8
}

$repoName = Split-Path -Leaf (Get-Location).Path
$kw = if ($Keywords) { $Keywords } else { "" }
$row = "| $(Get-Date -Format 'yyyy-MM-dd') | $repoName | /$Mode | $Task | $kw | $handoffPath |"
Add-Content -Path $globalIndex -Value $row -Encoding utf8
Write-Host "${DIM}  Appended to device-wide INDEX.md ($globalIndex)${RESET}"

# ── Step 6: Append one-liner to shared handoffs index ────────────────────────
$sharedHandoffs = ".kit/context/handoffs.md"
if (Test-Path $sharedHandoffs) {
    $tag = "## [SESSION: $SessionId | Task: $Task | Mode: /$Mode | Status: complete"
    if ($workflowEvidence -and $workflowEvidence.tier) { $tag += " | Tier: $($workflowEvidence.tier)" }
    if ($Outcome)  { $tag += " | Outcome: $Outcome" }
    if ($Keywords) { $tag += " | Keywords: $Keywords" }
    if ($Files)    { $tag += " | Files: $Files" }
    $tag += " | Handoff: $handoffPath]"
    Add-Content -Path $sharedHandoffs -Value "`n$tag" -Encoding utf8
Write-Host "${GREEN}✅ Shared handoffs index updated${RESET}"

    $indexPath = Join-Path (Split-Path $sharedHandoffs) "handoffs.index.jsonl"
    $record = @{
        session_id   = $SessionId
        task         = $Task
        mode         = $Mode
        tier         = if ($workflowEvidence -and $workflowEvidence.tier) { $workflowEvidence.tier } else { "" }
        status       = "complete"
        outcome      = $Outcome
        keywords     = if ($Keywords) { ,@($Keywords -split '\s*,\s*' | Where-Object { $_ }) } else { @() }
        files        = if ($Files) { ,@($Files -split '\s*,\s*' | Where-Object { $_ }) } else { @() }
        mode_sequence = if ($workflowEvidence) { ,@($workflowEvidence.mode_sequence) } else { @() }
        repo_context_used = if ($workflowEvidence) { ,@($workflowEvidence.repo_context_used) } else { @() }
        agents_spawned = if ($workflowEvidence) { ,@($workflowEvidence.agents_spawned) } else { @() }
        agents_skipped = if ($workflowEvidence) { ,@($workflowEvidence.agents_skipped) } else { @() }
        mode_decisions = if ($workflowEvidence) { ,@($workflowEvidence.mode_decisions) } else { @() }
        review_checks = if ($workflowEvidence) { ,@($workflowEvidence.review_checks) } else { @() }
        verification_commands = if ($workflowEvidence) { ,@($workflowEvidence.verification_commands) } else { @() }
        memory_decision = if ($workflowEvidence) { $workflowEvidence.write_decisions.memory } else { "" }
        history_decision = if ($workflowEvidence) { $workflowEvidence.write_decisions.history } else { "" }
        wiki_decision = if ($workflowEvidence) { $workflowEvidence.write_decisions.wiki } else { "" }
        handoff_path = $handoffPath
        summary      = $Summary
        recorded_at  = (Get-Date -Format "o")
    }
    Append-JsonlIndexLine -IndexPath $indexPath -Record $record
    Write-Host "${GREEN}✅ Machine-readable handoff index updated${RESET}"
}

& $script:AgentsShell -NoProfile -File "$TOOLS/session-end-hook.ps1" -SessionId $SessionId -Mode $Mode -Outcome $Outcome -Summary $Summary -Files $Files | Out-Null

Write-Host ""
Write-Host "${BOLD}${GREEN}╔══════════════════════════════════════════════╗${RESET}"
Write-Host "${BOLD}${GREEN}║  Session registered. Harness complete. ✅    ║${RESET}"
Write-Host "${BOLD}${GREEN}╚══════════════════════════════════════════════╝${RESET}"
Write-Host ""
Write-Host "  Private handoff: ${CYAN}$handoffPath${RESET}"
Write-Host "  Memory index:    ${CYAN}$MemoryPath${RESET}"
Write-Host "  Maintenance:     ${DIM}manual-only; run maintenance tools explicitly when needed${RESET}"
Write-Host ""
exit 0
