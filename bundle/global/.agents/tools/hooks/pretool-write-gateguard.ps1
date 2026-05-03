#!/usr/bin/env pwsh
# pretool-write-gateguard.ps1 -- PreToolUse hook for Write / Edit tools.
#
# Two enforcement rules at the protocol layer:
#   1. Wiki existence: if the file being edited is source code AND
#      .wiki/index.md does NOT exist, block with /wiki-init suggestion.
#      (The wiki rule has been "mandatory" in prose since v0.3 -- empirical
#      compliance was 0%. Hook makes it real.)
#   2. First-edit-per-file gate: if this is the first time this file has
#      been edited in this session AND the file is non-trivial source code,
#      block until the agent has run wiki-resolver against it. Mirrors
#      ECC's GateGuard Fact-Force pattern: "investigate before mutating."
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
if (-not $targetFile) { exit 0 }

# Skip non-source-code files: docs, configs, lockfiles, gitignored stuff.
# The wiki rule is for code that ships features. Let test/scratch/doc edits
# pass without ceremony.
$srcPattern = '\.(ts|tsx|js|jsx|py|go|rs|java|cs|rb|php|swift|kt|scala|cpp|c|h|hpp|vue|svelte|astro)$'
$ignorePattern = '(\.test\.|\.spec\.|/tests?/|/__tests__/|/fixtures/|/dist/|/build/|/node_modules/|/\.venv/|/__pycache__/)'
if ($targetFile -notmatch $srcPattern) { exit 0 }
if ($targetFile -match $ignorePattern) { exit 0 }

$sessionId = $payload.session_id
$cwd = (Get-Location).Path

function Block-WithReason {
    param([string]$Reason)
    [Console]::Error.WriteLine($Reason)
    exit 2
}

# Rule 1: wiki existence
if (-not ($disabledHooks -contains "wiki-existence")) {
    $wikiIndex = Join-Path $cwd ".wiki/index.md"
    if (-not (Test-Path $wikiIndex)) {
        Block-WithReason @"
Blocked by kit hook (write-gateguard/wiki-existence):

This repo has no .wiki/index.md. The kit's always-on rules require .wiki/
to exist before non-trivial source code edits, so future agents (and
reviewers) have a documented entry point.

To resolve:
  Run /wiki-init to bootstrap .wiki/ from real code evidence.

To bypass entirely:
  Set KIT_DISABLED_HOOKS=wiki-existence and retry the edit.

If this repo deliberately has its own pipeline (and you want the kit to
defer), add <!-- agentic-kit:disable-lifecycle --> to its CLAUDE.md.
"@
    }
}

# Rule 2: first-edit-per-file gate (GateGuard pattern)
if (-not ($disabledHooks -contains "first-edit-gate") -and $sessionId) {
    $sessDir = Join-Path $script:SessionRoot $sessionId
    $editedFilesPath = Join-Path $sessDir "edited-files.json"
    $editedFiles = @{}
    if (Test-Path $editedFilesPath) {
        try {
            $loaded = Get-Content $editedFilesPath -Raw -Encoding UTF8 | ConvertFrom-Json
            foreach ($p in $loaded.PSObject.Properties) {
                $editedFiles[$p.Name] = $p.Value
            }
        } catch {}
    }
    $normalizedTarget = $targetFile -replace '\\', '/'
    $isFirstEdit = -not $editedFiles.ContainsKey($normalizedTarget)

    if ($isFirstEdit) {
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
