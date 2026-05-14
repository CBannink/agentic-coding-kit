#!/usr/bin/env pwsh
# swarm-classifier.ps1
# Decides whether a task should use the SWARM tier (parallel fan-out) or stay
# sequential. Three conditions must ALL hold for swarm eligibility:
#   1. verb is parallel-safe
#   2. scope is fan-out-able (ISOLATED with multi-component, or explicit --swarm)
#   3. user opted in (-OptIn flag, or task starts with one of the swarm verbs)
#
# This is the third axis on top of scope-classifier (ISOLATED/SHARED/CRITICAL)
# and tier (INLINE/TARGETED/FULL/SWARM). Output: JSON with mode + reason.
#
# Usage:
#   swarm-classifier.ps1 -Task "redesign the dashboard"
#   swarm-classifier.ps1 -Task "fix login bug" -OptIn
#   swarm-classifier.ps1 -Task "audit security" -Scope ISOLATED -FileCount 12

param(
    [Parameter(Mandatory)][string]$Task,
    [string]$Scope = "",
    [int]$FileCount = 0,
    [switch]$OptIn
)

# Parallel-safe verbs -- cheap divergence is a feature, not a bug
$swarmVerbs = @(
    "audit", "explore", "port", "redesign", "refactor",
    "bulk-migrate", "bulk migrate", "migrate", "modernize",
    "pentest", "security-review", "security review",
    "ethical-hack", "ethical hack", "red-team", "red team",
    "review", "scan", "sweep", "survey",
    "brainstorm", "ideate", "options", "variants"
)

# Sequential-only verbs -- coordination cost > work saved
$sequentialVerbs = @(
    "fix", "implement", "ship", "deploy", "release",
    "migrate-schema", "migrate schema", "add", "build feature",
    "patch", "hotfix", "rollback"
)

$taskLower = $Task.ToLower()

$matchedSwarmVerb = $null
foreach ($v in $swarmVerbs) {
    if ($taskLower -like "*$v*") {
        $matchedSwarmVerb = $v
        break
    }
}

$matchedSeqVerb = $null
foreach ($v in $sequentialVerbs) {
    if ($taskLower -like "*$v*") {
        $matchedSeqVerb = $v
        break
    }
}

# --- Decision logic ---
$mode = "sequential"
$reason = "default mode"

if ($matchedSeqVerb -and -not $OptIn) {
    $mode = "sequential"
    $reason = "task verb '$matchedSeqVerb' is sequential-only -- focused work, swarm hurts"
} elseif ($Scope -eq "CRITICAL") {
    $mode = "sequential"
    $reason = "CRITICAL scope never swarms -- single-writer discipline required"
} elseif ($OptIn -and $matchedSwarmVerb) {
    $mode = "swarm-fanout"
    $reason = "user opted in (--swarm) AND verb '$matchedSwarmVerb' is parallel-safe"
} elseif ($OptIn) {
    $mode = "swarm-fanout"
    $reason = "user opted in (--swarm) -- proceeding despite no verb match (caller takes responsibility)"
} elseif ($matchedSwarmVerb -and $Scope -eq "ISOLATED" -and $FileCount -ge 4) {
    $mode = "swarm-fanout"
    $reason = "verb '$matchedSwarmVerb' + ISOLATED scope + $FileCount files -- strong fan-out signal"
} elseif ($matchedSwarmVerb -and $FileCount -ge 8) {
    $mode = "swarm-fanout"
    $reason = "verb '$matchedSwarmVerb' + $FileCount files -- large parallel-safe surface"
} elseif ($matchedSwarmVerb) {
    # Verb matches but scope/count not strong enough -- recommend parallel reviewers
    # rather than full fan-out. Sequential implementer + N reviewers concurrently.
    $mode = "swarm-review"
    $reason = "verb '$matchedSwarmVerb' is parallel-safe but scope is small -- use parallel reviewers, sequential implementer"
}

$result = [ordered]@{
    mode          = $mode
    reason        = $reason
    matched_verb  = if ($matchedSwarmVerb) { $matchedSwarmVerb } elseif ($matchedSeqVerb) { $matchedSeqVerb } else { "" }
    opt_in        = [bool]$OptIn
    scope         = $Scope
    file_count    = $FileCount
}

Write-Output ($result | ConvertTo-Json -Compress)
