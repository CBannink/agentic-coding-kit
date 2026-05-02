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

    # Required gates per scope
    $required = @("scope_classified", "context_loaded", "implementation_done", "verification_evidence")
    if ($scope -eq "SHARED" -or $scope -eq "CRITICAL") {
        $required += "rubber_duck_consulted"
    }

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

# ── Step 5b: Append to GLOBAL session-state INDEX.md (cross-repo retrieval) ───
# This is the device-wide handoff index. Lets pre-session in any repo find
# semantically-relevant prior work across all repos you've touched.
$globalIndex = Join-Path $script:SessionRoot "INDEX.md"
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
Write-Host "${DIM}  Appended to global INDEX.md ($globalIndex)${RESET}"

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

# ── Step 7: memory.md -- new durable facts ────────────────────────────────────
if (Test-Path $MemoryPath) {
    Write-Host ""
    Write-Host "${BOLD}Memory facts${RESET}"
    Write-Host "${DIM}Record durable architectural facts discovered this session.${RESET}"
    Write-Host "${DIM}Gate: 'Would this be useful to a completely different instance on a different task in this repo?'${RESET}"
    Write-Host "${DIM}Yes → record it. No → leave it in the handoff above.${RESET}"
    Write-Host "${DIM}Examples: verified commands, schema constraints, architectural decisions, known traps.${RESET}"
    if ($NonInteractive) {
        Write-Host "${DIM}  Skipped in non-interactive mode.${RESET}"
        $addFacts = "n"
    } else {
        $addFacts = Read-Host "Any new durable facts to add to memory.md? (y/N)"
    }

    if ($addFacts -eq "y") {
        $factEntries = @()
        Write-Host "Enter each fact on one line. Blank line when done:"
        while ($true) {
            $fact = Read-Host "  Fact"
            if ($fact -eq "") { break }
            $factEntries += "- $fact  [added: $(Get-Date -Format 'yyyy-MM-dd')]"
        }
        if ($factEntries.Count -gt 0) {
            $factsBlock = "`n" + ($factEntries -join "`n")
            Add-Content -Path $MemoryPath -Value $factsBlock -Encoding utf8
            Write-Host "${GREEN}✅ $($factEntries.Count) fact(s) added to memory.md${RESET}"
        }
    } else {
        Write-Host "${DIM}  Skipped.${RESET}"
    }
} else {
    Write-Host "${DIM}  memory.md not found -- skipping facts gate${RESET}"
}

# ── Step 8: .wiki update gate ─────────────────────────────────────────────────
$wikiFeatures   = ".wiki/features.md"
$wikiManifest   = ".wiki/.features"

if ((Test-Path $wikiFeatures) -or (Test-Path $wikiManifest)) {
    Write-Host ""
    Write-Host "${BOLD}Wiki update gate${RESET}"
    Write-Host "${DIM}Update .wiki when: new CLI command/flag, new API endpoint, new dashboard page, new onboarding${RESET}"
    Write-Host "${DIM}step, new validator/eval mode, new env var, or meaningful behaviour change to existing feature.${RESET}"
    Write-Host "${DIM}Skip for: refactors, test additions, bug fixes restoring documented behaviour, perf fixes.${RESET}"
    if ($NonInteractive) {
        Write-Host "${DIM}  Skipped in non-interactive mode.${RESET}"
        $wikiNeeded = "n"
    } else {
        $wikiNeeded = Read-Host "Does this session require a .wiki update? (y/N)"
    }

    if ($wikiNeeded -eq "y") {
        Write-Host ""
        Write-Host "Open ${CYAN}.wiki/features.md${RESET} and ${CYAN}.wiki/.features${RESET} now and make your edits."
        Write-Host "${DIM}Both files must stay in sync (features.md = human, .features = JSON manifest).${RESET}"
        Read-Host "Press Enter when wiki files are updated"
        Write-Host "${GREEN}✅ Wiki update confirmed${RESET}"
    } else {
        Write-Host "${DIM}  Skipped -- no user-visible feature change.${RESET}"
    }
} else {
    Write-Host "${DIM}  No .wiki/ found -- skipping wiki gate${RESET}"
}

# ── Step 9: history.md entry ──────────────────────────────────────────────────
$historyPath = if ($MemoryPath) {
    Join-Path (Split-Path $MemoryPath) "history.md"
} else {
    ".kit/context/history.md"
}

if (Test-Path $historyPath) {
    Write-Host ""
    Write-Host "${BOLD}History entry${RESET}"
    Write-Host "${DIM}Write to history.md when: major feature shipped, significant bug fixed, key architecture decision, dangerous trap discovered.${RESET}"
    Write-Host "${DIM}Skip for: refactors, test additions, minor fixes, config changes.${RESET}"
    if ($NonInteractive) {
        Write-Host "${DIM}  Skipped in non-interactive mode.${RESET}"
        $writeHistory = "n"
    } else {
        $writeHistory = Read-Host "Write a history.md entry for this session? (y/N)"
    }

    if ($writeHistory -eq "y") {
        $historyTitle = Read-Host "Entry title (one line, e.g. 'JWT auth module shipped')"
        Write-Host "Entry body (paste 2-5 sentences, then press Enter twice when done):"
        $bodyLines = @()
        $emptyCount = 0
        while ($emptyCount -lt 1) {
            $line = Read-Host ""
            if ($line -eq "") { $emptyCount++ } else { $emptyCount = 0; $bodyLines += $line }
        }
        $historyBody = $bodyLines -join "`n"
        $historyDate = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
        $historyEntry = @"

## $historyDate -- $historyTitle

$historyBody

---
"@
        Add-Content -Path $historyPath -Value $historyEntry -Encoding utf8
        Write-Host "${GREEN}✅ history.md updated: $historyPath${RESET}"
    } else {
        Write-Host "${DIM}  Skipped.${RESET}"
    }
} else {
    Write-Host "${DIM}  history.md not found at $historyPath -- skipping${RESET}"
}

# ── Agent Count Enforcement ──────────────────────────────────────────────────
$metaPath = Join-Path (Get-SessionDir $SessionId) "session-meta.json"
$evidencePath = Join-Path (Get-SessionDir $SessionId) "workflow-evidence.json"
$tierCaps = @{ INLINE = 0; TARGETED = 6; FULL = 12; SWARM = 24 }
$agentCount = 0
$cap = 6
if (Test-Path $evidencePath) {
    try {
        $evidence = Get-Content $evidencePath -Raw | ConvertFrom-Json
        if ($evidence.tier -and $tierCaps.ContainsKey($evidence.tier)) {
            $cap = $tierCaps[$evidence.tier]
        }
    } catch {}
}
if ($cap -eq 6 -and (Test-Path $metaPath)) {
    try {
        $meta = Get-Content $metaPath -Raw | ConvertFrom-Json
        if ($meta.tier_rec -and $tierCaps.ContainsKey($meta.tier_rec)) {
            $cap = $tierCaps[$meta.tier_rec]
        }
    } catch {}
}
if ($state -and $state.agents_run) {
    $agentCount = @($state.agents_run).Count
}
Write-Host ""
Write-Host "${BOLD}Agent count: $agentCount registered (tier cap: $cap)${RESET}"
if ($agentCount -gt $cap) {
    Write-Host "${YELLOW}⚠ OVER TIER CAP by $($agentCount - $cap) agents.${RESET}"
    Append-ReflectionEntry -Path $globalReflectionsPath -Class "routing" -Pattern "Agent cap exceeded during session registration" -Evidence "session=$SessionId tier_cap=$cap agent_count=$agentCount task=$Task"
    if ($NonInteractive -and -not $AutoApprove) {
        exit 1
    }
} else {
    Write-Host "${GREEN}✓ Within tier cap${RESET}"
}

if ($gateWarnings.Count -gt 0) {
    $evidence = "session=$SessionId task=$Task scope=$scope missing_gates=" + ($gateWarnings -join ',')
    $class = if ($gateBlocking) { "verification" } else { "gating" }
    $pattern = if ($gateBlocking) { "Session registered with verification gate missing or overridden" } else { "Session registered with required workflow gates incomplete" }
    Append-ReflectionEntry -Path $globalReflectionsPath -Class $class -Pattern $pattern -Evidence $evidence
}

# ── Extra objective-failure triggers (self-improvement loop) ──────────────────
# These capture patterns the harness can detect mechanically. Subjective ideas
# still go through normal session/reflect judgment. Only objective failures here.
if ($workflowEvidence) {
    # Tier override downward -- forbidden, always a workflow bug
    if ($workflowEvidence.tier -and $meta -and $meta.tier_rec) {
        $tierOrder = @{ INLINE = 0; TARGETED = 1; FULL = 2; SWARM = 3 }
        if ($tierOrder.ContainsKey($workflowEvidence.tier) -and $tierOrder.ContainsKey($meta.tier_rec)) {
            if ($tierOrder[$workflowEvidence.tier] -lt $tierOrder[$meta.tier_rec]) {
                Append-ReflectionEntry -Path $globalReflectionsPath -Class "gating" `
                    -Pattern "Tier overridden DOWNWARD ($($meta.tier_rec) --> $($workflowEvidence.tier)) -- orchestrator may only override upward" `
                    -Evidence "session=$SessionId task=$Task tier_rec=$($meta.tier_rec) tier_actual=$($workflowEvidence.tier) reason=$($workflowEvidence.tier_reason)"
            }
        }
    }

    # False-positive verifier was skipped on a /review or /security-review session
    $reviewModes = @("review", "security-review")
    if ($reviewModes -contains $Mode -and $workflowEvidence.agents_skipped) {
        $skipped = ($workflowEvidence.agents_skipped | Out-String)
        if ($skipped -match "(?i)false.?positive") {
            Append-ReflectionEntry -Path $globalReflectionsPath -Class "verification" `
                -Pattern "False-positive verifier was skipped on /$Mode" `
                -Evidence "session=$SessionId task=$Task skipped=$skipped"
        }
    }

    # Workflow evidence has gaps -- mode/tier/scope unset means the brief lied about discipline
    $missingFields = @()
    if (-not $workflowEvidence.tier) { $missingFields += "tier" }
    if (-not $workflowEvidence.scope) { $missingFields += "scope" }
    if (-not $workflowEvidence.mode_sequence -or @($workflowEvidence.mode_sequence).Count -eq 0) { $missingFields += "mode_sequence" }
    if (-not $workflowEvidence.verification_commands -or @($workflowEvidence.verification_commands).Count -eq 0) { $missingFields += "verification_commands" }
    if ($missingFields.Count -ge 2) {
        Append-ReflectionEntry -Path $globalReflectionsPath -Class "verification" `
            -Pattern "Workflow evidence missing required fields ($($missingFields -join ', '))" `
            -Evidence "session=$SessionId task=$Task mode=$Mode missing=$($missingFields -join ',')"
    }
}

# ── Expanded reflection capture (6 additional objective-failure detectors) ───
# Each catches a class of mistake mechanically. Subjective judgment stays in
# /reflect; these only fire on conditions detectable from session artifacts.

# Detector 1: long session (likely abandonment or context loss)
if ($meta -and $meta.started_at) {
    try {
        $startedAt = [datetime]::Parse($meta.started_at)
        $hoursElapsed = ((Get-Date) - $startedAt).TotalHours
        if ($hoursElapsed -gt 8) {
            Append-ReflectionEntry -Path $globalReflectionsPath -Class "verification" `
                -Pattern "Session ran for $([math]::Round($hoursElapsed, 1)) hours -- likely abandoned, lost context, or merged with another task" `
                -Evidence "session=$SessionId task=$Task mode=$Mode hours=$([math]::Round($hoursElapsed, 1))"
        }
    } catch {}
}

# Detector 2: trivial verification command (gaming the verification gate)
if ($workflowEvidence -and $workflowEvidence.verification_commands) {
    $trivialPatterns = @('^\s*echo\s', '^\s*true\s*$', '^\s*:\s*$', '^\s*exit\s+0\s*$', '^\s*ls\s*$', '^\s*pwd\s*$')
    foreach ($cmd in @($workflowEvidence.verification_commands)) {
        foreach ($p in $trivialPatterns) {
            if ($cmd -match $p) {
                Append-ReflectionEntry -Path $globalReflectionsPath -Class "verification" `
                    -Pattern "Verification command appears to be gaming the gate: '$cmd'" `
                    -Evidence "session=$SessionId task=$Task command=$cmd"
                break
            }
        }
    }
}

# Detector 3: verification_evidence gate marked but no commands recorded
if ($state -and $state.gates.verification_evidence -eq $true) {
    $verCmdCount = if ($workflowEvidence -and $workflowEvidence.verification_commands) { @($workflowEvidence.verification_commands).Count } else { 0 }
    if ($verCmdCount -eq 0) {
        Append-ReflectionEntry -Path $globalReflectionsPath -Class "verification" `
            -Pattern "verification_evidence gate marked passed but no verification commands in workflow-evidence" `
            -Evidence "session=$SessionId task=$Task -- agent marked the gate without running anything"
    }
}

# Detector 4: bloated handoff summary (>25 words = clarity erosion)
if ($Summary) {
    $wordCount = @($Summary -split '\s+' | Where-Object { $_ }).Count
    if ($wordCount -gt 25) {
        Append-ReflectionEntry -Path $globalReflectionsPath -Class "noise" `
            -Pattern "Handoff summary is $wordCount words (limit 15-25); will hurt retrieval scan in next session" `
            -Evidence "session=$SessionId task=$Task word_count=$wordCount summary='$($Summary.Substring(0, [Math]::Min(80, $Summary.Length)))...'"
    }
}

# Detector 5: agents registered but not propagated to workflow-evidence
if ($state -and @($state.agents_run).Count -gt 0) {
    $evidenceAgents = if ($workflowEvidence) { @($workflowEvidence.agents_spawned) } else { @() }
    if ($evidenceAgents.Count -eq 0) {
        Append-ReflectionEntry -Path $globalReflectionsPath -Class "gating" `
            -Pattern "$(@($state.agents_run).Count) agent(s) in state.agents_run but workflow-evidence.agents_spawned is empty -- registration didn't propagate" `
            -Evidence "session=$SessionId task=$Task agents=$(@($state.agents_run) -join ',')"
    }
}

# Detector 5b: review-tier-vs-stages mismatch (skill-protocol shortcut detection)
# Catches the "FULL tier picked but only TARGETED-style work executed" pattern.
# Fires only when review-evidence.json exists for this session (i.e., /review
# was the active mode and the agent recorded at least one stage).
$reviewEvPath = Join-Path (Get-SessionDir $SessionId) "review-evidence.json"
if (Test-Path $reviewEvPath) {
    try {
        $reviewEv = Get-Content $reviewEvPath -Raw -Encoding UTF8 | ConvertFrom-Json
        if ($reviewEv.tier -and $reviewEv.stages_run -and $reviewEv.stages_run.Count -gt 0) {
            $expected = @{
                "INLINE"   = @("verifier")
                "TARGETED" = @("wiki-resolver", "surface", "verifier")
                "FULL"     = @("wiki-resolver", "surface", "consequence", "interaction", "synthesis", "adversarial", "verifier")
            }
            if ($expected.ContainsKey($reviewEv.tier)) {
                $stagesRun = @($reviewEv.stages_run | ForEach-Object { $_.stage } | Select-Object -Unique)
                $missing = @($expected[$reviewEv.tier] | Where-Object { $stagesRun -notcontains $_ })
                if ($missing.Count -gt 0) {
                    Append-ReflectionEntry -Path $globalReflectionsPath -Class "gating" `
                        -Pattern "review tier=$($reviewEv.tier) missing stages [$($missing -join ', ')] -- agent shortcut the protocol" `
                        -Evidence "session=$SessionId task=$Task tier=$($reviewEv.tier) stages_run=[$($stagesRun -join ',')] missing=[$($missing -join ',')]"
                }
            }
        }
    } catch {}
}

# Detector 6: repeated task slug across recent sessions (possible thrashing)
if ($Task) {
    $taskSlug = ($Task -replace '[^a-zA-Z0-9\s]', '' -replace '\s+', '-').ToLower()
    $taskSlug = $taskSlug.Substring(0, [Math]::Min(30, $taskSlug.Length))
    $recentDir = $script:SessionRoot
    $recentMatches = 0
    if (Test-Path $recentDir) {
        $cutoff = (Get-Date).AddDays(-7)
        Get-ChildItem $recentDir -Directory -ErrorAction SilentlyContinue |
            Where-Object { $_.Name -ne ".archive" -and $_.Name -match "^\d{4}-\d{2}-\d{2}" -and $_.Name -ne $SessionId } |
            ForEach-Object {
                $otherMeta = Join-Path $_.FullName "session-meta.json"
                if (Test-Path $otherMeta) {
                    try {
                        $om = Get-Content $otherMeta -Raw -Encoding UTF8 | ConvertFrom-Json
                        if ($om.task -eq $taskSlug -and $om.started_at) {
                            $oStart = [datetime]::Parse($om.started_at)
                            if ($oStart -gt $cutoff) { $recentMatches++ }
                        }
                    } catch {}
                }
            }
    }
    if ($recentMatches -ge 1) {
        Append-ReflectionEntry -Path $globalReflectionsPath -Class "routing" `
            -Pattern "Task '$taskSlug' has been run $($recentMatches + 1) times in the last 7 days -- possible thrashing or unfinished work" `
            -Evidence "session=$SessionId task=$Task recent_repeats=$recentMatches"
    }
}

# Detector 7: memory-writes audit (memory drift detection)
# A field reflection identified the failure mode: agent spawns N agents,
# learns user preferences / feedback patterns / domain facts during the
# session, but writes ZERO entries to the kit's memory locations. Memory
# saving is voluntary; without enforcement it gets skipped under
# conversational pressure. Detector fires a soft reflection when:
#   - state.agents_run.Count >= 3 (real session, not trivial)
#   - AND no files modified under ~/.agents/memory/ since session start
#     OR no entries appended to .codex/context/memory.md (now .kit/...)
# Soft because some sessions legitimately have nothing to save (mechanical
# refactor, doc edit). Recurring fires across many sessions = real pattern
# that auto-consolidate will surface to harness-propose.
if ($state -and @($state.agents_run).Count -ge 3) {
    $memoryDir = Join-Path $HOME ".agents/memory"
    $sessStartTime = if (Test-Path (Get-SessionDir $SessionId)) {
        (Get-Item (Get-SessionDir $SessionId)).CreationTime
    } else {
        (Get-Date).AddHours(-1)
    }

    $memoryWriteCount = 0
    if (Test-Path $memoryDir) {
        $memoryWriteCount = @(Get-ChildItem $memoryDir -Recurse -File -ErrorAction SilentlyContinue | Where-Object { $_.LastWriteTime -gt $sessStartTime }).Count
    }
    # Also check repo's .kit/context/memory.md for new appends
    $repoMemPath = ".kit/context/memory.md"
    if (Test-Path $repoMemPath) {
        $repoMemMtime = (Get-Item $repoMemPath).LastWriteTime
        if ($repoMemMtime -gt $sessStartTime) { $memoryWriteCount++ }
    }

    if ($memoryWriteCount -eq 0) {
        $agentList = (@($state.agents_run) -join ',')
        Append-ReflectionEntry -Path $globalReflectionsPath -Class "routing" `
            -Pattern "Spawned $(@($state.agents_run).Count) agent(s) but 0 memory writes -- did the session learn user prefs / feedback patterns / repo facts that should have been saved?" `
            -Evidence "session=$SessionId task=$Task agents=[$agentList] memory_writes=0"
    }
}

# ── Self-improvement loop enforcement ─────────────────────────────────────────
# Three phases: consolidate, compress, gate-check. Each handles a different
# axis of slop/noise; together they close the loop without requiring /reflect
# in the common case.
#
# Phase 1: run the agent-less mechanical consolidator. It dedups identical
# entries, archives anything already promoted in memory.md, drops stale
# single-occurrence entries, and auto-promotes additive patterns with 2+
# occurrences.
$autoConsolidate = Join-Path $TOOLS "auto-consolidate.ps1"
if (Test-Path $autoConsolidate) {
    Write-Host ""
    Write-Host "${DIM}Auto-consolidating reflections...${RESET}"
    $consolidateRaw = & $script:AgentsShell -NoProfile $script:AgentsShell -NoProfile -File $autoConsolidate -Json 2>$null
    if ($consolidateRaw) {
        try {
            $cs = $consolidateRaw | ConvertFrom-Json
            $changed = $cs.deduped + $cs.archived + $cs.stale_dropped + $cs.auto_promoted
            if ($changed -gt 0) {
                Write-Host "  ${GREEN}auto-consolidated: $($cs.started_with) --> $($cs.remaining) (deduped=$($cs.deduped) archived=$($cs.archived) stale=$($cs.stale_dropped) promoted=$($cs.auto_promoted))${RESET}"
            } else {
                Write-Host "  ${DIM}no consolidation needed${RESET}"
            }
        } catch {}
    }
}

# Phase 2: compress memory (slop prevention). Mechanical only -- archives
# old session-state dirs and history entries, dedups memory.md and skill
# memory files. Soft-limit warnings surface for /reflect; nothing destructive.
$compressTool = Join-Path $TOOLS "compress-memory.ps1"
if (Test-Path $compressTool) {
    Write-Host "${DIM}Compressing memory...${RESET}"
    $compressRaw = & $script:AgentsShell -NoProfile -File $compressTool -Json 2>$null
    if ($compressRaw) {
        try {
            $cm = $compressRaw | ConvertFrom-Json
            $changed = $cm.sessions_archived + $cm.history_entries_archived + $cm.memory_dedups + $cm.skill_memory_dedups
            if ($changed -gt 0) {
                Write-Host "  ${GREEN}compressed: sessions=$($cm.sessions_archived) history=$($cm.history_entries_archived) dedups=$($cm.memory_dedups + $cm.skill_memory_dedups)${RESET}"
            }
            if ($cm.soft_limits_hit -and @($cm.soft_limits_hit).Count -gt 0) {
                Write-Host "  ${YELLOW}soft-limits hit on $(@($cm.soft_limits_hit).Count) file(s) -- consider /reflect to consolidate${RESET}"
            }
        } catch {}
    }
}

# Phase 2b: meta-pattern proposer. Detects recurring KIT-LEVEL failure patterns
# (5+ total occurrences AND 3+ within the last 30 days) and writes proposal
# markdown files for human review. NEVER auto-applies. SILENT when nothing
# meets the threshold -- only shouts when there's something genuinely actionable.
$proposeTool = Join-Path $TOOLS "harness-propose.ps1"
if (Test-Path $proposeTool) {
    $proposeRaw = & $script:AgentsShell -NoProfile -File $proposeTool -Json 2>$null
    if ($proposeRaw) {
        try {
            $pp = $proposeRaw | ConvertFrom-Json
            $newCount = if ($pp.new_proposals) { @($pp.new_proposals).Count } else { 0 }
            if ($newCount -gt 0) {
                # PROMINENT BANNER -- only shown when there's something to look at.
                Write-Host ""
                Write-Host "${BOLD}${YELLOW}╔══════════════════════════════════════════════════════════════════╗${RESET}"
                Write-Host "${BOLD}${YELLOW}║  ⚠ NEW HARNESS PROPOSAL(S): $newCount  ─ recurring failure pattern(s) found  ║${RESET}"
                Write-Host "${BOLD}${YELLOW}╚══════════════════════════════════════════════════════════════════╝${RESET}"
                foreach ($p in @($pp.new_proposals)) {
                    Write-Host "  ${YELLOW}• [$($p.class)] seen $($p.count)x  $($p.pattern_preview)${RESET}"
                }
                Write-Host ""
                Write-Host "  ${BOLD}Review (does NOT auto-apply):${RESET}"
                Write-Host "    pwsh ~/.agents/tools/harness-review.ps1                  # list all pending"
                Write-Host "    pwsh ~/.agents/tools/harness-review.ps1 -Show <id>       # read full proposal"
                Write-Host "    pwsh ~/.agents/tools/harness-review.ps1 -ProposalId <id> -Action accept|reject|defer -Note '...'"
                Write-Host ""
            }
            # Otherwise: silent. No proposals, nothing to show.
        } catch {}
    }
}

# Phase 3: query the gate. After consolidate + compress, the count reflects
# only entries that genuinely need judgment. If still >= mandatory threshold,
# block ship in NonInteractive mode unless -AutoApprove was explicitly set.
$reflectTrigger = Join-Path $TOOLS "reflect-trigger.ps1"
if (Test-Path $reflectTrigger) {
    $reflectRaw = & $script:AgentsShell -NoProfile $script:AgentsShell -NoProfile -File $reflectTrigger -Json 2>$null
    if ($reflectRaw) {
        try {
            $reflectStatus = $reflectRaw | ConvertFrom-Json
            if ($reflectStatus.status -eq "mandatory") {
                Write-Host ""
                Write-Host "${RED}${BOLD}🔁 SELF-IMPROVEMENT GATE: $($reflectStatus.count_total) unaddressed reflections (>=$($reflectStatus.threshold_mandatory))${RESET}"
                Write-Host "${RED}   Run /reflect before opening another session.${RESET}"
                Write-Host "${DIM}   See: $($reflectStatus.repo_path)${RESET}"
                Write-Host "${DIM}   See: $($reflectStatus.global_path)${RESET}"
                Write-Host ""
                if ($NonInteractive -and -not $AutoApprove) {
                    exit 2
                }
            } elseif ($reflectStatus.status -eq "soft") {
                Write-Host ""
                Write-Host "${YELLOW}🔁 reflection backlog: $($reflectStatus.count_total) unaddressed (soft warning, threshold $($reflectStatus.threshold_soft))${RESET}"
            }
        } catch {
            Write-Host "${DIM}   (reflect-trigger output unparseable -- skipping gate)${RESET}"
        }
    }
}

# ── Auto-compliance check (closes the empirical loop) ────────────────────────
# Runs test-compliance.ps1 against the session that just ended, logs the
# score to ~/.agents/compliance-history.jsonl, and emits a reflection entry
# if there are CRITICAL/HIGH fails. Without this, compliance data only
# exists when the user manually runs the harness -- which means it doesn't.
$complianceScript = $null
foreach ($candidate in @(
    (Join-Path $HOME "Downloads/caspar_bannink_agentic_coding/caspar_bannink_agentic_coding/scripts/test-compliance.ps1"),
    (Resolve-Path -Path "scripts/test-compliance.ps1" -ErrorAction SilentlyContinue),
    (Join-Path (Split-Path -Parent $TOOLS) "../../scripts/test-compliance.ps1")
)) {
    if ($candidate -and (Test-Path $candidate)) { $complianceScript = $candidate; break }
}

if ($complianceScript -and (Test-Path $complianceScript)) {
    Write-Host ""
    Write-Host "${DIM}Auto-compliance check...${RESET}"
    try {
        $complianceJson = & $script:AgentsShell -NoProfile -File $complianceScript -SessionId $SessionId -Json 2>$null
        if ($complianceJson) {
            $cr = $complianceJson | ConvertFrom-Json
            $score = $cr.compliance_pct
            $critFails = $cr.critical_fails

            # Append to history
            $historyJsonl = Join-Path $HOME ".agents/compliance-history.jsonl"
            $record = @{
                ts = (Get-Date).ToString("o")
                session_id = $SessionId
                task = $Task
                mode = $Mode
                score_pct = $score
                pass = $cr.score
                critical_fails = $critFails
            } | ConvertTo-Json -Compress
            Add-Content -Path $historyJsonl -Value $record -Encoding UTF8

            $color = if ($critFails -eq 0) { $GREEN } elseif ($critFails -le 2) { $YELLOW } else { $RED }
            Write-Host "  ${color}Compliance: $score% ($($cr.score) passed, $critFails critical/high fails)${RESET}"

            # Reflection on critical fails -- feeds harness-propose for kit-level patterns
            if ($critFails -gt 0) {
                $failNames = @($cr.results | Where-Object { $_.status -eq "FAIL" -and $_.severity -in @("CRITICAL","HIGH") } | ForEach-Object { $_.name })
                Append-ReflectionEntry -Path $globalReflectionsPath -Class "gating" `
                    -Pattern "Session compliance below bar: $critFails critical/high assertion(s) failed: $($failNames -join ', ')" `
                    -Evidence "session=$SessionId task=$Task score=$score% fails=[$($failNames -join ',')]"
            }
        }
    } catch {
        Write-Host "  ${DIM}(compliance check failed: $($_.Exception.Message))${RESET}"
    }
} else {
    Write-Host "${DIM}(compliance script not on disk -- skipping auto-check)${RESET}"
}

# ── Done ──────────────────────────────────────────────────────────────────────
Write-Host ""
Write-Host "${BOLD}${GREEN}╔══════════════════════════════════════════════╗${RESET}"
Write-Host "${BOLD}${GREEN}║  Session registered. Harness complete. ✅    ║${RESET}"
Write-Host "${BOLD}${GREEN}╚══════════════════════════════════════════════╝${RESET}"
Write-Host ""
Write-Host "  Private handoff: ${CYAN}$handoffPath${RESET}"
Write-Host "  Memory index:    ${CYAN}$MemoryPath${RESET}"
if (Test-Path $historyPath) { Write-Host "  History:         ${CYAN}$historyPath${RESET}" }
if ((Test-Path $wikiFeatures) -or (Test-Path $wikiManifest)) { Write-Host "  Wiki:            ${CYAN}$wikiFeatures${RESET}" }
Write-Host "  Next session:    ${DIM}pwsh ~/.agents/tools/pre-session.ps1 -Mode $Mode -Task '...'${RESET}"
Write-Host ""
