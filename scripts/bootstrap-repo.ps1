#!/usr/bin/env pwsh

param(
    [Parameter(Mandatory = $true)]
    [string]$TargetRepo
)

$ScriptRoot = Split-Path -Parent $MyInvocation.MyCommand.Path
$RepoRoot = Split-Path -Parent $ScriptRoot
$TemplateRoot = Join-Path $RepoRoot "bundle\repo-template"

if (-not (Test-Path $TargetRepo)) {
    throw "Target repo does not exist: $TargetRepo"
}

Copy-Item -Recurse -Force (Join-Path $TemplateRoot '*') $TargetRepo
Write-Host "Bootstrapped .codex / .wiki template into $TargetRepo"
