# quick-harness-check.ps1 -- "did the kit's harness actually fire" smoke test.
#
# Runs 3 tiny coding tasks through opencode + your existing Copilot/Kimi/whatever
# auth, then inspects what got written to ~/.agents/session-state/ to confirm
# the lifecycle hooks (pre-session, post-session, plugin events) fired.
#
# Run from a real terminal window (cmd, Windows Terminal, PowerShell host).
# The earlier hang was a non-TTY issue inside the Claude Code tool environment;
# from a real terminal opencode runs cleanly.
#
# Usage:
#   .\benchmarks\quick-harness-check.ps1
#   .\benchmarks\quick-harness-check.ps1 -Model github-copilot/claude-haiku-4.5
#   .\benchmarks\quick-harness-check.ps1 -Model openrouter/moonshotai/kimi-k2.6
#
# This is NOT a benchmark. It just answers "is the kit firing correctly under
# opencode runtime." For the actual benchmark see benchmarks/mini-coding-eval.py.

param(
    [string]$Model = "github-copilot/claude-haiku-4.5",
    [int]$TimeoutSec = 180
)

# Don't use ErrorActionPreference=Stop -- native git commands emit stderr
# warnings (e.g. CRLF) that aren't real errors and would halt the script.
$ErrorActionPreference = "Continue"

# Sandbox setup
$sandbox = Join-Path $env:TEMP "kit-quickcheck-$(Get-Random)"
New-Item -ItemType Directory -Path $sandbox -Force | Out-Null
Set-Location $sandbox
& git init -q 2>&1 | Out-Null
"# quick check sandbox" | Set-Content README.md
"def add(a, b):`n    return a + b" | Set-Content sample.py
& git add . 2>&1 | Out-Null
& git -c user.email=t@t -c user.name=t commit -q -m "init" 2>&1 | Out-Null

# Bootstrap kit into the sandbox + opencode adapter
$installScript = Join-Path $PSScriptRoot "..\scripts\install.ps1"
if (-not (Test-Path $installScript)) {
    Write-Error "Could not find install.ps1 at $installScript -- run from the repo root or correct the path."
    exit 1
}
& $installScript -TargetRepo $sandbox -InstallRepoTemplate -InstallAdapter opencode -Force *>&1 | Out-String -Stream | Where-Object { $_ -match "Installed|Wiring" } | ForEach-Object { "  $_" }
""

# Snapshot session-state BEFORE
$sessionRoot = Join-Path $env:USERPROFILE ".agents\session-state"
$beforeDirs = @(Get-ChildItem $sessionRoot -Directory -ErrorAction SilentlyContinue | Where-Object { $_.Name -match "^\d{4}" })
$beforeCount = $beforeDirs.Count

# 3 tiny tasks
$tasks = @(
    "Write a one-line python expression that returns true if a number is even.",
    "What is 7 factorial? Just give the number.",
    "List the files in the current directory using the file tool."
)

$opencode = if (Get-Command opencode -ErrorAction SilentlyContinue) { "opencode" } else { Join-Path $env:APPDATA "npm\opencode.cmd" }

Write-Host "Running 3 quick tasks via opencode..."
Write-Host "  Model: $Model"
Write-Host "  Sandbox: $sandbox"
Write-Host ""

$ti = 0
foreach ($task in $tasks) {
    $ti++
    Write-Host "  [$ti/$($tasks.Count)] $task" -NoNewline
    $start = Get-Date

    $proc = Start-Process -FilePath $opencode `
        -ArgumentList "run", $task, "-m", $Model `
        -PassThru -NoNewWindow `
        -RedirectStandardOutput "$sandbox\out-$ti.log" `
        -RedirectStandardError "$sandbox\err-$ti.log"

    $finished = $proc.WaitForExit($TimeoutSec * 1000)
    if (-not $finished) {
        try { $proc.Kill() } catch {}
        Write-Host "  -> TIMEOUT" -ForegroundColor Yellow
    } else {
        $elapsed = ((Get-Date) - $start).TotalSeconds
        Write-Host "  -> $([math]::Round($elapsed, 1))s, exit=$($proc.ExitCode)" -ForegroundColor Green
    }
}

# Snapshot AFTER
Write-Host ""
$afterDirs = @(Get-ChildItem $sessionRoot -Directory -ErrorAction SilentlyContinue | Where-Object { $_.Name -match "^\d{4}" })
$newDirs = @($afterDirs | Where-Object { $beforeDirs.Name -notcontains $_.Name })

Write-Host "============ HARNESS FIRED? ============"
Write-Host "  session-state dirs before run: $beforeCount"
Write-Host "  session-state dirs after run:  $($afterDirs.Count)"
Write-Host "  NEW dirs created during test:  $($newDirs.Count)"
Write-Host ""

if ($newDirs.Count -eq 0) {
    Write-Host "  ✗ No new session-state dir created." -ForegroundColor Red
    Write-Host "    Possible causes:"
    Write-Host "      - opencode plugin (.opencode/plugins/agentic-kit.ts) didn't fire"
    Write-Host "      - opencode's plugin event names differ from what the kit expects"
    Write-Host "      - opencode failed to load plugins for this session"
    Write-Host "    Check OpenCode's logs: opencode run ... --log-level INFO"
} else {
    Write-Host "  ✓ Kit lifecycle fired." -ForegroundColor Green
    foreach ($dir in $newDirs | Sort-Object LastWriteTime -Descending | Select-Object -First 3) {
        Write-Host ""
        Write-Host "  Session: $($dir.Name)"
        $files = Get-ChildItem $dir.FullName -ErrorAction SilentlyContinue
        foreach ($f in $files) {
            Write-Host "    $($f.Name) ($($f.Length) bytes)"
        }
        $handoff = Join-Path $dir.FullName "handoffs.md"
        if (Test-Path $handoff) {
            Write-Host ""
            Write-Host "  Handoff preview:"
            Get-Content $handoff -Encoding UTF8 -TotalCount 12 | ForEach-Object { Write-Host "    | $_" }
        }
    }
}

Write-Host ""
Write-Host "Sandbox left intact at: $sandbox"
Write-Host "Output logs at:         $sandbox\out-*.log, err-*.log"
Write-Host "Session-state dirs at:  $sessionRoot"
Write-Host ""
Write-Host "If you want to clean up:"
Write-Host "  Remove-Item -Recurse -Force '$sandbox'"
foreach ($d in $newDirs) {
    Write-Host "  Remove-Item -Recurse -Force '$($d.FullName)'"
}
