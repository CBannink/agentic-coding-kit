#!/usr/bin/env pwsh
# harness-propose.ps1
# The meta-pattern: when a reflection failure has recurred N+ times AND
# implicates the kit's own discipline (not repo-specific), generate a written
# proposal for a harness-level change. NEVER auto-applies. Human reviews via
# harness-review.ps1, implements manually.
#
# Detection logic:
#   - Read global reflections.md (post-session writes here)
#   - Read decisions.jsonl (skip patterns we've already accepted/rejected)
#   - Group entries by class+pattern signature
#   - For groups with seen_count >= -MinOccurrences (default 3):
#     - If pattern matches kit-level keyword set -> generate proposal
#     - Else: leave for normal /reflect (repo-level promotion)
#
# Output: writes <id>.md proposal files to ${AGENTS_HOME}/proposals/
#         outputs JSON summary of new proposals
#
# Safety boundaries (intentional):
#   - Never modifies any kit file
#   - Never auto-applies anything
#   - Only describes the change; user implements
#   - Can be re-run idempotently (existing proposals not duplicated)
#   - Decisions log prevents re-proposing rejected patterns

param(
    [int]$MinOccurrences = 5,                # raised from 3 -- avoid noise; only fire on real recurrence
    [int]$RecencyWindowDays = 30,            # only count occurrences within this window (recent pattern, not stale accumulation)
    [int]$MinRecentOccurrences = 3,          # of total, at least this many must be recent
    [string]$ReflectionsPath = "",
    [switch]$Json,
    [switch]$DryRun
)

. (Join-Path $PSScriptRoot "_paths.ps1")

if (-not $ReflectionsPath) {
    $ReflectionsPath = Join-Path $script:AgentsRoot "context/reflections.md"
}
$proposalsDir = Join-Path $script:AgentsRoot "proposals"
$decisionsLog = Join-Path $proposalsDir "decisions.jsonl"
New-Item -ItemType Directory -Path $proposalsDir -Force | Out-Null

# Patterns that imply harness-level fix (vs repo-level).
# Tightened: only specific kit-vocabulary terms that wouldn't appear in a
# repo's own context. "session" / "workflow" / "register" were too generic.
$kitLevelSignals = @(
    'gate skipped', 'gate marked', 'tier overridden', 'tier rec',
    'agent cap', 'subagent stop', 'specialist-memory', 'state-gate', 'state-init',
    'scope-classifier', 'swarm-classifier', 'auto-consolidate', 'reflect-trigger',
    'workflow-evidence missing', 'workflow-evidence skipped',
    'pre-session', 'post-session', 'handoff index', 'reflection capture',
    'verification gate', 'verification command', 'verification skipped'
)

function Test-IsKitLevel([string]$pattern) {
    $lower = $pattern.ToLower()
    foreach ($sig in $kitLevelSignals) {
        if ($lower -match [regex]::Escape($sig)) { return $true }
    }
    return $false
}

function Get-PatternHash([string]$class, [string]$pattern) {
    # Normalize so trivial variations (numbers, paths) don't fragment the count
    $key = "$class|$pattern".ToLower()
    $key = $key -replace '\b\d+\b', 'N'
    $key = $key -replace '[a-f0-9]{8,}', 'HEX'
    $key = $key -replace '\d{4}-\d{2}-\d{2}', 'DATE'
    $key = $key -replace '[a-z]:[\\\/][^\s"'']+', 'PATH'
    $key = $key -replace '/[^\s"'']+', 'PATH'
    $bytes = [System.Text.Encoding]::UTF8.GetBytes($key)
    $hash  = [System.Security.Cryptography.SHA256]::Create().ComputeHash($bytes)
    return ([System.BitConverter]::ToString($hash) -replace '-', '').Substring(0, 12)
}

# Read reflections
if (-not (Test-Path $ReflectionsPath)) {
    if ($Json) { Write-Output (@{ proposals = @(); reason = "no reflections file" } | ConvertTo-Json -Compress) }
    else       { Write-Host "No reflections at $ReflectionsPath -- nothing to propose." }
    exit 0
}

$lines = Get-Content $ReflectionsPath -Encoding UTF8
$entries = @()
$current = $null
for ($i = 0; $i -lt $lines.Count; $i++) {
    $l = $lines[$i]
    if ($l -match "^- \[(\d{4}-\d{2}-\d{2})\].*?\[class:([^\]]+)\]") {
        if ($current) { $entries += $current }
        $current = [pscustomobject]@{
            date = $Matches[1]
            class = $Matches[2]
            pattern = ""
            evidence = ""
        }
    } elseif ($current -and $l -match "^\s*Pattern:\s*(.*)$") {
        $current.pattern = $Matches[1].Trim()
    } elseif ($current -and $l -match "^\s*Evidence:\s*(.*)$") {
        $current.evidence = $Matches[1].Trim()
    }
}
if ($current) { $entries += $current }
$entries = @($entries | Where-Object { $_.pattern })

# Group + count using pattern hash.
# Track total count AND recent count separately. The recent count is what matters
# for "is this still happening" -- a pattern with 10 occurrences from 2024 and
# zero from this month isn't actionable.
$today = Get-Date
$recencyCutoff = $today.AddDays(-$RecencyWindowDays)

$grouped = @{}
foreach ($e in $entries) {
    $h = Get-PatternHash $e.class $e.pattern
    if (-not $grouped.ContainsKey($h)) {
        $grouped[$h] = [pscustomobject]@{
            hash = $h; class = $e.class; pattern = $e.pattern
            count = 0; recent_count = 0; evidences = @()
        }
    }
    $grouped[$h].count++
    # Is this entry within the recency window?
    try {
        $entryDate = [datetime]::ParseExact($e.date, "yyyy-MM-dd", $null)
        if ($entryDate -ge $recencyCutoff) { $grouped[$h].recent_count++ }
    } catch {}
    if ($grouped[$h].evidences.Count -lt 5 -and $e.evidence) {
        $grouped[$h].evidences += $e.evidence
    }
}

# Read decisions log to skip already-handled patterns
$alreadyDecided = @{}
if (Test-Path $decisionsLog) {
    foreach ($d in Get-Content $decisionsLog -Encoding UTF8) {
        try {
            $dec = $d | ConvertFrom-Json
            if ($dec.pattern_hash) { $alreadyDecided[$dec.pattern_hash] = $dec.action }
        } catch {}
    }
}

# Existing proposal IDs (don't duplicate)
$existingHashes = @{}
Get-ChildItem $proposalsDir -Filter "*.md" -ErrorAction SilentlyContinue | ForEach-Object {
    $head = Get-Content $_.FullName -Encoding UTF8 -TotalCount 5 -ErrorAction SilentlyContinue
    foreach ($l in $head) {
        if ($l -match "pattern_hash:\s*([A-Fa-f0-9]+)") {
            $existingHashes[$Matches[1]] = $_.Name
        }
    }
}

$newProposals = New-Object System.Collections.ArrayList
$skipReasons  = @{}

foreach ($g in $grouped.Values | Sort-Object count -Descending) {
    # Ordered cheap-to-expensive checks. Total threshold first, then recency,
    # then exclusion lists, then kit-level routing.
    if ($g.count -lt $MinOccurrences)              { $skipReasons[$g.hash] = "count<$MinOccurrences (have $($g.count))"; continue }
    if ($g.recent_count -lt $MinRecentOccurrences) { $skipReasons[$g.hash] = "recent<$MinRecentOccurrences (have $($g.recent_count) in last $RecencyWindowDays days)"; continue }
    if ($alreadyDecided.ContainsKey($g.hash))      { $skipReasons[$g.hash] = "decided:$($alreadyDecided[$g.hash])"; continue }
    if ($existingHashes.ContainsKey($g.hash))      { $skipReasons[$g.hash] = "proposal-exists"; continue }
    if (-not (Test-IsKitLevel $g.pattern))         { $skipReasons[$g.hash] = "not-kit-level (use /reflect)"; continue }

    # Emit a proposal
    $proposalId = "$(Get-Date -Format 'yyyy-MM-dd')-$($g.hash.Substring(0, 6))"
    $proposalPath = Join-Path $proposalsDir "$proposalId.md"

    # Heuristic suggestions based on class
    $suggestionByClass = @{
        gating       = "Consider tightening the relevant gate. Likely target: state-init.ps1 (add to required gates) or state-gate.ps1 (raise the cap or block earlier)."
        verification = "Consider making the verification mechanical instead of agent-marked. Likely target: test-loop.ps1 (add the check) or workflow-evidence.ps1 (require the field)."
        routing      = "Consider tightening the classifier. Likely target: scope-classifier.ps1 (add pattern), swarm-classifier.ps1 (add verb), or pre-session.ps1 (adjust tier rec)."
        noise        = "Consider tightening the discipline upstream. Likely target: post-session.ps1 (truncate at write time) or the relevant skill file (clarify the limit)."
    }
    $suggestion = if ($suggestionByClass.ContainsKey($g.class)) { $suggestionByClass[$g.class] } else { "Generic kit-level pattern. Inspect occurrences and decide which file to amend." }

    $proposalBody = @"
---
proposal_id: $proposalId
pattern_hash: $($g.hash)
class: $($g.class)
seen_count: $($g.count)
recent_count: $($g.recent_count)
recency_window_days: $RecencyWindowDays
generated_at: $(Get-Date -Format "o")
status: pending
---

# Harness Proposal: $($g.pattern.Substring(0, [Math]::Min(80, $g.pattern.Length)))

## Pattern (recurring)

> $($g.pattern)

Class: ``$($g.class)``  | Seen total: **$($g.count)** | Recent ($RecencyWindowDays days): **$($g.recent_count)**

## Evidence

$(if ($g.evidences.Count -gt 0) {
    ($g.evidences | ForEach-Object { "- $_" }) -join "`n"
} else {
    "(no evidence captured beyond the pattern itself)"
})

## Suggested direction

$suggestion

## Risks

- A harness-level change has GLOBAL blast radius (every repo, every session).
- Wrong call ships a kit-wide regression. Easier to add than remove.
- Prefer the smallest possible change that addresses the recurrence.
- Always test against an isolated session repo before adopting.

## Review

This is a PROPOSAL. The harness will not auto-apply it. Decide and (if accepting)
implement manually. Track decision with:

``````
pwsh ~/.agents/tools/harness-review.ps1 -ProposalId $proposalId -Action accept|reject|defer -Note "..."
``````
"@

    if (-not $DryRun) {
        Set-Content -Path $proposalPath -Value $proposalBody -Encoding UTF8
    }
    [void]$newProposals.Add([pscustomobject]@{
        proposal_id = $proposalId
        pattern_hash = $g.hash
        class = $g.class
        count = $g.count
        path = $proposalPath
        pattern_preview = $g.pattern.Substring(0, [Math]::Min(100, $g.pattern.Length))
    })
}

$summary = [ordered]@{
    new_proposals = @($newProposals)
    skipped       = $skipReasons
    proposals_dir = $proposalsDir
    decisions_log = $decisionsLog
    dry_run       = [bool]$DryRun
}

if ($Json) {
    Write-Output (($summary | ConvertTo-Json -Depth 5 -Compress))
} else {
    Write-Host "harness-propose: $($newProposals.Count) new proposal(s)"
    foreach ($p in $newProposals) {
        Write-Host "  $($p.proposal_id)  [$($p.class)]  count=$($p.count)  $($p.pattern_preview)"
        Write-Host "    $($p.path)"
    }
    if ($newProposals.Count -gt 0) {
        Write-Host ""
        Write-Host "Review with: pwsh ~/.agents/tools/harness-review.ps1"
    }
}
exit 0
