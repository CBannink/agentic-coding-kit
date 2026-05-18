#!/usr/bin/env pwsh
# model-selector.ps1 -- dynamic model selection for agent spawning.
#
# Takes scope classification + agent role and returns the recommended model.
# Orchestrators call this before spawning subagents.
#
# Usage:
#   model-selector.ps1 -Scope ISOLATED -Role workflow-explorer
#   model-selector.ps1 -Scope CRITICAL -Role workflow-implementer
#   model-selector.ps1 -Scope SHARED -Role code-quality-reviewer -TrustData <json>
#
# Output: JSON { model, tier, reason, trust_adjustment, trust_warning }

param(
    [ValidateSet("ISOLATED","SHARED","CRITICAL")]
    [string]$Scope = "SHARED",

    [string]$Role,

    # Optional: trust data from reflection-emitter-stats.ps1
    # If an agent has high supersession rate, downgrade its model (save cost on noise)
    [string]$TrustData,

    # Override: force a specific tier regardless of classification
    [ValidateSet("fast","balanced","premium")]
    [string]$ForceTier,

    # Host context (avoid $Host -- reserved automatic variable in PowerShell)
    [ValidateSet("claude-code","opencode","copilot-cli")]
    [string]$HostContext = "claude-code",

    [switch]$Json
)

. (Join-Path $PSScriptRoot "_paths.ps1")

# --- Model name map: tier -> host -> model string ---
# Defaults per host. Override any entry via MODEL_MAP_FILE env var pointing to a
# JSON file with structure { "fast": { "copilot-cli": "gemini-2.5-pro" }, ... }
# or per-tier env vars: MODEL_FAST, MODEL_BALANCED, MODEL_PREMIUM.
$modelMap = @{
    fast = @{
        "claude-code"  = "claude-haiku-4-5"
        "opencode"     = "opencode-go/deepseek-v4-flash"
        "copilot-cli"  = "gpt-5.4-mini"
    }
    balanced = @{
        "claude-code"  = "claude-sonnet-4-6"
        "opencode"     = "opencode-go/minimax-m2.7"
        "copilot-cli"  = "claude-sonnet-4.6"
    }
    premium = @{
        "claude-code"  = "claude-opus-4-7"
        "opencode"     = "opencode-go/deepseek-v4-pro"
        "copilot-cli"  = "gpt-5.4"
    }
}

# --- Apply overrides from MODEL_MAP_FILE (JSON) ---
if ($env:MODEL_MAP_FILE -and (Test-Path $env:MODEL_MAP_FILE)) {
    try {
        $overrides = Get-Content $env:MODEL_MAP_FILE -Raw -Encoding UTF8 | ConvertFrom-Json -ErrorAction Stop
        foreach ($tier in @("fast","balanced","premium")) {
            $tierObj = $overrides.$tier
            if ($tierObj) {
                foreach ($prop in $tierObj.PSObject.Properties) {
                    $modelMap[$tier][$prop.Name] = $prop.Value
                }
            }
        }
    } catch {
        # Malformed override file -- continue with defaults
    }
}

# --- Apply per-tier env var overrides (host-specific) ---
# Env var overrides take precedence over ensemble overrides (explicit user intent wins).
$envOverrideTiers = @{}
if ($env:MODEL_FAST)     { $modelMap["fast"][$HostContext]     = $env:MODEL_FAST;     $envOverrideTiers["fast"]     = $true }
if ($env:MODEL_BALANCED) { $modelMap["balanced"][$HostContext] = $env:MODEL_BALANCED; $envOverrideTiers["balanced"] = $true }
if ($env:MODEL_PREMIUM)  { $modelMap["premium"][$HostContext]  = $env:MODEL_PREMIUM;  $envOverrideTiers["premium"]  = $true }

$tierOrder = @("fast","balanced","premium")

function Get-ModelName([string]$Tier, [string]$HostName) {
    $hostMap = $modelMap[$Tier]
    if ($hostMap -and $hostMap.ContainsKey($HostName)) {
        return $hostMap[$HostName]
    }
    return $modelMap[$Tier]["claude-code"]
}

# --- Role category classification ---
$explorerRoles      = @("workflow-explorer","explorer")
$implementerRoles   = @("workflow-implementer","implementer")
$reviewerRoles      = @("code-quality-reviewer","security-reviewer","modularity-expert",
                        "adversarial-reviewer","qa-reviewer","spec-reviewer","qa",
                        "adversarial","modularity","code-quality","security")
$skepticRoles       = @("workflow-skeptic","skeptic")
$verifierRoles      = @("final-verifier","verifier")
$uxRoles            = @("ux-driver","ui-driver","ux","ui")
$prRoles            = @("pr-reviewer","pr")
$orchestratorRoles  = @("goal-orchestrator","orchestrator")

function Get-RoleCategory([string]$RoleName) {
    $r = $RoleName.ToLower()
    foreach ($v in $explorerRoles)     { if ($r -eq $v) { return "explorer" } }
    foreach ($v in $implementerRoles)  { if ($r -eq $v) { return "implementer" } }
    foreach ($v in $reviewerRoles)     { if ($r -eq $v) { return "reviewer" } }
    foreach ($v in $skepticRoles)      { if ($r -eq $v) { return "skeptic" } }
    foreach ($v in $verifierRoles)     { if ($r -eq $v) { return "verifier" } }
    foreach ($v in $uxRoles)           { if ($r -eq $v) { return "ux" } }
    foreach ($v in $prRoles)           { if ($r -eq $v) { return "pr" } }
    foreach ($v in $orchestratorRoles) { if ($r -eq $v) { return "orchestrator" } }
    return "unknown"
}

# --- Tier matrix: [category][scope] -> tier ---
# explorer:      ISOLATED=fast,  SHARED=fast,     CRITICAL=balanced
# implementer:   ISOLATED=balanced, SHARED=balanced, CRITICAL=balanced
# reviewer:      ISOLATED=fast,  SHARED=balanced, CRITICAL=balanced
# skeptic:       all=balanced
# verifier:      ISOLATED=fast,  SHARED=balanced, CRITICAL=balanced
# ux/ui:         all=balanced
# pr:            all=balanced
# orchestrator:  ISOLATED=balanced, SHARED=balanced, CRITICAL=premium

$tierMatrix = @{
    explorer = @{
        ISOLATED = "fast"
        SHARED   = "fast"
        CRITICAL = "balanced"
    }
    implementer = @{
        ISOLATED = "balanced"
        SHARED   = "balanced"
        CRITICAL = "balanced"
    }
    reviewer = @{
        ISOLATED = "fast"
        SHARED   = "balanced"
        CRITICAL = "balanced"
    }
    skeptic = @{
        ISOLATED = "balanced"
        SHARED   = "balanced"
        CRITICAL = "balanced"
    }
    verifier = @{
        ISOLATED = "fast"
        SHARED   = "balanced"
        CRITICAL = "balanced"
    }
    ux = @{
        ISOLATED = "balanced"
        SHARED   = "balanced"
        CRITICAL = "balanced"
    }
    pr = @{
        ISOLATED = "balanced"
        SHARED   = "balanced"
        CRITICAL = "balanced"
    }
    orchestrator = @{
        ISOLATED = "balanced"
        SHARED   = "balanced"
        CRITICAL = "premium"
    }
    unknown = @{
        ISOLATED = "balanced"
        SHARED   = "balanced"
        CRITICAL = "balanced"
    }
}

# --- Copilot CLI cross-provider ensemble overrides ---
# When running on copilot-cli, certain roles benefit from cross-provider diversity.
# These override the host default for that role+tier combination.
$ensembleOverrides = @{
    "copilot-cli" = @{
        "adversarial-reviewer" = @{ balanced = "gpt-5.4"; premium = "gpt-5.4" }
        "modularity-expert"    = @{ balanced = "gpt-5.4"; premium = "gpt-5.4" }
        "orchestrator"         = @{ balanced = "gpt-5.4"; premium = "gpt-5.4" }
        "goal-orchestrator"    = @{ balanced = "gpt-5.4"; premium = "gpt-5.4" }
        "workflow-explorer"    = @{ fast = "gpt-5.4-mini"; balanced = "gpt-5.4-mini" }
        "explorer"             = @{ fast = "gpt-5.4-mini"; balanced = "gpt-5.4-mini" }
    }
}

# --- Resolve base tier ---
$roleName = if ($Role) { $Role } else { "" }
$category = Get-RoleCategory -RoleName $roleName
$baseTier = $tierMatrix[$category][$Scope]
$baseReason = "$Scope scope + $category role = $baseTier tier"

# --- ForceTier override ---
if ($ForceTier) {
    $baseTier   = $ForceTier
    $baseReason = "forced tier override: $ForceTier"
}

# --- Trust adjustment ---
$trustAdjustment = $null
$trustWarning    = $null

if ($TrustData) {
    try {
        $trust = $TrustData | ConvertFrom-Json -ErrorAction Stop
        $rate  = [double]$trust.supersession_rate

        if ($rate -gt 0.8) {
            $currentIdx = $tierOrder.IndexOf($baseTier)
            if ($currentIdx -gt 0) {
                $downgradedTier  = $tierOrder[$currentIdx - 1]
                $trustAdjustment = "downgraded from $($baseTier): supersession_rate $rate > 0.8 threshold (very high noise)"
                $trustWarning    = "Agent '$Role' has supersession_rate $rate -- consider replacing or retraining this role."
                $baseTier        = $downgradedTier
            } else {
                $trustAdjustment = "already at lowest tier; cannot downgrade further (supersession_rate $rate)"
                $trustWarning    = "Agent '$Role' has supersession_rate $rate -- consider replacing or retraining this role."
            }
        } elseif ($rate -gt 0.6) {
            $currentIdx = $tierOrder.IndexOf($baseTier)
            if ($currentIdx -gt 0) {
                $downgradedTier  = $tierOrder[$currentIdx - 1]
                $trustAdjustment = "downgraded from $($baseTier): supersession_rate $rate > 0.6 threshold (high noise rate)"
                $baseTier        = $downgradedTier
            } else {
                $trustAdjustment = "already at lowest tier; cannot downgrade further (supersession_rate $rate)"
            }
        } elseif ($rate -lt 0.2) {
            $currentIdx = $tierOrder.IndexOf($baseTier)
            if ($currentIdx -lt ($tierOrder.Count - 1)) {
                $upgradedTier    = $tierOrder[$currentIdx + 1]
                $trustAdjustment = "upgraded from $($baseTier): supersession_rate $rate < 0.2 threshold (reliable agent)"
                $baseTier        = $upgradedTier
            }
        }
    } catch {
        # Malformed TrustData -- silently ignore, proceed with base tier
    }
}

# --- Apply ensemble override if available (skipped when env var override is active for this tier) ---
$ensembleApplied = $null
if ($ensembleOverrides.ContainsKey($HostContext) -and $roleName -and -not $envOverrideTiers.ContainsKey($baseTier)) {
    $roleOverrides = $ensembleOverrides[$HostContext]
    $lookupRole = $roleName.ToLower()
    if ($roleOverrides.ContainsKey($lookupRole)) {
        $tierOverride = $roleOverrides[$lookupRole]
        if ($tierOverride.ContainsKey($baseTier)) {
            $ensembleApplied = "cross-provider ensemble: $lookupRole on $HostContext uses $($tierOverride[$baseTier]) at $baseTier tier"
        }
    }
}

$modelName = if ($ensembleApplied) {
    $ensembleOverrides[$HostContext][$roleName.ToLower()][$baseTier]
} else {
    Get-ModelName -Tier $baseTier -HostName $HostContext
}

$result = [ordered]@{
    model            = $modelName
    tier             = $baseTier
    reason           = $baseReason
    trust_adjustment = $trustAdjustment
    trust_warning    = $trustWarning
    ensemble_override = $ensembleApplied
}

Write-Output ($result | ConvertTo-Json -Compress)
