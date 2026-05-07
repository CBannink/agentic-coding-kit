#!/usr/bin/env pwsh

param(
    [Parameter(Mandatory = $true)]
    [string]$SessionId,
    [string]$Mode = "",
    [string]$Tier = "",
    [string]$TierReason = "",
    [string]$Scope = "",
    [string]$ScopeReason = "",
    [string]$BuildBrief = "",
    [string]$AddRepoContext = "",
    [string]$AddAgent = "",
    [string]$AddSkippedAgent = "",
    [string]$AddModeDecision = "",
    [string]$AddReviewCheck = "",
    [string]$AddVerification = "",
    # Structured verification proof. When -AddVerification is used with these
    # set, the recording also lands in the verification_proofs array as a
    # tuple { command, exit_code, output_hash, captured_at }. -WithExitCode
    # is REQUIRED for the structured record; if non-zero, the call is
    # rejected (the verification did NOT pass, so it is not evidence). Free-
    # form -AddVerification without these stays back-compat: no enforcement,
    # just recorded in verification_commands.
    [Nullable[int]]$WithExitCode = $null,
    [string]$WithCommand = "",
    [string]$WithOutputHash = "",
    [Alias("WriteMemoryDecision", "Memory")]
    [string]$MemoryDecision = "",
    [Alias("WriteHistoryDecision", "History")]
    [string]$HistoryDecision = "",
    [Alias("WriteWikiDecision", "Wiki")]
    [string]$WikiDecision = "",
    [string]$AddNote = ""
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

. (Join-Path $PSScriptRoot "_paths.ps1")

$sessionDir = Get-SessionDir $SessionId
$path = Join-Path $sessionDir "workflow-evidence.json"
$metaPath = Join-Path $sessionDir "session-meta.json"
New-Item -ItemType Directory -Path $sessionDir -Force | Out-Null

if (Test-Path $path) {
    $doc = Get-Content $path -Raw | ConvertFrom-Json
} else {
    $doc = [pscustomobject]@{
        session_id            = $SessionId
        updated_at            = ""
        mode_sequence         = @()
        tier                  = ""
        tier_reason           = ""
        scope                 = ""
        scope_reason          = ""
        build_brief_used      = ""
        repo_context_used     = @()
        agents_spawned        = @()
        agents_skipped        = @()
        mode_decisions        = @()
        review_checks         = @()
        verification_commands = @()
        verification_proofs   = @()
        write_decisions       = [pscustomobject]@{
            memory = ""
            history = ""
            wiki = ""
        }
        notes = @()
    }
}

$modeSequence = [System.Collections.ArrayList]::new()
$repoContext = [System.Collections.ArrayList]::new()
$agentsSpawned = [System.Collections.ArrayList]::new()
$agentsSkipped = [System.Collections.ArrayList]::new()
$modeDecisions = [System.Collections.ArrayList]::new()
$reviewChecks = [System.Collections.ArrayList]::new()
$verification = [System.Collections.ArrayList]::new()
$notes = [System.Collections.ArrayList]::new()

foreach ($value in @($doc.mode_sequence)) { Add-UniqueValue -List $modeSequence -Value $value }
foreach ($value in @($doc.repo_context_used)) { Add-UniqueValue -List $repoContext -Value $value }
foreach ($value in @($doc.agents_spawned)) { Add-UniqueValue -List $agentsSpawned -Value $value }
foreach ($value in @($doc.agents_skipped)) { Add-UniqueValue -List $agentsSkipped -Value $value }
foreach ($value in @($doc.mode_decisions)) { Add-UniqueValue -List $modeDecisions -Value $value }
foreach ($value in @($doc.review_checks)) { Add-UniqueValue -List $reviewChecks -Value $value }
foreach ($value in @($doc.verification_commands)) { Add-UniqueValue -List $verification -Value $value }
foreach ($value in @($doc.notes)) { Add-UniqueValue -List $notes -Value $value }

Add-UniqueValue -List $modeSequence -Value $Mode
Add-UniqueValue -List $repoContext -Value $AddRepoContext
Add-UniqueValue -List $agentsSpawned -Value $AddAgent
Add-UniqueValue -List $agentsSkipped -Value $AddSkippedAgent
Add-UniqueValue -List $modeDecisions -Value $AddModeDecision
Add-UniqueValue -List $reviewChecks -Value $AddReviewCheck
Add-UniqueValue -List $verification -Value $AddVerification

# Structured verification proof: only accept if exit_code == 0. A non-zero
# exit means verification did NOT pass, so it cannot be recorded as evidence.
if ($AddVerification -and $null -ne $WithExitCode) {
    if ($WithExitCode -ne 0) {
        Write-Error "REJECTED: verification record requires WithExitCode=0 but got $WithExitCode. The command did not pass; it is not evidence. Re-run, fix, or pass a free-form -AddVerification without -WithExitCode if you genuinely want to log a non-passing run."
        exit 1
    }
    $proof = [pscustomobject]@{
        command     = if ($WithCommand) { $WithCommand } else { $AddVerification }
        exit_code   = [int]$WithExitCode
        output_hash = $WithOutputHash
        captured_at = (Get-Date -Format 'o')
    }
    $existingProofs = @()
    if ($doc.PSObject.Properties['verification_proofs']) {
        $existingProofs = @($doc.verification_proofs)
    }
    $doc | Add-Member -NotePropertyName verification_proofs -NotePropertyValue (@($existingProofs) + @($proof)) -Force
}

Add-UniqueValue -List $notes -Value $AddNote

if ($Tier) { $doc.tier = $Tier }
if ($TierReason) { $doc.tier_reason = $TierReason }
if ($Scope) { $doc.scope = $Scope }
if ($ScopeReason) { $doc.scope_reason = $ScopeReason }
if ($BuildBrief) { $doc.build_brief_used = $BuildBrief }
if ($MemoryDecision) { $doc.write_decisions.memory = $MemoryDecision }
if ($HistoryDecision) { $doc.write_decisions.history = $HistoryDecision }
if ($WikiDecision) { $doc.write_decisions.wiki = $WikiDecision }

$doc.mode_sequence = @($modeSequence)
$doc.repo_context_used = @($repoContext)
$doc.agents_spawned = @($agentsSpawned)
$doc.agents_skipped = @($agentsSkipped)
$doc.mode_decisions = @($modeDecisions)
$doc.review_checks = @($reviewChecks)
$doc.verification_commands = @($verification)
$doc.notes = @($notes)
$doc.updated_at = Get-Date -Format "o"

$doc | ConvertTo-Json -Depth 6 | Set-Content -Path $path -Encoding utf8
Sync-EvalArtifactMirror -SessionId $SessionId -SourcePath $path -TargetName "workflow-evidence.json"

if ($Tier -and (Test-Path $metaPath)) {
    try {
        $meta = Get-Content $metaPath -Raw | ConvertFrom-Json
        $meta | Add-Member -NotePropertyName tier_rec -NotePropertyValue $Tier -Force
        $meta | ConvertTo-Json -Depth 6 | Set-Content -Path $metaPath -Encoding utf8
        Sync-EvalArtifactMirror -SessionId $SessionId -SourcePath $metaPath -TargetName "session-meta.json"
    } catch {}
}

Write-Output ($doc | ConvertTo-Json -Compress -Depth 6)
