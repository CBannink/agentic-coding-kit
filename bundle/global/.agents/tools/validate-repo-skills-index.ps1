#!/usr/bin/env pwsh

[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)]
    [string]$RepoRoot,
    [string]$IndexPath = "",
    [string]$ProfilePath = "",
    [switch]$RequireCurrentContract
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

function New-ValidationResult {
    param(
        [string]$RepoRoot,
        [string]$IndexPath,
        [string]$ProfilePath
    )

    return @{
        validator_version   = 1
        repo_root           = $RepoRoot
        index_path          = $IndexPath
        profile_path        = $ProfilePath
        checked_at          = (Get-Date -Format "o")
        status              = "valid"
        trust_level         = "normal"
        recommended_action  = "load_index_routing"
        strict_failure      = $false
        reasons             = @()
        warnings            = @()
        loadable_skill_paths = @()
        loadable_skills     = @()
        metadata            = @{
            schema_version                  = $null
            assurance                       = ""
            derive_mode                     = ""
            freshness_status                = ""
            freshness_scope                 = ""
            target_surfaces                 = @()
            current_contract                = $false
            current_contract_fields_missing = @()
            coverage_overall                = ""
            coverage_sampling_mode          = ""
            repo_local_skills_count         = 0
        }
    }
}

function Add-UniqueItem {
    param(
        [hashtable]$Result,
        [string]$Property,
        [string]$Value
    )

    if (-not $Value) { return }
    $items = [System.Collections.ArrayList]@($Result[$Property])
    if (-not $items.Contains($Value)) {
        [void]$items.Add($Value)
    }
    $Result[$Property] = @($items)
}

function Set-ValidationVerdict {
    param(
        [hashtable]$Result,
        [string]$Status,
        [string]$TrustLevel,
        [string]$RecommendedAction,
        [bool]$StrictFailure
    )

    $Result.status = $Status
    $Result.trust_level = $TrustLevel
    $Result.recommended_action = $RecommendedAction
    $Result.strict_failure = $StrictFailure
}

function Resolve-RepoRelativePath {
    param(
        [string]$RepoRoot,
        [string]$RelativePath
    )

    if (-not $RelativePath) { return $null }
    return [System.IO.Path]::GetFullPath((Join-Path $RepoRoot $RelativePath))
}

function Test-PathUnderCodexSkills {
    param(
        [string]$RepoRoot,
        [string]$TargetPath
    )

    $skillsRoot = [System.IO.Path]::GetFullPath((Join-Path $RepoRoot ".kit\skills"))
    return $TargetPath.StartsWith($skillsRoot, [System.StringComparison]::OrdinalIgnoreCase)
}

$RepoRoot = [System.IO.Path]::GetFullPath($RepoRoot)
if (-not $IndexPath) {
    $IndexPath = Join-Path $RepoRoot ".kit\skills\index.json"
}
if (-not $ProfilePath) {
    $ProfilePath = Join-Path $RepoRoot ".kit\skills\profile.md"
}

$result = New-ValidationResult -RepoRoot $RepoRoot -IndexPath $IndexPath -ProfilePath $ProfilePath

if (-not (Test-Path $IndexPath)) {
    Set-ValidationVerdict -Result $result -Status "missing" -TrustLevel "blocked" -RecommendedAction "run_derive_repo_skills" -StrictFailure $RequireCurrentContract.IsPresent
    Add-UniqueItem -Result $result -Property "reasons" -Value "index_not_found"
    $result | ConvertTo-Json -Depth 8
    exit ($(if ($RequireCurrentContract) { 40 } else { 20 }))
}

try {
    $index = Get-Content $IndexPath -Raw | ConvertFrom-Json -AsHashtable
} catch {
    Set-ValidationVerdict -Result $result -Status "invalid" -TrustLevel "blocked" -RecommendedAction "run_derive_repo_skills" -StrictFailure $true
    Add-UniqueItem -Result $result -Property "reasons" -Value "index_not_valid_json"
    Add-UniqueItem -Result $result -Property "warnings" -Value $_.Exception.Message
    $result | ConvertTo-Json -Depth 8
    exit 30
}

$requiredBaseFields = @("generated_at", "generator", "freshness", "repo_local_skills")
foreach ($field in $requiredBaseFields) {
    if (-not $index.ContainsKey($field)) {
        Set-ValidationVerdict -Result $result -Status "invalid" -TrustLevel "blocked" -RecommendedAction "run_derive_repo_skills" -StrictFailure $true
        Add-UniqueItem -Result $result -Property "reasons" -Value "missing_base_field:$field"
    }
}

if ($result.status -eq "invalid") {
    $result | ConvertTo-Json -Depth 8
    exit 30
}

try {
    [void][datetimeoffset]::Parse([string]$index.generated_at)
} catch {
    Set-ValidationVerdict -Result $result -Status "invalid" -TrustLevel "blocked" -RecommendedAction "run_derive_repo_skills" -StrictFailure $true
    Add-UniqueItem -Result $result -Property "reasons" -Value "generated_at_not_parseable"
}

if (-not ($index.freshness -is [System.Collections.IDictionary])) {
    Set-ValidationVerdict -Result $result -Status "invalid" -TrustLevel "blocked" -RecommendedAction "run_derive_repo_skills" -StrictFailure $true
    Add-UniqueItem -Result $result -Property "reasons" -Value "freshness_not_object"
} else {
    if (-not $index.freshness.ContainsKey("basis")) {
        Set-ValidationVerdict -Result $result -Status "invalid" -TrustLevel "blocked" -RecommendedAction "run_derive_repo_skills" -StrictFailure $true
        Add-UniqueItem -Result $result -Property "reasons" -Value "freshness_basis_missing"
    }
    $freshnessStatus = if ($index.freshness.ContainsKey("status")) { [string]$index.freshness.status } else { "" }
    $freshnessScope = if ($index.freshness.ContainsKey("scope")) { [string]$index.freshness.scope } else { "" }
    $targetSurfaces = if ($index.freshness.ContainsKey("target_surfaces")) { @($index.freshness.target_surfaces) } else { @() }
    $result.metadata.freshness_status = $freshnessStatus
    $result.metadata.freshness_scope = $freshnessScope
    $result.metadata.target_surfaces = @($targetSurfaces)
    if ($freshnessStatus -notin @("fresh", "stale")) {
        Set-ValidationVerdict -Result $result -Status "invalid" -TrustLevel "blocked" -RecommendedAction "run_derive_repo_skills" -StrictFailure $true
        Add-UniqueItem -Result $result -Property "reasons" -Value "freshness_status_invalid"
    }
    if ($freshnessScope -and $freshnessScope -notin @("repo", "surface")) {
        Set-ValidationVerdict -Result $result -Status "invalid" -TrustLevel "blocked" -RecommendedAction "run_derive_repo_skills" -StrictFailure $true
        Add-UniqueItem -Result $result -Property "reasons" -Value "freshness_scope_invalid"
    }
}

if ($result.status -eq "invalid") {
    $result | ConvertTo-Json -Depth 8
    exit 30
}

$repoLocalSkills = @($index.repo_local_skills)
$result.metadata.repo_local_skills_count = $repoLocalSkills.Count

$currentContractFields = @("schema_version", "assurance", "derive_mode", "stack", "repo_shape", "coverage_summary", "surfaces", "execution_affordances", "recommended_global_skills", "profile_path")
$missingCurrentFields = [System.Collections.ArrayList]::new()
foreach ($field in $currentContractFields) {
    if (-not $index.ContainsKey($field)) {
        [void]$missingCurrentFields.Add($field)
    }
}
$result.metadata.current_contract_fields_missing = @($missingCurrentFields)

$schemaVersion = $null
if ($index.ContainsKey("schema_version")) {
    try { $schemaVersion = [int]$index.schema_version } catch { $schemaVersion = $null }
}
$result.metadata.schema_version = $schemaVersion
$result.metadata.assurance = if ($index.ContainsKey("assurance")) { [string]$index.assurance } else { "" }
$deriveMode = if ($index.ContainsKey("derive_mode")) { [string]$index.derive_mode } else { "" }
$result.metadata.derive_mode = $deriveMode
$coverageSummary = if ($index.ContainsKey("coverage_summary") -and ($index.coverage_summary -is [System.Collections.IDictionary])) { $index.coverage_summary } else { $null }
$result.metadata.coverage_overall = if ($coverageSummary -and $coverageSummary.ContainsKey("overall")) { [string]$coverageSummary.overall } else { "" }
$result.metadata.coverage_sampling_mode = if ($coverageSummary -and $coverageSummary.ContainsKey("sampling_mode")) { [string]$coverageSummary.sampling_mode } else { "" }

$isCurrentContract = ($missingCurrentFields.Count -eq 0) -and ($schemaVersion -eq 3) -and ($result.metadata.assurance -eq "evidence-backed")
$result.metadata.current_contract = $isCurrentContract

if (-not $isCurrentContract -and $result.status -eq "valid") {
    Set-ValidationVerdict -Result $result -Status "legacy" -TrustLevel "lowered" -RecommendedAction "prefer_profile_and_global_skills" -StrictFailure $false
    foreach ($field in $missingCurrentFields) {
        Add-UniqueItem -Result $result -Property "warnings" -Value "missing_current_contract_field:$field"
    }
    if ($schemaVersion -ne $null -and $schemaVersion -ne 3) {
        Add-UniqueItem -Result $result -Property "warnings" -Value "unexpected_schema_version:$schemaVersion"
    }
    if ($index.ContainsKey("assurance") -and $result.metadata.assurance -ne "evidence-backed") {
        Add-UniqueItem -Result $result -Property "warnings" -Value "unexpected_assurance:$($result.metadata.assurance)"
    }
}

if ($schemaVersion -eq 3 -and -not $result.metadata.freshness_scope) {
    Set-ValidationVerdict -Result $result -Status "invalid" -TrustLevel "blocked" -RecommendedAction "run_derive_repo_skills" -StrictFailure $true
    Add-UniqueItem -Result $result -Property "reasons" -Value "freshness_scope_missing_current_contract"
}

if ($deriveMode -and $deriveMode -notin @("full", "scoped")) {
    Set-ValidationVerdict -Result $result -Status "invalid" -TrustLevel "blocked" -RecommendedAction "run_derive_repo_skills" -StrictFailure $true
    Add-UniqueItem -Result $result -Property "reasons" -Value "derive_mode_invalid"
}

if ($coverageSummary -eq $null) {
    if ($index.ContainsKey("coverage_summary")) {
        Set-ValidationVerdict -Result $result -Status "invalid" -TrustLevel "blocked" -RecommendedAction "run_derive_repo_skills" -StrictFailure $true
        Add-UniqueItem -Result $result -Property "reasons" -Value "coverage_summary_not_object"
    }
} elseif ($isCurrentContract) {
    $coverageOverall = $result.metadata.coverage_overall
    $coverageSamplingMode = $result.metadata.coverage_sampling_mode
    if ($coverageOverall -notin @("broad", "adequate", "partial")) {
        Set-ValidationVerdict -Result $result -Status "invalid" -TrustLevel "blocked" -RecommendedAction "run_derive_repo_skills" -StrictFailure $true
        Add-UniqueItem -Result $result -Property "reasons" -Value "coverage_summary_overall_invalid"
    }
    if ($coverageSamplingMode -notin @("minimal", "standard", "expanded")) {
        Set-ValidationVerdict -Result $result -Status "invalid" -TrustLevel "blocked" -RecommendedAction "run_derive_repo_skills" -StrictFailure $true
        Add-UniqueItem -Result $result -Property "reasons" -Value "coverage_summary_sampling_mode_invalid"
    }
}

if ($deriveMode -eq "full" -and $result.metadata.freshness_scope -and $result.metadata.freshness_scope -ne "repo") {
    Set-ValidationVerdict -Result $result -Status "invalid" -TrustLevel "blocked" -RecommendedAction "run_derive_repo_skills" -StrictFailure $true
    Add-UniqueItem -Result $result -Property "reasons" -Value "full_derive_requires_repo_freshness_scope"
}
if ($deriveMode -eq "scoped") {
    if ($result.metadata.freshness_scope -ne "surface") {
        Set-ValidationVerdict -Result $result -Status "invalid" -TrustLevel "blocked" -RecommendedAction "run_derive_repo_skills" -StrictFailure $true
        Add-UniqueItem -Result $result -Property "reasons" -Value "scoped_derive_requires_surface_freshness_scope"
    }
    if (@($result.metadata.target_surfaces).Count -eq 0) {
        Set-ValidationVerdict -Result $result -Status "invalid" -TrustLevel "blocked" -RecommendedAction "run_derive_repo_skills" -StrictFailure $true
        Add-UniqueItem -Result $result -Property "reasons" -Value "scoped_derive_requires_target_surfaces"
    }
}

$resolvedProfilePath = if ($index.ContainsKey("profile_path")) {
    Resolve-RepoRelativePath -RepoRoot $RepoRoot -RelativePath ([string]$index.profile_path)
} else {
    [System.IO.Path]::GetFullPath($ProfilePath)
}
$result.profile_path = $resolvedProfilePath

if (-not (Test-Path $resolvedProfilePath)) {
    if ($index.ContainsKey("profile_path")) {
        Set-ValidationVerdict -Result $result -Status "invalid" -TrustLevel "blocked" -RecommendedAction "run_derive_repo_skills" -StrictFailure $true
        Add-UniqueItem -Result $result -Property "reasons" -Value "profile_path_missing"
    } else {
        if ($result.status -eq "valid") {
            Set-ValidationVerdict -Result $result -Status "legacy" -TrustLevel "lowered" -RecommendedAction "prefer_profile_and_global_skills" -StrictFailure $false
        }
        Add-UniqueItem -Result $result -Property "warnings" -Value "default_profile_path_missing"
    }
}
if ($index.ContainsKey("profile_path") -and -not (Test-PathUnderCodexSkills -RepoRoot $RepoRoot -TargetPath $resolvedProfilePath)) {
    Set-ValidationVerdict -Result $result -Status "invalid" -TrustLevel "blocked" -RecommendedAction "run_derive_repo_skills" -StrictFailure $true
    Add-UniqueItem -Result $result -Property "reasons" -Value "profile_path_outside_codex_skills"
}

$loadableSkillPaths = [System.Collections.ArrayList]::new()
$loadableSkills = [System.Collections.ArrayList]::new()
foreach ($skill in $repoLocalSkills) {
    if (-not ($skill -is [System.Collections.IDictionary])) {
        Set-ValidationVerdict -Result $result -Status "invalid" -TrustLevel "blocked" -RecommendedAction "run_derive_repo_skills" -StrictFailure $true
        Add-UniqueItem -Result $result -Property "reasons" -Value "repo_local_skill_not_object"
        continue
    }

    $name = if ($skill.ContainsKey("name")) { [string]$skill.name } else { "" }
    $relativePath = if ($skill.ContainsKey("path")) { [string]$skill.path } else { "" }
    $confidence = if ($skill.ContainsKey("confidence")) { [string]$skill.confidence } else { "" }

    if (-not $name -or -not $relativePath) {
        Set-ValidationVerdict -Result $result -Status "invalid" -TrustLevel "blocked" -RecommendedAction "run_derive_repo_skills" -StrictFailure $true
        Add-UniqueItem -Result $result -Property "reasons" -Value "repo_local_skill_missing_name_or_path"
        continue
    }

    $resolvedSkillPath = Resolve-RepoRelativePath -RepoRoot $RepoRoot -RelativePath $relativePath
    if (-not (Test-PathUnderCodexSkills -RepoRoot $RepoRoot -TargetPath $resolvedSkillPath)) {
        Set-ValidationVerdict -Result $result -Status "invalid" -TrustLevel "blocked" -RecommendedAction "run_derive_repo_skills" -StrictFailure $true
        Add-UniqueItem -Result $result -Property "reasons" -Value "skill_path_outside_codex_skills:$name"
        continue
    }
    if (-not (Test-Path $resolvedSkillPath)) {
        Set-ValidationVerdict -Result $result -Status "invalid" -TrustLevel "blocked" -RecommendedAction "run_derive_repo_skills" -StrictFailure $true
        Add-UniqueItem -Result $result -Property "reasons" -Value "skill_path_missing:$name"
        continue
    }

    if ($confidence -eq "high") {
        if (-not $loadableSkillPaths.Contains($resolvedSkillPath)) {
            [void]$loadableSkillPaths.Add($resolvedSkillPath)
            [void]$loadableSkills.Add(@{
                name = $name
                path = $resolvedSkillPath
            })
        }
    } else {
        Add-UniqueItem -Result $result -Property "warnings" -Value "non_high_confidence_skill_excluded:${name}:${confidence}"
        if ($isCurrentContract) {
            Set-ValidationVerdict -Result $result -Status "invalid" -TrustLevel "blocked" -RecommendedAction "run_derive_repo_skills" -StrictFailure $true
            Add-UniqueItem -Result $result -Property "reasons" -Value "current_contract_non_high_confidence_skill:$name"
        }
    }
}

$result.loadable_skill_paths = @($loadableSkillPaths)
$result.loadable_skills = @($loadableSkills)

if ($result.status -eq "valid" -and $deriveMode -eq "scoped") {
    Set-ValidationVerdict -Result $result -Status "valid" -TrustLevel "lowered" -RecommendedAction "prefer_profile_and_global_skills" -StrictFailure $false
    Add-UniqueItem -Result $result -Property "warnings" -Value "scoped_derive_mode_present"
}

if ($result.status -eq "valid" -and $result.metadata.coverage_overall -eq "partial") {
    Add-UniqueItem -Result $result -Property "warnings" -Value "coverage_summary_partial"
}

if ($result.status -eq "valid" -and $result.metadata.freshness_status -eq "stale") {
    $recommendedAction = if ($result.metadata.freshness_scope -eq "surface") { "run_scoped_derive_repo_skills" } else { "run_derive_repo_skills" }
    Set-ValidationVerdict -Result $result -Status "valid" -TrustLevel "lowered" -RecommendedAction $recommendedAction -StrictFailure $false
    Add-UniqueItem -Result $result -Property "warnings" -Value "index_marked_stale"
}

if ($RequireCurrentContract -and -not $isCurrentContract) {
    $result.strict_failure = $true
    if ($result.status -eq "legacy") {
        $result.recommended_action = "run_derive_repo_skills"
    }
}

$exitCode = switch ($result.status) {
    "valid" { 0 }
    "legacy" { 10 }
    "missing" { 20 }
    "invalid" { 30 }
    default { 30 }
}
if ($result.strict_failure) {
    $exitCode = 40
}

$result | ConvertTo-Json -Depth 8
exit $exitCode
