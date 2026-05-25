# install-copilot-kit.ps1
# Compatibility shim: delegate to the canonical repo installer.

[CmdletBinding()]
param(
    [switch]$DryRun,
    [switch]$Force,
    [switch]$NoBackup
)

$ErrorActionPreference = 'Stop'

$AgentsRoot = Join-Path $HOME ".agents"
$MetaPath = Join-Path $AgentsRoot "context/install-meta.json"

function Say([string]$msg, [string]$color='White') { Write-Host $msg -ForegroundColor $color }

function Resolve-GeneralInstallScript {
    if ($env:AGENTIC_KIT_REPO) {
        $candidate = Join-Path $env:AGENTIC_KIT_REPO 'scripts/install.ps1'
        if (Test-Path $candidate) { return $candidate }
    }

    if (Test-Path $MetaPath) {
        try {
            $meta = Get-Content -Raw -Encoding utf8 -LiteralPath $MetaPath | ConvertFrom-Json
            if ($meta.install_script -and (Test-Path $meta.install_script)) { return $meta.install_script }
            if ($meta.repo_root) {
                $candidate = Join-Path $meta.repo_root 'scripts/install.ps1'
                if (Test-Path $candidate) { return $candidate }
            }
        } catch {
            Say "  WARN  failed to read ${MetaPath}: $($_.Exception.Message)" 'Yellow'
        }
    }

    $repoCandidate = Join-Path $PSScriptRoot '..\..\..\..\scripts\install.ps1'
    if (Test-Path $repoCandidate) { return (Resolve-Path $repoCandidate).Path }

    throw "Could not locate scripts/install.ps1. Run the general installer from a checked-out repo first, or set AGENTIC_KIT_REPO to that repo."
}

$installScript = Resolve-GeneralInstallScript

if ($NoBackup) {
    Say "  WARN  -NoBackup is ignored by the shim; backup behavior is owned by scripts/install.ps1." 'Yellow'
}
if ($env:COPILOT_HOME) {
    Say "  WARN  COPILOT_HOME is ignored by the shim; scripts/install.ps1 installs Copilot under <HomeRoot>\\.copilot." 'Yellow'
}

if ($DryRun) {
    Say "Dry run: would run pwsh `"$installScript`" -HomeRoot `"$HOME`" -For copilot$(if ($Force) { ' -Force' } else { '' })" 'Cyan'
    exit 0
}

& $installScript -HomeRoot $HOME -For copilot -Force:$Force
