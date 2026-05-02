#!/usr/bin/env pwsh
# test-loop.ps1
# The heartbeat. Executes the project's test/build command, captures structured
# output, and marks the verification_evidence gate on pass. On fail, formats
# the failure for agent diagnosis. On 3-in-a-row same-signature fail, escalates
# to "stuck" so the agent stops doubling down.
#
# Usage:
#   pwsh ~/.agents/tools/test-loop.ps1 -SessionId <id> -Command "npm test"
#   pwsh ~/.agents/tools/test-loop.ps1 -SessionId <id> -Command "pytest -x" -TailLines 80
#   pwsh ~/.agents/tools/test-loop.ps1 -SessionId <id> -Command "go test ./..." -PassOnExitCode 0,1
#
# Pulls verification discipline from "agent must remember to test" to
# "harness enforces it." Wire into /build, /refactor, /redesign as the
# canonical verification step. Agent calls it; agent doesn't decide whether to.
#
# Output: JSON to stdout AND to ${session}/test-loop-runs.jsonl (append).
# Exit codes: 0 = pass, 1 = fail (try again), 3 = stuck (escalate to user).

param(
    [Parameter(Mandatory)][string]$SessionId,
    [Parameter(Mandatory)][string]$Command,
    [int[]]$PassOnExitCode = @(0),
    [int]$TailLines = 60,
    [int]$TimeoutSeconds = 600,
    [int]$StuckThreshold = 3,
    [switch]$NoGateMark
)

. (Join-Path $PSScriptRoot "_paths.ps1")

$sessionDir = Get-SessionDir $SessionId
if (-not (Test-Path $sessionDir)) {
    Write-Error "Session dir not found: $sessionDir -- run pre-session.ps1 first."
    exit 1
}

$runsLog     = Join-Path $sessionDir "test-loop-runs.jsonl"
$capturesDir = Join-Path $sessionDir "test-captures"
New-Item -ItemType Directory -Path $capturesDir -Force | Out-Null

# Iteration counter -- count existing entries in the runs log
$iteration = 1
if (Test-Path $runsLog) {
    $iteration = @(Get-Content $runsLog -ErrorAction SilentlyContinue).Count + 1
}

$capturePath = Join-Path $capturesDir ("iter-{0:000}.log" -f $iteration)

# Run via the .NET Process API directly. PS5.1's Start-Process has a known bug
# where ExitCode returns null when streams are redirected -- the .NET API doesn't
# have that issue. Lower overhead than Start-Job (no separate runspace).
$start = Get-Date
$timedOut = $false

$psi = New-Object System.Diagnostics.ProcessStartInfo
$psi.FileName = "cmd.exe"
$psi.Arguments = "/c $Command"
$psi.RedirectStandardOutput = $true
$psi.RedirectStandardError  = $true
$psi.UseShellExecute = $false
$psi.CreateNoWindow  = $true

$proc = [System.Diagnostics.Process]::Start($psi)
# Read streams asynchronously so a buffer-fill doesn't deadlock the wait
$outTask = $proc.StandardOutput.ReadToEndAsync()
$errTask = $proc.StandardError.ReadToEndAsync()

$finished = $proc.WaitForExit($TimeoutSeconds * 1000)
if (-not $finished) {
    try { $proc.Kill() } catch {}
    $timedOut = $true
    $exitCode = -1
} else {
    # Drain remaining buffered output, then read ExitCode (reliable post-exit).
    $proc.WaitForExit()
    $exitCode = $proc.ExitCode
}

$durationMs = [int]((Get-Date) - $start).TotalMilliseconds

# Combine stdout + stderr into the canonical capture file
$stdout = ""
$stderr = ""
try { $stdout = $outTask.Result } catch {}
try { $stderr = $errTask.Result } catch {}
$captured = $stdout
if ($stderr) { $captured += "`n[stderr]`n$stderr" }
if ($timedOut) { $captured += "`n[TIMEOUT after $TimeoutSeconds seconds]" }
Set-Content -Path $capturePath -Value $captured -Encoding UTF8

# Tail the last N lines for the agent
$tail = ""
if (Test-Path $capturePath) {
    $tail = (Get-Content $capturePath -Encoding UTF8 -Tail $TailLines) -join "`n"
}

$status = if ($timedOut) { "timeout" }
          elseif ($PassOnExitCode -contains [int]$exitCode) { "pass" }
          else { "fail" }

# --- Loop detection: hash-based failure signature ---
function Get-FailureSignature([string]$tail) {
    if (-not $tail) { return "" }
    $sig = $tail.ToLower()
    # Normalize variability that hides real loops: line numbers, paths, hex hashes,
    # timestamps, durations. Keeping the structural shape of the failure stable.
    $sig = $sig -replace '\b\d+\b', 'N'
    $sig = $sig -replace '[a-f0-9]{8,}', 'HEX'
    $sig = $sig -replace '\d{4}-\d{2}-\d{2}', 'DATE'
    $sig = $sig -replace '[a-z]:[\\\/][^\s"'']+', 'PATH'
    $sig = $sig -replace '/[^\s"'']+', 'PATH'
    if ($sig.Length -gt 2000) { $sig = $sig.Substring(0, 2000) }
    $bytes = [System.Text.Encoding]::UTF8.GetBytes($sig)
    $hash  = [System.Security.Cryptography.SHA256]::Create().ComputeHash($bytes)
    return ([System.BitConverter]::ToString($hash) -replace '-', '').Substring(0, 16)
}

$failureSig = ""
$escalation = $null
if ($status -eq "fail" -or $status -eq "timeout") {
    $failureSig = Get-FailureSignature $tail
    # Read previous runs from the log; check the last (StuckThreshold-1) for matching sig.
    if ((Test-Path $runsLog) -and $StuckThreshold -gt 1) {
        $needed = $StuckThreshold - 1
        $prev = @(Get-Content $runsLog -Encoding UTF8 -Tail $needed -ErrorAction SilentlyContinue)
        $matchCount = 0
        foreach ($line in $prev) {
            try {
                $r = $line | ConvertFrom-Json
                if ($r.failure_sig -eq $failureSig -and ($r.status -eq "fail" -or $r.status -eq "timeout")) {
                    $matchCount++
                }
            } catch {}
        }
        if ($matchCount -ge $needed) {
            $status = "stuck"
            $escalation = "Same failure signature has occurred $StuckThreshold times in a row. Stop doubling down -- try a different approach: different file, different angle, or escalate to user."
        }
    }
}

$record = [ordered]@{
    iteration    = $iteration
    command      = $Command
    exit_code    = [int]$exitCode
    duration_ms  = $durationMs
    status       = $status
    tail         = $tail
    capture_path = $capturePath
    failure_sig  = $failureSig
    escalation   = $escalation
    ran_at       = (Get-Date -Format "o")
}

# Append to runs log (compact one line per record)
$compactJson = ($record | ConvertTo-Json -Compress -Depth 4)
Add-Content -Path $runsLog -Value $compactJson -Encoding UTF8

# On pass: mark the verification_evidence gate, record in workflow-evidence
if ($status -eq "pass" -and -not $NoGateMark) {
    & $script:AgentsShell -NoProfile -File (Join-Path $PSScriptRoot "state-gate.ps1") `
        -SessionId $SessionId -Mark "verification_evidence" 2>&1 | Out-Null
    & $script:AgentsShell -NoProfile -File (Join-Path $PSScriptRoot "workflow-evidence.ps1") `
        -SessionId $SessionId -AddVerification $Command 2>&1 | Out-Null
}

# Output the record (always pretty-printed for the agent to read)
Write-Output ($record | ConvertTo-Json -Depth 4)

# Exit code conveys outcome to callers
switch ($status) {
    "pass"    { exit 0 }
    "stuck"   { exit 3 }
    default   { exit 1 }
}
