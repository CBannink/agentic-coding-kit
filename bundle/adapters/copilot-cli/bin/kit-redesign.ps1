#!/usr/bin/env pwsh
param([Parameter(ValueFromRemainingArguments = $true)][string[]]$WrapperArgs)
& (Join-Path $PSScriptRoot 'Invoke-KitBashWrapper.ps1') -ScriptBaseName 'kit-redesign' @WrapperArgs
exit $LASTEXITCODE
