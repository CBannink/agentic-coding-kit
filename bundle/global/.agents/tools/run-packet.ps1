#!/usr/bin/env pwsh

param(
    [Parameter(Mandatory = $true)]
    [string]$SessionId,
    [string]$Mode = "",
    [string]$Task = "",
    [string]$ApprovalStatus = "",
    [string]$PlanSummary = "",
    [string[]]$AddLikelyFile = @(),
    [string[]]$AddIntegrationPoint = @(),
    [string[]]$AddVerificationItem = @(),
    [string[]]$AddMemoryPath = @(),
    [string[]]$AddNote = @()
)

function Add-UniqueValue {
    param(
        [System.Collections.ArrayList]$List,
        [string]$Value
    )
    if ($Value -and -not $List.Contains($Value)) {
        [void]$List.Add($Value)
    }
}

function Add-UniqueValues {
    param(
        [System.Collections.ArrayList]$List,
        [object[]]$Values
    )
    foreach ($value in @($Values)) {
        if ($null -eq $value) { continue }
        foreach ($part in @("$value" -split '\s*,\s*')) {
            Add-UniqueValue -List $List -Value $part
        }
    }
}

. (Join-Path $PSScriptRoot "_paths.ps1")

$sessionDir = Get-SessionDir $SessionId
$path = Join-Path $sessionDir "run-packet.json"
New-Item -ItemType Directory -Path $sessionDir -Force | Out-Null

if (Test-Path $path) {
    $doc = Get-Content $path -Raw | ConvertFrom-Json
} else {
    $doc = [pscustomobject]@{
        session_id                    = $SessionId
        updated_at                    = ""
        mode_sequence                 = @()
        task                          = ""
        approval_status               = ""
        plan_summary                  = ""
        likely_files                  = @()
        integration_points            = @()
        verification_items            = @()
        repo_specialist_memory_used   = @()
        notes                         = @()
    }
}

$modeSequence = [System.Collections.ArrayList]::new()
$likelyFiles = [System.Collections.ArrayList]::new()
$integrationPoints = [System.Collections.ArrayList]::new()
$verificationItems = [System.Collections.ArrayList]::new()
$memoryPaths = [System.Collections.ArrayList]::new()
$notes = [System.Collections.ArrayList]::new()

foreach ($value in @($doc.mode_sequence)) { Add-UniqueValue -List $modeSequence -Value $value }
foreach ($value in @($doc.likely_files)) { Add-UniqueValue -List $likelyFiles -Value $value }
foreach ($value in @($doc.integration_points)) { Add-UniqueValue -List $integrationPoints -Value $value }
foreach ($value in @($doc.verification_items)) { Add-UniqueValue -List $verificationItems -Value $value }
foreach ($value in @($doc.repo_specialist_memory_used)) { Add-UniqueValue -List $memoryPaths -Value $value }
foreach ($value in @($doc.notes)) { Add-UniqueValue -List $notes -Value $value }

Add-UniqueValue -List $modeSequence -Value $Mode
Add-UniqueValues -List $likelyFiles -Values $AddLikelyFile
Add-UniqueValues -List $integrationPoints -Values $AddIntegrationPoint
Add-UniqueValues -List $verificationItems -Values $AddVerificationItem
Add-UniqueValues -List $memoryPaths -Values $AddMemoryPath
Add-UniqueValues -List $notes -Values $AddNote

if ($Task) { $doc.task = $Task }
if ($ApprovalStatus) { $doc.approval_status = $ApprovalStatus }
if ($PlanSummary) { $doc.plan_summary = $PlanSummary }

$doc.mode_sequence = @($modeSequence)
$doc.likely_files = @($likelyFiles)
$doc.integration_points = @($integrationPoints)
$doc.verification_items = @($verificationItems)
$doc.repo_specialist_memory_used = @($memoryPaths)
$doc.notes = @($notes)
$doc.updated_at = Get-Date -Format "o"

$doc | ConvertTo-Json -Depth 6 | Set-Content -Path $path -Encoding utf8
Sync-EvalArtifactMirror -SessionId $SessionId -SourcePath $path -TargetName "run-packet.json"
Write-Output ($doc | ConvertTo-Json -Compress -Depth 6)
