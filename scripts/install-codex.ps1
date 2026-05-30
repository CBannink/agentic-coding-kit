#!/usr/bin/env pwsh
# Dedicated Codex installer. Thin wrapper over install.ps1 so this host cannot
# accidentally install or refresh another harness.

param(
    [string]$HomeRoot = $HOME,
    [string]$TargetRepo = "",
    [switch]$InstallRepoTemplate,
    [switch]$BootstrapHarness,
    [switch]$Upgrade,
    [switch]$Force,
    [switch]$RepairKitBlock,
    [switch]$PruneStaleAssets,
    [switch]$DryRunPrune,
    [switch]$CleanReinstall
)

$ScriptRoot = Split-Path -Parent $MyInvocation.MyCommand.Path
$Install = Join-Path $ScriptRoot "install.ps1"

$params = @{ HomeRoot = $HomeRoot; For = "codex" }
if ($TargetRepo) {
    $params.TargetRepo = $TargetRepo
    $params.InstallAdapter = "codex"
}
if ($InstallRepoTemplate) { $params.InstallRepoTemplate = $true }
if ($BootstrapHarness) { $params.BootstrapHarness = $true }
if ($Upgrade) { $params.Upgrade = $true }
if ($Force) { $params.Force = $true }
if ($RepairKitBlock) { $params.RepairKitBlock = $true }
if ($PruneStaleAssets) { $params.PruneStaleAssets = $true }
if ($DryRunPrune) { $params.DryRunPrune = $true }
if ($CleanReinstall) { $params.CleanReinstall = $true }

& $Install @params
exit $LASTEXITCODE
