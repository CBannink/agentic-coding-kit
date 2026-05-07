#!/usr/bin/env pwsh
# pretool-bash-dispatcher.ps1 -- PreToolUse hook for the Bash tool.
#
# Single hook, multiple rules. Reads Claude Code's PreToolUse JSON from
# stdin, pattern-matches the bash command, decides allow / block.
#
# Pattern from `affaan-m/everything-claude-code` and
# `disler/claude-code-hooks-mastery`: PreToolUse + exit 2 + reason on
# stderr both BLOCKS the call AND teaches the agent why it was blocked.
# `permissions.deny` cannot do the second part.
#
# Rules enforced:
#   1. Dangerous filesystem ops -> block
#        rm -rf /, rm -rf ~, sudo rm, chmod 777 on /, > /etc/, > /dev/sda
#   2. git push --force on main/master -> block (require confirm)
#   3. git commit -> verification_evidence gate must be marked
#                    in current session's state.json. If not, block.
#   4. npm test|pytest|cargo test|go test on success -> AUTO-MARK
#      verification_evidence (closes the Iron Law loop without agent thought)
#
# Opt-out: KIT_DISABLED_HOOKS env var, comma-separated names. To skip
# this entire hook: KIT_DISABLED_HOOKS=bash-dispatcher
# To skip just one rule: KIT_DISABLED_HOOKS=git-commit-verify
#
# Exit codes (Claude Code contract):
#   0 = allow tool call
#   2 = block tool call (stderr becomes the reason shown to agent)
#   anything else = treated as error / proceed

$ErrorActionPreference = "Continue"
. (Join-Path $PSScriptRoot "../_paths.ps1") -ErrorAction SilentlyContinue

# Universal opt-out
$disabledHooks = if ($env:KIT_DISABLED_HOOKS) { @($env:KIT_DISABLED_HOOKS -split ',') } else { @() }
if ($disabledHooks -contains "bash-dispatcher") { exit 0 }

# Read PreToolUse JSON payload from stdin
$rawInput = [Console]::In.ReadToEnd()
if (-not $rawInput) { exit 0 }
try {
    $payload = $rawInput | ConvertFrom-Json
} catch {
    # If we can't parse the payload, don't block -- that would be worse
    # than skipping enforcement
    exit 0
}

$cmd = ""
if ($payload.tool_input -and $payload.tool_input.command) {
    $cmd = [string]$payload.tool_input.command
}
if (-not $cmd) { exit 0 }

$cmdLower = $cmd.ToLower()
$sessionId = $payload.session_id

function Block-WithReason {
    param([string]$Reason)
    [Console]::Error.WriteLine($Reason)
    exit 2
}

# Rule 1: dangerous filesystem ops
# Strip quoted strings + heredocs before the check. Dangerous tokens
# inside "..." / '...' / @'...'@ / $(cat <<'EOF' ... EOF) are text
# content, not executed commands. Without this, the hook blocks any
# git commit / echo / heredoc whose body MENTIONS rm -rf etc. Live
# experience caught this when the kit's own commit was blocked.
$cmdStripped = $cmdLower
# Strip @'...'@ heredoc-style PowerShell strings
$cmdStripped = [regex]::Replace($cmdStripped, "@'.*?'@", "''", 'Singleline')
# Strip @"..."@ heredoc-style PowerShell strings
$cmdStripped = [regex]::Replace($cmdStripped, '@".*?"@', '""', 'Singleline')
# Strip bash heredocs: <<'EOF' ... EOF and <<"EOF" ... EOF
$cmdStripped = [regex]::Replace($cmdStripped, "<<'(\w+)'.*?\1", "''", 'Singleline')
$cmdStripped = [regex]::Replace($cmdStripped, '<<"?(\w+)"?.*?\1', '""', 'Singleline')
# Strip "..." double-quoted strings
$cmdStripped = [regex]::Replace($cmdStripped, '"[^"]*"', '""')
# Strip '...' single-quoted strings
$cmdStripped = [regex]::Replace($cmdStripped, "'[^']*'", "''")

if (-not ($disabledHooks -contains "dangerous-fs")) {
    if ($cmdStripped -match '\brm\s+-rf?\s+(/|~|\$home|\.\.\.)') {
        Block-WithReason "Blocked by kit hook (bash-dispatcher/dangerous-fs): 'rm -rf' targeting filesystem root, home, or '...' is destructive. If this is intentional, set KIT_DISABLED_HOOKS=dangerous-fs and rerun."
    }
    if ($cmdStripped -match '\bsudo\s+rm\b') {
        Block-WithReason "Blocked by kit hook (bash-dispatcher/dangerous-fs): 'sudo rm' is dangerous. If this is intentional, set KIT_DISABLED_HOOKS=dangerous-fs and rerun."
    }
    if ($cmdStripped -match '\bchmod\s+777\b') {
        Block-WithReason "Blocked by kit hook (bash-dispatcher/dangerous-fs): 'chmod 777' opens permissions to everyone. Use a more restrictive mode. To bypass: KIT_DISABLED_HOOKS=dangerous-fs."
    }
    # Whitelist /dev/null (universal bit-bucket) and /dev/std{in,out,err} BEFORE
    # the broader /dev/ check. Without this, every `2>/dev/null` redirect was
    # a false-positive that broke common shell idioms.
    $devCheck = $cmdStripped -replace '\d?>\s*/dev/(null|stdin|stdout|stderr)\b', ''
    if ($devCheck -match '>\s*(/etc/|/dev/|/sys/)') {
        Block-WithReason "Blocked by kit hook (bash-dispatcher/dangerous-fs): redirect to /etc/, /dev/<device>, or /sys/ is destructive at system level. (Note: /dev/null, /dev/std{in,out,err} are whitelisted.)"
    }
}

# Rule 2: git push --force to main/master
if (-not ($disabledHooks -contains "git-push-force")) {
    if ($cmdLower -match '\bgit\s+push\b' -and $cmdLower -match '(\-\-force|\-f\b)') {
        if ($cmdLower -match '\b(main|master)\b') {
            Block-WithReason "Blocked by kit hook (bash-dispatcher/git-push-force): force-pushing to main/master is destructive to shared history. Confirm with user explicitly. To bypass: KIT_DISABLED_HOOKS=git-push-force."
        }
    }
}

# Rule 3: git commit must have verification_evidence gate marked
if (-not ($disabledHooks -contains "git-commit-verify")) {
    if ($cmdLower -match '\bgit\s+commit\b' -and $sessionId) {
        $sessDir = Join-Path $script:SessionRoot $sessionId
        $statePath = Join-Path $sessDir "state.json"
        if (Test-Path $statePath) {
            try {
                $state = Get-Content $statePath -Raw -Encoding UTF8 | ConvertFrom-Json
                if (-not $state.gates.verification_evidence) {
                    Block-WithReason @"
Blocked by kit hook (bash-dispatcher/git-commit-verify): Iron Law violated.

The 'verification_evidence' gate is NOT marked for this session. You cannot
commit without fresh test/build evidence.

To resolve:
  1. Run your test suite, get green output.
  2. Mark the gate: pwsh ~/.agents/tools/state-gate.ps1 -SessionId $sessionId -Mark verification_evidence
  3. Retry the commit.

To bypass entirely (not recommended): KIT_DISABLED_HOOKS=git-commit-verify
"@
                }
            } catch {
                # state.json malformed -- don't block on tooling failure
            }
        }
    }
}

# Rule 4: auto-mark verification_evidence on test commands
# This is allow + side-effect, not block. We tag the session for
# post-tool-use to confirm the test passed. Implementation: write a marker
# file that PostToolUse can pick up and mark the gate if exit code was 0.
if (-not ($disabledHooks -contains "test-auto-mark") -and $sessionId) {
    if ($cmdLower -match '\b(npm\s+test|pytest|cargo\s+test|go\s+test|jest|vitest|mocha|rspec)\b') {
        $sessDir = Join-Path $script:SessionRoot $sessionId
        if (Test-Path $sessDir) {
            $markerFile = Join-Path $sessDir ".pending-verify-mark"
            try {
                Set-Content -Path $markerFile -Value $cmd -Encoding UTF8
            } catch {}
        }
    }
}

# All checks passed
exit 0
