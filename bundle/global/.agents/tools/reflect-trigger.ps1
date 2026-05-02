#!/usr/bin/env pwsh
# reflect-trigger.ps1
# Reads global + repo-local reflections.md, returns the unaddressed count and
# a JSON payload the orchestrator can act on. This is the self-improvement
# loop's enforcement point -- pre-session gates on it, the /reflect skill
# consumes it, and post-session populates the underlying files.
#
# Usage:
#   pwsh ~/.agents/tools/reflect-trigger.ps1
#   pwsh ~/.agents/tools/reflect-trigger.ps1 -RepoRoot "C:\path\to\repo"
#   pwsh ~/.agents/tools/reflect-trigger.ps1 -Json    # machine-readable only
#
# Output (Json mode):
#   {
#     "status": "ok" | "soft" | "mandatory",
#     "count_repo": 0, "count_global": 0, "count_total": 0,
#     "threshold_soft": 3, "threshold_mandatory": 5,
#     "entries": [ {file, line, class, pattern, evidence}, ... ],
#     "recommended_action": "none" | "log-and-proceed" | "run-/reflect"
#   }
#
# Exit codes:
#   0 = ok or soft (proceed)
#   2 = mandatory (orchestrator should run /reflect before continuing)

param(
    [string]$RepoRoot = "",
    [int]$SoftThreshold = 3,
    [int]$MandatoryThreshold = 5,
    [switch]$Json
)

. (Join-Path $PSScriptRoot "_paths.ps1")

if (-not $RepoRoot) { $RepoRoot = (Get-Location).Path }

$repoPath   = Join-Path $RepoRoot ".codex/context/reflections.md"
$globalPath = Join-Path $script:AgentsRoot "context/reflections.md"

function Parse-Reflections([string]$path, [string]$scope) {
    if (-not (Test-Path $path)) { return @() }
    $entries = [System.Collections.ArrayList]::new()
    $lines = Get-Content $path
    for ($i = 0; $i -lt $lines.Count; $i++) {
        $l = $lines[$i]
        if ($l -match "^- \[" -and $l -notmatch "promoted|archived") {
            $class = if ($l -match "\[class:([^\]]+)\]") { $Matches[1] } else { "unknown" }
            # Pattern + Evidence are on following lines
            $pattern = ""
            $evidence = ""
            if ($i + 1 -lt $lines.Count -and $lines[$i+1] -match "^\s*Pattern:\s*(.*)$") {
                $pattern = $Matches[1].Trim()
            }
            if ($i + 2 -lt $lines.Count -and $lines[$i+2] -match "^\s*Evidence:\s*(.*)$") {
                $evidence = $Matches[1].Trim()
            }
            [void]$entries.Add([pscustomobject]@{
                file     = $path
                scope    = $scope
                line     = $i + 1
                class    = $class
                pattern  = $pattern
                evidence = $evidence
            })
        }
    }
    return @($entries)
}

$repoEntries   = Parse-Reflections $repoPath "repo"
$globalEntries = Parse-Reflections $globalPath "global"
$all = @($repoEntries) + @($globalEntries)
$total = $all.Count

$status = if ($total -ge $MandatoryThreshold) { "mandatory" }
          elseif ($total -ge $SoftThreshold)  { "soft" }
          else { "ok" }

$action = switch ($status) {
    "mandatory" { "run-/reflect" }
    "soft"      { "log-and-proceed" }
    default     { "none" }
}

$result = [ordered]@{
    status              = $status
    count_repo          = $repoEntries.Count
    count_global        = $globalEntries.Count
    count_total         = $total
    threshold_soft      = $SoftThreshold
    threshold_mandatory = $MandatoryThreshold
    entries             = $all
    recommended_action  = $action
    repo_path           = $repoPath
    global_path         = $globalPath
}

if ($Json) {
    Write-Output ($result | ConvertTo-Json -Depth 5 -Compress)
} else {
    Write-Host "Reflection gate: $status ($total unaddressed: repo=$($repoEntries.Count), global=$($globalEntries.Count))"
    Write-Host "Recommended:     $action"
    if ($total -gt 0) {
        Write-Host ""
        Write-Host "Entries:"
        foreach ($e in $all) {
            Write-Host "  [$($e.scope) $($e.class)] $($e.pattern)"
            if ($e.evidence) { Write-Host "    Evidence: $($e.evidence)" }
        }
    }
}

if ($status -eq "mandatory") { exit 2 } else { exit 0 }
