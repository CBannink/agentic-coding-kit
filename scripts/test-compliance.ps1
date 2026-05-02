#!/usr/bin/env pwsh
# test-compliance.ps1 -- empirical kit compliance assertions.
#
# Why: validate-bundle checks bundle integrity; doctor checks install health.
# Neither tests "did the agent actually obey the kit's rules during a real
# session." This tool does. Run it post-session, get a PASS/FAIL per rule
# plus an aggregate compliance score. Recurring failures are the kit's
# enforcement gaps -- exactly what harness-propose should pick up.
#
# Usage:
#   pwsh test-compliance.ps1 -SessionId <id> [-RepoRoot <path>] [-Json]
#   pwsh test-compliance.ps1 -SessionId <id> -ExpectWiki -ExpectFeatureChange
#
# Flags:
#   -SessionId <id>           the kit session id from ~/.agents/session-state/
#   -RepoRoot <path>          repo where the agent worked (default: cwd)
#   -ExpectWiki               assert .wiki/ should exist + index.md present
#   -ExpectFeatureChange      assert .wiki/features.md was touched in session
#   -ExpectKitTree            assert .kit/context/memory.md exists
#   -ForbidRepoHandoffs       assert agent did NOT write to repo-level
#                             handoff files (test for kit precedence)
#   -RepoHandoffPaths <list>  comma-sep paths to check for forbidden writes
#                             (e.g., "agents/handoffs/latest.md,hand_off.md")
#   -MinAgentsRecorded <n>    assert >=N agents in workflow-evidence
#   -Json                     machine-readable output
#
# Exit codes:
#   0 = all assertions passed
#   1 = >=1 hard violation (CRITICAL or HIGH severity)
#   2 = soft violations only (MEDIUM/LOW)

param(
    [Parameter(Mandatory=$true)][string]$SessionId,
    [string]$RepoRoot = (Get-Location).Path,
    [switch]$ExpectWiki,
    [switch]$ExpectFeatureChange,
    [switch]$ExpectKitTree,
    [switch]$ForbidRepoHandoffs,
    [string]$RepoHandoffPaths = "agents/handoffs/latest.md,hand_off.md,repo-handoffs/latest.md,agents/session_state.md",
    [int]$MinAgentsRecorded = 0,
    [switch]$Json
)

. (Join-Path $PSScriptRoot "../bundle/global/.agents/tools/_paths.ps1") -ErrorAction SilentlyContinue
if (-not $script:SessionRoot) {
    $script:SessionRoot = if ($env:AGENTS_SESSION_ROOT) { $env:AGENTS_SESSION_ROOT } else { Join-Path $HOME ".agents/session-state" }
}

$sessDir = Join-Path $script:SessionRoot $SessionId
$results = @()

function Add-Result {
    param([string]$Name, [string]$Status, [string]$Severity, [string]$Detail = "")
    $script:results += @{
        name = $Name
        status = $Status
        severity = $Severity
        detail = $Detail
    }
}

# Assertion 1: session dir exists
if (Test-Path $sessDir) {
    Add-Result "session_dir_exists" "PASS" "HIGH" $sessDir
} else {
    Add-Result "session_dir_exists" "FAIL" "CRITICAL" "no session at $sessDir -- did pre-session.ps1 run?"
    # If session dir missing, most other assertions are meaningless
    if ($Json) {
        @{ session_id = $SessionId; results = $results; score = "0/1"; ok = $false } | ConvertTo-Json -Compress -Depth 5 | Write-Output
    } else {
        Write-Host "FAIL: session dir missing -- aborting other checks"
    }
    exit 1
}

# Assertion 2: state.json with required gates
$statePath = Join-Path $sessDir "state.json"
if (Test-Path $statePath) {
    try {
        $state = Get-Content $statePath -Raw -Encoding UTF8 | ConvertFrom-Json
        $required = @("scope_classified", "context_loaded", "implementation_done", "verification_evidence", "handoff_written")
        $marked = @()
        $missing = @()
        foreach ($g in $required) {
            if ($state.gates.$g) { $marked += $g } else { $missing += $g }
        }
        if ($missing.Count -eq 0) {
            Add-Result "all_gates_marked" "PASS" "HIGH" ($marked -join ", ")
        } else {
            Add-Result "all_gates_marked" "FAIL" "HIGH" "missing: $($missing -join ', ')"
        }

        # Iron Law: verification_evidence specifically
        if ($state.gates.verification_evidence) {
            Add-Result "iron_law_verification" "PASS" "CRITICAL" ""
        } else {
            Add-Result "iron_law_verification" "FAIL" "CRITICAL" "verification_evidence gate NOT marked -- agent claimed completion without fresh evidence"
        }
    } catch {
        Add-Result "all_gates_marked" "FAIL" "HIGH" "state.json malformed: $($_.Exception.Message)"
    }
} else {
    Add-Result "all_gates_marked" "FAIL" "CRITICAL" "no state.json -- state-init.ps1 didn't run"
}

# Assertion 3: workflow-evidence.json populated
$evPath = Join-Path $sessDir "workflow-evidence.json"
if (Test-Path $evPath) {
    try {
        $ev = Get-Content $evPath -Raw -Encoding UTF8 | ConvertFrom-Json
        $agentCount = if ($ev.agents_spawned) { @($ev.agents_spawned).Count } else { 0 }
        $verifyCount = if ($ev.verifications) { @($ev.verifications).Count } else { 0 }

        if ($MinAgentsRecorded -gt 0) {
            if ($agentCount -ge $MinAgentsRecorded) {
                Add-Result "agents_recorded" "PASS" "HIGH" "$agentCount recorded (>= $MinAgentsRecorded expected)"
            } else {
                Add-Result "agents_recorded" "FAIL" "HIGH" "$agentCount recorded, expected >= $MinAgentsRecorded -- orchestrator skipped -AddAgent calls"
            }
        }

        if ($verifyCount -gt 0) {
            Add-Result "verifications_recorded" "PASS" "MEDIUM" "$verifyCount verification command(s) recorded"
        } else {
            Add-Result "verifications_recorded" "FAIL" "MEDIUM" "no verifications in workflow-evidence -- Iron Law evidence audit fails"
        }
    } catch {
        Add-Result "workflow_evidence_valid" "FAIL" "HIGH" "workflow-evidence.json malformed"
    }
} else {
    Add-Result "workflow_evidence_valid" "FAIL" "HIGH" "no workflow-evidence.json -- agent did not record any evidence"
}

# Assertion 4: handoffs.md written to kit-canonical location
$handoffPath = Join-Path $sessDir "handoffs.md"
if ((Test-Path $handoffPath) -and ((Get-Item $handoffPath).Length -gt 50)) {
    Add-Result "kit_handoff_written" "PASS" "HIGH" "$((Get-Item $handoffPath).Length) bytes at $handoffPath"
} else {
    Add-Result "kit_handoff_written" "FAIL" "HIGH" "no/empty handoffs.md at $handoffPath -- session-private handoff missing"
}

# Assertion 5: forbidden repo-level handoff writes (kit precedence test)
if ($ForbidRepoHandoffs) {
    $forbidden = @($RepoHandoffPaths -split '[,;]' | ForEach-Object { $_.Trim() } | Where-Object { $_ })
    $violations = @()
    foreach ($p in $forbidden) {
        $full = Join-Path $RepoRoot $p
        if (Test-Path $full) {
            $size = (Get-Item $full).Length
            # Larger than 100 bytes = real content was written, not just placeholder
            if ($size -gt 100) {
                $violations += "$p ($size bytes)"
            }
        }
    }
    if ($violations.Count -eq 0) {
        Add-Result "kit_precedence_held" "PASS" "HIGH" "no significant writes to repo-level handoff paths"
    } else {
        Add-Result "kit_precedence_held" "FAIL" "HIGH" "agent wrote to repo-level handoff paths (kit precedence violated): $($violations -join '; ')"
    }
}

# Assertion 6: .wiki/ exists if expected
if ($ExpectWiki) {
    $wikiIdx = Join-Path $RepoRoot ".wiki/index.md"
    $wikiFeat = Join-Path $RepoRoot ".wiki/features.md"
    if ((Test-Path $wikiIdx) -and (Test-Path $wikiFeat)) {
        Add-Result "wiki_present" "PASS" "HIGH" ".wiki/index.md + features.md present"
    } else {
        $missing = @()
        if (-not (Test-Path $wikiIdx))  { $missing += "index.md" }
        if (-not (Test-Path $wikiFeat)) { $missing += "features.md" }
        Add-Result "wiki_present" "FAIL" "HIGH" ".wiki/ incomplete -- missing: $($missing -join ', ') -- agent skipped /wiki-init"
    }
}

# Assertion 7: features.md was actually updated in this session (mtime)
if ($ExpectFeatureChange) {
    $wikiFeat = Join-Path $RepoRoot ".wiki/features.md"
    if (Test-Path $wikiFeat) {
        $featMtime = (Get-Item $wikiFeat).LastWriteTime
        $sessStart = (Get-Item $sessDir).CreationTime
        if ($featMtime -gt $sessStart) {
            Add-Result "features_md_updated" "PASS" "HIGH" "features.md mtime > session start"
        } else {
            Add-Result "features_md_updated" "FAIL" "HIGH" "features.md NOT updated since session start -- wiki rule violated for feature change"
        }
    } else {
        Add-Result "features_md_updated" "FAIL" "HIGH" "no features.md -- wiki not bootstrapped"
    }
}

# Assertion 8: .kit/ tree if expected
if ($ExpectKitTree) {
    $kitMem = Join-Path $RepoRoot ".kit/context/memory.md"
    if (Test-Path $kitMem) {
        Add-Result "kit_tree_present" "PASS" "MEDIUM" ".kit/context/memory.md present"
    } else {
        Add-Result "kit_tree_present" "FAIL" "MEDIUM" "no .kit/context/memory.md -- /kit-init not run"
    }
}

# Assertion 9: review-evidence (if /review session)
$reviewEvPath = Join-Path $sessDir "review-evidence.json"
if (Test-Path $reviewEvPath) {
    try {
        $rev = Get-Content $reviewEvPath -Raw -Encoding UTF8 | ConvertFrom-Json
        if ($rev.tier -and $rev.stages_run) {
            $stagesRun = @($rev.stages_run | ForEach-Object { $_.stage } | Select-Object -Unique)
            $expected = @{
                "INLINE"   = @("verifier")
                "TARGETED" = @("wiki-resolver", "surface", "verifier")
                "FULL"     = @("wiki-resolver", "surface", "consequence", "interaction", "synthesis", "adversarial", "verifier")
            }
            if ($expected.ContainsKey($rev.tier)) {
                $missing = @($expected[$rev.tier] | Where-Object { $stagesRun -notcontains $_ })
                if ($missing.Count -eq 0) {
                    Add-Result "review_tier_stages_match" "PASS" "HIGH" "tier=$($rev.tier) all expected stages ran"
                } else {
                    Add-Result "review_tier_stages_match" "FAIL" "HIGH" "tier=$($rev.tier) missing: $($missing -join ', ') -- agent shortcut the protocol"
                }
            }
        }
    } catch {}
}

# ── Aggregate + output ────────────────────────────────────────────────────────
$pass     = @($results | Where-Object { $_.status -eq "PASS" }).Count
$fail     = @($results | Where-Object { $_.status -eq "FAIL" }).Count
$total    = $results.Count
$critFail = @($results | Where-Object { $_.status -eq "FAIL" -and $_.severity -in @("CRITICAL", "HIGH") }).Count

if ($Json) {
    @{
        session_id = $SessionId
        repo_root = $RepoRoot
        score = "$pass/$total"
        compliance_pct = if ($total -gt 0) { [Math]::Round(($pass / $total) * 100, 1) } else { 0 }
        critical_fails = $critFail
        results = $results
        ok = ($critFail -eq 0)
    } | ConvertTo-Json -Compress -Depth 6 | Write-Output
} else {
    Write-Host ""
    Write-Host "test-compliance -- session $SessionId"
    Write-Host "==========================================="
    Write-Host ""
    foreach ($r in $results) {
        $tag = switch ($r.status) {
            "PASS" { "[PASS]" }
            "FAIL" { "[FAIL]" }
            default { "[????]" }
        }
        $sev = "[$($r.severity)]"
        $line = "$tag $sev $($r.name)"
        if ($r.detail) { $line += " -- $($r.detail)" }
        Write-Host $line
    }
    Write-Host ""
    Write-Host "Score: $pass/$total passed ($(if ($total -gt 0) { [Math]::Round(($pass / $total) * 100, 1) } else { 0 })%)"
    Write-Host "Critical/High fails: $critFail"
    if ($critFail -gt 0) {
        Write-Host "VERDICT: FAIL -- kit compliance violated"
    } elseif ($fail -gt 0) {
        Write-Host "VERDICT: SOFT FAIL -- minor gaps"
    } else {
        Write-Host "VERDICT: PASS"
    }
}

if ($critFail -gt 0) { exit 1 }
elseif ($fail -gt 0) { exit 2 }
exit 0
