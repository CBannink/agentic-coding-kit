#!/usr/bin/env pwsh
# dev-server-runner.ps1 -- detect and start a local dev server, wait for the
# port to respond, return the pid + port. Companion -Stop mode kills it.
#
# Why: playwright-explorer needs a running app on localhost. Forcing the user
# (or agent) to start it manually breaks the screenshot loop. This tool
# auto-detects framework, picks the right command, polls the port, and exits
# only when ready -- so the agent can run capture immediately after.
#
# Usage:
#   pwsh dev-server-runner.ps1                     # auto-detect, start, return JSON
#   pwsh dev-server-runner.ps1 -RepoRoot <path>    # for a specific repo
#   pwsh dev-server-runner.ps1 -Port 3001          # override port detection
#   pwsh dev-server-runner.ps1 -Stop -Pid <pid>    # stop a previously started server
#   pwsh dev-server-runner.ps1 -Json               # machine-readable output (default)
#
# Detection order:
#   1. package.json `scripts.dev` -> npm run dev
#   2. next.config.* -> npx next dev
#   3. vite.config.* -> npx vite
#   4. nuxt.config.* -> npx nuxt dev
#   5. svelte.config.* -> npm run dev
#   6. manage.py present -> python manage.py runserver
#   7. Cargo.toml + frontend dir -> error, ambiguous (ask user)
#
# Exit codes:
#   0 = server running and responsive
#   1 = could not detect framework
#   2 = server started but did not respond within timeout
#   3 = port already in use by another process

param(
    [string]$RepoRoot = (Get-Location).Path,
    [int]$Port = 0,
    [int]$TimeoutSeconds = 60,
    [switch]$Stop,
    [int]$ProcessId = 0,
    [switch]$Json
)

function Out-Result {
    param([hashtable]$Data, [int]$ExitCode = 0)
    if ($Json -or $true) {
        $Data | ConvertTo-Json -Compress -Depth 5 | Write-Output
    }
    exit $ExitCode
}

if ($Stop) {
    if ($ProcessId -le 0) {
        Out-Result @{ ok = $false; error = "missing -ProcessId for -Stop" } 1
    }
    try {
        $proc = Get-Process -Id $ProcessId -ErrorAction Stop
        Stop-Process -Id $ProcessId -Force -ErrorAction Stop
        # Kill any child node processes the dev server spawned
        Get-CimInstance Win32_Process -Filter "ParentProcessId=$ProcessId" -ErrorAction SilentlyContinue | ForEach-Object {
            Stop-Process -Id $_.ProcessId -Force -ErrorAction SilentlyContinue
        }
        Out-Result @{ ok = $true; stopped_pid = $ProcessId } 0
    } catch {
        Out-Result @{ ok = $false; error = "process $ProcessId not found or could not be stopped: $($_.Exception.Message)" } 1
    }
}

if (-not (Test-Path $RepoRoot)) {
    Out-Result @{ ok = $false; error = "RepoRoot not found: $RepoRoot" } 1
}

# Detection
$pkgJsonPath = Join-Path $RepoRoot "package.json"
$detected = $null
$command = $null
$cwd = $RepoRoot

if (Test-Path $pkgJsonPath) {
    try {
        $pkg = Get-Content $pkgJsonPath -Raw -Encoding UTF8 | ConvertFrom-Json
        $hasNext = (Test-Path (Join-Path $RepoRoot "next.config.js")) -or (Test-Path (Join-Path $RepoRoot "next.config.mjs")) -or (Test-Path (Join-Path $RepoRoot "next.config.ts"))
        $hasVite = (Test-Path (Join-Path $RepoRoot "vite.config.js")) -or (Test-Path (Join-Path $RepoRoot "vite.config.ts"))
        $hasNuxt = Test-Path (Join-Path $RepoRoot "nuxt.config.ts")
        if ($pkg.scripts -and $pkg.scripts.dev) {
            $detected = "npm-dev"
            $command = "npm run dev"
        } elseif ($hasNext) {
            $detected = "next"
            $command = "npx next dev"
        } elseif ($hasVite) {
            $detected = "vite"
            $command = "npx vite"
        } elseif ($hasNuxt) {
            $detected = "nuxt"
            $command = "npx nuxt dev"
        }
    } catch {
        # malformed package.json -- fall through
    }
}

# Frontend monorepo: try common locations
if (-not $detected) {
    foreach ($sub in @("apps/frontend", "apps/web", "frontend", "web", "client", "packages/web")) {
        $subPath = Join-Path $RepoRoot $sub
        if (Test-Path (Join-Path $subPath "package.json")) {
            try {
                $subPkg = Get-Content (Join-Path $subPath "package.json") -Raw -Encoding UTF8 | ConvertFrom-Json
                if ($subPkg.scripts -and $subPkg.scripts.dev) {
                    $detected = "npm-dev:$sub"
                    $command = "npm run dev"
                    $cwd = $subPath
                    break
                }
            } catch {}
        }
    }
}

# Python frameworks
if (-not $detected) {
    if (Test-Path (Join-Path $RepoRoot "manage.py")) {
        $detected = "django"
        $command = "python manage.py runserver"
        if ($Port -eq 0) { $Port = 8000 }
    }
}

if (-not $detected) {
    Out-Result @{
        ok = $false
        error = "could not detect dev server framework"
        hints = @(
            "expected: package.json scripts.dev, next.config.*, vite.config.*, manage.py",
            "or pass an explicit start command via your shell and use -ProcessId / port directly"
        )
    } 1
}

# Default port by framework if not specified
if ($Port -eq 0) {
    $Port = switch -Wildcard ($detected) {
        "next"      { 3000 }
        "vite"      { 5173 }
        "nuxt"      { 3000 }
        "django"    { 8000 }
        default     { 3000 }
    }
}

# Check port is free
$portInUse = $false
try {
    $tcp = Get-NetTCPConnection -LocalPort $Port -State Listen -ErrorAction SilentlyContinue
    if ($tcp) { $portInUse = $true }
} catch {
    # Get-NetTCPConnection unavailable (older PS / Linux) -- fall back to TCP probe
    try {
        $client = New-Object System.Net.Sockets.TcpClient
        $client.Connect("127.0.0.1", $Port)
        if ($client.Connected) { $portInUse = $true }
        $client.Close()
    } catch {
        # connect failed = port free
    }
}

if ($portInUse) {
    # Could be us from a previous run; surface so the agent can decide.
    Out-Result @{
        ok = $true
        already_running = $true
        port = $Port
        url = "http://localhost:$Port"
        detected = $detected
        note = "port $Port already in use; assuming dev server is up. Verify before screenshotting."
    } 0
}

# Start the process
$startInfo = New-Object System.Diagnostics.ProcessStartInfo
if ($IsWindows -or $env:OS -match "Windows") {
    $startInfo.FileName = "cmd.exe"
    $startInfo.Arguments = "/c $command"
} else {
    $startInfo.FileName = "/bin/sh"
    $startInfo.Arguments = "-c `"$command`""
}
$startInfo.WorkingDirectory = $cwd
$startInfo.UseShellExecute = $false
$startInfo.RedirectStandardOutput = $true
$startInfo.RedirectStandardError = $true
$startInfo.CreateNoWindow = $true

try {
    $proc = [System.Diagnostics.Process]::Start($startInfo)
} catch {
    Out-Result @{ ok = $false; error = "failed to start: $($_.Exception.Message)"; command = $command } 1
}

# Poll the port
$deadline = (Get-Date).AddSeconds($TimeoutSeconds)
$ready = $false
while ((Get-Date) -lt $deadline) {
    Start-Sleep -Milliseconds 500
    try {
        $client = New-Object System.Net.Sockets.TcpClient
        $client.Connect("127.0.0.1", $Port)
        if ($client.Connected) {
            $ready = $true
            $client.Close()
            break
        }
    } catch {
        # not ready yet
    }
}

if (-not $ready) {
    # Try to clean up
    try { Stop-Process -Id $proc.Id -Force -ErrorAction SilentlyContinue } catch {}
    Out-Result @{
        ok = $false
        error = "server did not respond on port $Port within $TimeoutSeconds seconds"
        pid = $proc.Id
        command = $command
        cwd = $cwd
    } 2
}

Out-Result @{
    ok = $true
    already_running = $false
    pid = $proc.Id
    port = $Port
    url = "http://localhost:$Port"
    detected = $detected
    command = $command
    cwd = $cwd
    stop_command = "pwsh ~/.agents/tools/dev-server-runner.ps1 -Stop -ProcessId $($proc.Id)"
} 0
