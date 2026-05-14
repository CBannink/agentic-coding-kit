#!/usr/bin/env pwsh
# pretool-write-gateguard.ps1 -- PreToolUse hook for Write / Edit tools.
#
# Enforcement rules at the protocol layer:
#   1. Wiki existence: if the file being edited is source code AND
#      .wiki/index.md does NOT exist, block with /wiki-init suggestion.
#      (The wiki rule has been "mandatory" in prose since v0.3 -- empirical
#      compliance was 0%. Hook makes it real.)
#   2. Plan approval for SHARED / CRITICAL build work: source edits block until
#      the same-session plan artifact exists and run-packet.json records
#      approval_status=approved.
#   3. Multi-file implementation delegation: once a second unique source file
#      would be edited, block unless a workflow implementer has already been
#      spawned for the session.
#   4. First-edit-per-file reminder: first edit to a source file emits a
#      wiki-resolver reminder. This remains advisory.
#
# Both rules respect the repo's pipeline if it's authoritative -- the kit's
# job here is augmentation, not override. If the repo doesn't want wiki
# enforcement: KIT_DISABLED_HOOKS=wiki-existence
#
# Opt-out: KIT_DISABLED_HOOKS env var (comma-sep). To skip both rules:
#   KIT_DISABLED_HOOKS=write-gateguard
# To skip just one: KIT_DISABLED_HOOKS=wiki-existence  OR  =first-edit-gate

$ErrorActionPreference = "Continue"
. (Join-Path $PSScriptRoot "../_paths.ps1") -ErrorAction SilentlyContinue

$disabledHooks = if ($env:KIT_DISABLED_HOOKS) { @($env:KIT_DISABLED_HOOKS -split ',') } else { @() }
if ($disabledHooks -contains "write-gateguard") { exit 0 }

$rawInput = [Console]::In.ReadToEnd()
if (-not $rawInput) { exit 0 }
try {
    $payload = $rawInput | ConvertFrom-Json
} catch { exit 0 }

# Resolve the target file from the tool input. Both Write and Edit use
# different field names -- handle both.
$targetFile = $null
if ($payload.tool_input.file_path) { $targetFile = [string]$payload.tool_input.file_path }
elseif ($payload.tool_input.path) { $targetFile = [string]$payload.tool_input.path }
elseif ($payload.tool_input.filePath) { $targetFile = [string]$payload.tool_input.filePath }
if (-not $targetFile) { exit 0 }

# Skip non-source-code files: docs, configs, lockfiles, gitignored stuff.
# The wiki rule is for code that ships features. Let test/scratch/doc edits
# pass without ceremony.
$normalizedTarget = $targetFile -replace '\\', '/'
$srcPattern = '\.(ts|tsx|js|jsx|py|go|rs|java|cs|rb|php|swift|kt|scala|cpp|c|h|hpp|vue|svelte|astro)$'
$ignorePattern = '(\.test\.|\.spec\.|/tests?/|/__tests__/|/fixtures/|/dist/|/build/|/node_modules/|/\.venv/|/__pycache__/)'
if ($normalizedTarget -notmatch $srcPattern) { exit 0 }
if ($normalizedTarget -match $ignorePattern) { exit 0 }

$sessionId = $payload.session_id
$cwd = if ($payload.cwd) {
    [string]$payload.cwd
} elseif ($payload.directory) {
    [string]$payload.directory
} elseif ($env:CLAUDE_PROJECT_DIR) {
    $env:CLAUDE_PROJECT_DIR
} else {
    (Get-Location).Path
}

function Block-WithReason {
    param([string]$Reason)
    [Console]::Error.WriteLine($Reason)
    exit 2
}

function Get-WikiIndexPath {
    param([string]$RepoRoot)
    $wikiDir = Join-Path $RepoRoot ".wiki"
    if (-not (Test-Path $wikiDir -PathType Container)) { return $null }
    $entry = Get-ChildItem -LiteralPath $wikiDir -File |
        Where-Object { $_.Name -ieq "index.md" } |
        Select-Object -First 1
    if ($entry) { return $entry.FullName }
    return $null
}

function Get-JsonFile {
    param([string]$Path)
    if (-not (Test-Path $Path)) { return $null }
    try {
        return Get-Content $Path -Raw -Encoding UTF8 | ConvertFrom-Json
    } catch {
        return $null
    }
}

function Test-WorkflowImplementerRegistered {
    param($State)
    if (-not $State) { return $false }
    return @($State.agents_run) | Where-Object { $_ -match '(^|-)workflow-implementer$|(^|-)implementer$' } | Select-Object -First 1
}

# Rule 1: wiki existence
if (-not ($disabledHooks -contains "wiki-existence")) {
    $wikiIndex = Get-WikiIndexPath -RepoRoot $cwd
    if (-not $wikiIndex) {
        Block-WithReason @"
Blocked by kit hook (write-gateguard/wiki-existence):

This repo has no .wiki/index.md entry point (case-insensitive match). The
kit's always-on rules require .wiki/ to exist before non-trivial source code
edits, so future agents (and reviewers) have a documented entry point.

To resolve:
  Run /wiki-init to bootstrap .wiki/ from real code evidence.

To bypass entirely:
  Set KIT_DISABLED_HOOKS=wiki-existence and retry the edit.

If this repo deliberately has its own pipeline (and you want the kit to
defer), add <!-- agentic-kit:disable-lifecycle --> to its CLAUDE.md.
"@
    }
}

# Rule 2/3/4: approval, delegation, and first-edit reminder
if ($sessionId) {
    $sessDir = Join-Path $script:SessionRoot $sessionId
    $editedFilesPath = Join-Path $sessDir "edited-files.json"
    $state = Get-JsonFile -Path (Join-Path $sessDir "state.json")
    $runPacket = Get-JsonFile -Path (Join-Path $sessDir "run-packet.json")
    $planPath = Join-Path $sessDir "plan.md"
    $editedFiles = @{}
    if (Test-Path $editedFilesPath) {
        try {
            $loaded = Get-Content $editedFilesPath -Raw -Encoding UTF8 | ConvertFrom-Json
            foreach ($p in $loaded.PSObject.Properties) {
                $editedFiles[$p.Name] = $p.Value
            }
        } catch {}
    }

    $scope = if ($state) { [string]$state.scope } else { "" }
    $needsApprovedPlan = @("SHARED", "CRITICAL") -contains $scope
    $approvalStatus = if ($runPacket) { [string]$runPacket.approval_status } else { "" }
    $planApproved = $approvalStatus -ieq "approved"
    if ($needsApprovedPlan -and ((-not $planApproved) -or (-not (Test-Path $planPath)))) {
        Block-WithReason @"
Blocked by kit hook (write-gateguard/plan-approval):

This session attempted a source edit before the approved build contract existed.
For SHARED and CRITICAL build work, source-code edits require:

  1. ~/.agents/session-state/$sessionId/plan.md
  2. ~/.agents/session-state/$sessionId/run-packet.json with
     approval_status = approved

Run /plan (or refresh the existing plan), record approval, then retry the edit.
"@
    }
    if ($needsApprovedPlan -and $state -and -not $state.gates.plan_approved) {
        $stateGate = Join-Path $script:Tools "state-gate.ps1"
        if (Test-Path $stateGate) {
            try {
                & $script:AgentsShell -NoProfile -File $stateGate -SessionId $sessionId -Mark "plan_approved" 2>&1 | Out-Null
            } catch {}
        }
    }

    $isFirstEdit = -not $editedFiles.ContainsKey($normalizedTarget)
    $editedFileCountAfterCurrent = @($editedFiles.Keys).Count + $(if ($isFirstEdit) { 1 } else { 0 })

    if ($editedFileCountAfterCurrent -gt 1 -and -not (Test-WorkflowImplementerRegistered -State $state)) {
        Block-WithReason @"
Blocked by kit hook (write-gateguard/implementation-delegation):

This edit would touch more than one unique source file in the current session,
but no workflow implementer has been registered yet. Multi-file or non-trivial
build work must delegate implementation instead of keeping code edits inline in
the main session.

To resolve:
  1. Spawn workflow-implementer.
  2. Let the implementer perform the multi-file source edits.
  3. Keep the main session as coordinator.
"@
    }

    if ($isFirstEdit -and -not ($disabledHooks -contains "first-edit-gate")) {
        # Mark the file as edited so subsequent edits don't re-trigger
        $editedFiles[$normalizedTarget] = (Get-Date).ToString("o")
        if (Test-Path $sessDir) {
            try {
                ($editedFiles | ConvertTo-Json -Depth 3) | Set-Content -Path $editedFilesPath -Encoding UTF8
            } catch {}
        }
        # Soft-warn (NOT block) on first edit -- ECC's GateGuard blocks but
        # that's too strict for our cross-CLI users. Soft-warn surfaces the
        # convention without breaking flow. Stop hook will catch unverified
        # ones.
        # NOTE: Claude Code prints stderr from PreToolUse even on exit 0 in
        # most versions, so this serves as an inline reminder.
        $reminder = "Kit hook (write-gateguard/first-edit-gate): first edit to ``$targetFile`` this session. Recommend: pwsh ~/.agents/tools/wiki-resolver.ps1 -ChangedFiles ``$targetFile`` -RepoRoot . to load relevant wiki context."
        [Console]::Error.WriteLine($reminder)
    }
}

exit 0
