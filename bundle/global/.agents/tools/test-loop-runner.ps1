#!/usr/bin/env pwsh
# test-loop-runner.ps1
#
# Mechanical test-iterate runner for the /test-gen skill.
# Runs a test command up to MaxRounds times, writing per-round logs.
# The agent (not this tool) reads logs and fixes code between rounds.
#
# Usage:
#   pwsh ~/.agents/tools/test-loop-runner.ps1 `
#       -SessionId "abc123" `
#       -TestCommand "npm test" `
#       [-TestFile "src/__tests__/foo.test.ts"] `
#       [-MaxRounds 5] `
#       [-Json]
#
# Exit codes:
#   0  — at least one round passed (final exit code 0)
#   1  — all rounds exhausted without passing

param(
    [Parameter(Mandatory = $true)]
    [string]$SessionId,

    [Parameter(Mandatory = $true)]
    [string]$TestCommand,

    [string]$TestFile = "",

    [int]$MaxRounds = 5,

    [switch]$Json
)

. (Join-Path $PSScriptRoot "_paths.ps1")

$sessionDir = Get-SessionDir $SessionId
New-Item -ItemType Directory -Path $sessionDir -Force | Out-Null

# Build the effective command: if TestFile is specified, append it
$effectiveCommand = if ($TestFile) { "$TestCommand $TestFile" } else { $TestCommand }

# Round results accumulator
$roundsDetail = [System.Collections.ArrayList]::new()

$finalExitCode = 1
$passedRound   = 0

for ($round = 1; $round -le $MaxRounds; $round++) {

    $logPath = Join-Path $sessionDir "test-round-$round.log"

    # Run the test command and capture combined stdout+stderr
    $output = & $env:ComSpec /c "$effectiveCommand" 2>&1
    $exitCode = $LASTEXITCODE

    # Write raw log
    $output | Set-Content -Path $logPath -Encoding utf8

    # --- Parse failure summary ---
    $outputText = $output -join "`n"

    # Attempt to count failures from common runner output patterns:
    # Jest:   "X failed, Y passed"  /  "X tests failed"
    # pytest: "X failed"
    # Go:     "FAIL" lines
    $failCount = 0
    $passCount = 0

    # Jest / Vitest style
    if ($outputText -match '(\d+)\s+failed') {
        $failCount = [int]$Matches[1]
    }
    if ($outputText -match '(\d+)\s+passed') {
        $passCount = [int]$Matches[1]
    }
    # pytest style: "X failed, Y passed" or "X passed"
    if ($outputText -match 'failed[,\s]+(\d+)\s+passed') {
        $passCount = [int]$Matches[1]
    }

    # Truncate failure extract to first 2000 chars to keep summary readable
    $failureExtract = ""
    if ($exitCode -ne 0) {
        $failureExtract = if ($outputText.Length -gt 2000) {
            $outputText.Substring(0, 2000) + "`n[... truncated — see log for full output ...]"
        } else {
            $outputText
        }
    }

    $roundRecord = [pscustomobject]@{
        round            = $round
        exit_code        = $exitCode
        failures         = $failCount
        passed           = $passCount
        log_path         = $logPath
        failure_extract  = $failureExtract
    }
    [void]$roundsDetail.Add($roundRecord)

    if ($exitCode -eq 0) {
        $finalExitCode = 0
        $passedRound   = $round
        break
    }

    # If not the last round, signal the agent to fix before the next round.
    # The tool does NOT fix code — it only runs and records.
    if (-not $Json) {
        Write-Output "test-loop-runner: round $round/$MaxRounds FAIL ($failCount failures) — see $logPath"
    }
}

$finalStatus = if ($finalExitCode -eq 0) { "pass" } else { "fail" }

$summary = [pscustomobject]@{
    ok             = ($finalExitCode -eq 0)
    rounds         = if ($passedRound -gt 0) { $passedRound } else { $MaxRounds }
    max_rounds     = $MaxRounds
    final_exit_code = $finalExitCode
    final_status   = $finalStatus
    test_command   = $effectiveCommand
    rounds_detail  = @($roundsDetail)
}

$summaryPath = Join-Path $sessionDir "test-loop-summary.json"
$summary | ConvertTo-Json -Depth 6 | Set-Content -Path $summaryPath -Encoding utf8

Sync-EvalArtifactMirror -SessionId $SessionId -SourcePath $summaryPath -TargetName "test-loop-summary.json"

if ($Json) {
    Write-Output ($summary | ConvertTo-Json -Compress -Depth 6)
} else {
    if ($finalExitCode -eq 0) {
        Write-Output "test-loop-runner: PASS after $($summary.rounds)/$MaxRounds rounds (0 failures)"
    } else {
        $lastRound = $roundsDetail[$roundsDetail.Count - 1]
        Write-Output "test-loop-runner: FAIL after $MaxRounds/$MaxRounds rounds ($($lastRound.failures) failures in last round) — see $summaryPath"
    }
}

exit $finalExitCode
