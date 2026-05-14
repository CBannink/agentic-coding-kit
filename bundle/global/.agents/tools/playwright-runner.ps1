#!/usr/bin/env pwsh
# playwright-runner.ps1 -- wrapper around playwright-runner.py.
#
# Usage:
#   pwsh ~/.agents/tools/playwright-runner.ps1 -ConfigPath .agents/screen-flows.yaml -OutDir ./screenshots
#   pwsh ~/.agents/tools/playwright-runner.ps1 -ConfigPath .agents/screen-flows.yaml -OutDir ./screenshots -BaseUrl http://localhost:3000
#
# Ensures Python + playwright + pyyaml are available, then delegates.
# Honors $env:AGENTS_PYTHON to override the Python interpreter.

param(
    [Parameter(Mandatory)][string]$ConfigPath,
    [Parameter(Mandatory)][string]$OutDir,
    [string]$BaseUrl = "",
    [bool]$Headless = $true
)

. (Join-Path $PSScriptRoot "_paths.ps1")

$python = if ($env:AGENTS_PYTHON) { $env:AGENTS_PYTHON } else { "python" }
$runner = Join-Path $PSScriptRoot "playwright-runner.py"

if (-not (Test-Path $ConfigPath)) {
    Write-Error "Config not found: $ConfigPath"
    exit 1
}
if (-not (Test-Path $runner)) {
    Write-Error "playwright-runner.py not found at $runner"
    exit 1
}

# Quick dependency probe
$probe = & $python -c "import playwright, yaml" 2>&1
if ($LASTEXITCODE -ne 0) {
    Write-Host "Python deps missing. Install with:"
    Write-Host "  $python -m pip install playwright pyyaml"
    Write-Host "  $python -m playwright install chromium"
    exit 1
}

$pyArgs = @(
    $runner,
    "--config", $ConfigPath,
    "--out-dir", $OutDir,
    "--headless", ($Headless.ToString().ToLower())
)
if ($BaseUrl) { $pyArgs += @("--base-url", $BaseUrl) }

& $python @pyArgs
exit $LASTEXITCODE
