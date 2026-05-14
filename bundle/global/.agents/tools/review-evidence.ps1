#!/usr/bin/env pwsh
# review-evidence.ps1 -- record which review stages ran for a session.
# Cross-referenced by post-session.ps1 to detect tier-vs-stages mismatches
# (e.g., FULL tier picked but only 4 of 8+ expected stages ran).
#
# Why: the /review skill is a markdown contract. Without an evidence trail,
# agents can shortcut from FULL down to TARGETED-style work without anyone
# noticing. This tool records each stage as it completes; post-session
# warns on mismatches so the self-improvement loop catches recurring
# shortcuts.
#
# Usage:
#   pwsh review-evidence.ps1 -SessionId <id> -Stage <name> [-AgentsRun <list>] [-Notes <txt>]
#   pwsh review-evidence.ps1 -SessionId <id> -SetTier <FULL|TARGETED|INLINE>
#   pwsh review-evidence.ps1 -SessionId <id> -Status   # report current state
#   pwsh review-evidence.ps1 -SessionId <id> -CheckMismatch   # exit 2 if tier-vs-stages mismatch
#
# Stage names (canonical):
#   wiki-resolver       -- wiki-resolver.ps1 invoked + prompt_block extracted
#   surface             -- software/security/api/testing/perf/maint/data-migration reviewers
#   consequence         -- consequence-agent ran (when public interface / shared type changed)
#   interaction         -- caller-callee / shared-contract / state-flow reviewers
#   synthesis           -- synthesis-reviewer merged outputs
#   adversarial         -- adversarial-reviewer cross-provider attack pass
#   verifier            -- false-positive-verifier confirmed file:line evidence
#
# Output (JSON for -Status / -CheckMismatch):
#   {
#     ok: true,
#     session_id: "...",
#     tier: "FULL",
#     stages_run: [{stage, agents, notes, ts}],
#     expected_for_tier: ["surface", "consequence", "interaction", "synthesis", "adversarial", "verifier"],
#     missing_stages: ["adversarial"],
#     mismatch: true,
#     warning: "FULL tier but adversarial stage was skipped..."
#   }
#
# Exit codes:
#   0 = ok / stage recorded / no mismatch
#   1 = error
#   2 = mismatch detected (use with -CheckMismatch in post-session)

param(
    [Parameter(Mandatory=$true)][string]$SessionId,
    [string]$Stage = "",
    [string]$AgentsRun = "",
    [string]$Notes = "",
    [ValidateSet("FULL", "TARGETED", "INLINE", "")][string]$SetTier = "",
    [switch]$Status,
    [switch]$CheckMismatch
)

. (Join-Path $PSScriptRoot "_paths.ps1")

$sessDir = Join-Path $script:SessionRoot $SessionId
New-Item -ItemType Directory -Path $sessDir -Force | Out-Null
$evPath = Join-Path $sessDir "review-evidence.json"

# Load existing state or initialize. PSCustomObject -> hashtable for PS 5.1
# compatibility (no -AsHashtable on the older shell).
function ConvertTo-Hashtable {
    param($Obj)
    if ($null -eq $Obj) { return @{} }
    $ht = @{}
    foreach ($p in $Obj.PSObject.Properties) {
        $v = $p.Value
        if ($v -is [System.Management.Automation.PSCustomObject]) {
            $ht[$p.Name] = ConvertTo-Hashtable $v
        } elseif ($v -is [System.Collections.IEnumerable] -and -not ($v -is [string])) {
            $ht[$p.Name] = @($v | ForEach-Object {
                if ($_ -is [System.Management.Automation.PSCustomObject]) { ConvertTo-Hashtable $_ } else { $_ }
            })
        } else {
            $ht[$p.Name] = $v
        }
    }
    return $ht
}

$state = @{}
if (Test-Path $evPath) {
    try {
        $loaded = Get-Content $evPath -Raw -Encoding UTF8 | ConvertFrom-Json
        $state = ConvertTo-Hashtable $loaded
    } catch { $state = @{} }
}
if (-not $state.ContainsKey("session_id")) { $state.session_id = $SessionId }
if (-not $state.ContainsKey("tier")) { $state.tier = "" }
if (-not $state.ContainsKey("stages_run")) { $state.stages_run = @() }

# Tier-required stage map. Keep loose -- skill descriptions allow conditional
# specialists, so "expected" is a minimum bar, not a maximum.
$expectedByTier = @{
    "INLINE"   = @("verifier")
    "TARGETED" = @("wiki-resolver", "surface", "verifier")
    "FULL"     = @("wiki-resolver", "surface", "consequence", "interaction", "synthesis", "adversarial", "verifier")
}

function Save-State {
    $state | ConvertTo-Json -Depth 6 | Set-Content -Path $evPath -Encoding UTF8
}

function Out-Result {
    param([hashtable]$Data, [int]$ExitCode = 0)
    $Data | ConvertTo-Json -Compress -Depth 6 | Write-Output
    exit $ExitCode
}

# Set tier mode
if ($SetTier) {
    $state.tier = $SetTier
    Save-State
    Out-Result @{ ok = $true; session_id = $SessionId; tier = $SetTier; action = "tier set" } 0
}

# Record a stage
if ($Stage) {
    $entry = @{
        stage = $Stage
        agents = if ($AgentsRun) { @($AgentsRun -split '[,;]' | ForEach-Object { $_.Trim() } | Where-Object { $_ }) } else { @() }
        notes = $Notes
        ts = (Get-Date).ToString("o")
    }
    $state.stages_run = @($state.stages_run + $entry)
    Save-State
    Out-Result @{ ok = $true; session_id = $SessionId; recorded = $Stage; total_stages = $state.stages_run.Count } 0
}

# Status / mismatch report
$tier = $state.tier
$stagesRun = @($state.stages_run | ForEach-Object { $_.stage } | Select-Object -Unique)
$expected = if ($tier -and $expectedByTier.ContainsKey($tier)) { $expectedByTier[$tier] } else { @() }
$missing = @($expected | Where-Object { $stagesRun -notcontains $_ })
$mismatch = ($missing.Count -gt 0)

$warning = $null
if ($mismatch) {
    $warning = "Tier=$tier expected stages [$($expected -join ', ')] but missing: [$($missing -join ', ')]. Did the agent shortcut the protocol?"
}

$result = @{
    ok = $true
    session_id = $SessionId
    tier = $tier
    stages_run = @($stagesRun)
    expected_for_tier = @($expected)
    missing_stages = @($missing)
    mismatch = $mismatch
    warning = $warning
    total_records = $state.stages_run.Count
}

if ($CheckMismatch) {
    if ($mismatch) {
        Out-Result $result 2
    }
    Out-Result $result 0
}

if ($Status) {
    Out-Result $result 0
}

# No flag specified -- assume status
Out-Result $result 0
