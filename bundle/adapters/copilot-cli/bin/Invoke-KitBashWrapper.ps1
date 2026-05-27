#!/usr/bin/env pwsh
[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)]
    [string]$ScriptBaseName,

    [Parameter(ValueFromRemainingArguments = $true)]
    [string[]]$WrapperArgs
)

$ErrorActionPreference = 'Stop'

function Get-BashExecutable {
    $fallbacks = @(
        'C:\Program Files\Git\bin\bash.exe',
        'C:\Program Files\Git\usr\bin\bash.exe',
        'C:\Program Files (x86)\Git\bin\bash.exe',
        'C:\Program Files (x86)\Git\usr\bin\bash.exe'
    )

    foreach ($path in $fallbacks) {
        if (Test-Path $path) { return $path }
    }

    $candidate = Get-Command bash -ErrorAction SilentlyContinue
    if ($candidate) { return $candidate.Source }

    throw "Git Bash not found. Install Git for Windows or add bash.exe to PATH."
}

$scriptPath = Join-Path $PSScriptRoot "$ScriptBaseName.sh"
if (-not (Test-Path $scriptPath)) {
    throw "Wrapper target not found: $scriptPath"
}

$bashExe = Get-BashExecutable
$bashScriptPath = $scriptPath -replace '\\', '/'

& $bashExe --noprofile --norc $bashScriptPath @WrapperArgs
exit $LASTEXITCODE
