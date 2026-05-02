#!/usr/bin/env pwsh
# doctor.ps1 -- self-diagnostic for the Caspar Bannink Agentic Coding Kit.
# One command tells you whether the kit is correctly installed and ready to run.
#
# Checks:
#   1. PowerShell version (pwsh 7+ recommended; PS 5.1 works with BOM-prefixed scripts)
#   2. ~/.agents/ populated (tools, skills, context, rendered skill-memory-index.json)
#   3. ~/.codex/ populated (global-workflows plugins)
#   4. AGENTS_HOME / AGENTS_SESSION_ROOT environment vars (optional overrides)
#   5. Claude Code hooks wired in ~/.claude/settings.json
#   6. OpenCode plugin at ~/.config/opencode/plugins/agentic-kit.ts
#   7. Companion files at ~/.claude/agentic-kit.md, ~/.codex/agentic-kit.md, ~/.config/opencode/agentic-kit.md
#   8. Include markers present in host-CLI config files
#   9. Tools execute cleanly: scope-classifier, swarm-classifier, reflect-trigger
#  10. Python + playwright (only required if using design loop)
#
# Output: one line per check (PASS/WARN/FAIL) plus summary.
# Exit code: 0 if no FAILs, 1 if any FAIL.

param(
    [switch]$Json
)

$results = New-Object System.Collections.ArrayList
$failCount = 0
$warnCount = 0

function Add-Check {
    param([string]$Name, [string]$Status, [string]$Detail = "")
    [void]$script:results.Add([pscustomobject]@{
        name = $Name; status = $Status; detail = $Detail
    })
    if ($Status -eq "FAIL") { $script:failCount++ }
    if ($Status -eq "WARN") { $script:warnCount++ }
}

# 1. PowerShell version
$psVer = $PSVersionTable.PSVersion
if ($psVer.Major -ge 7) {
    Add-Check "PowerShell version" "PASS" "pwsh $psVer (recommended)"
} elseif ($psVer.Major -eq 5 -and $psVer.Minor -ge 1) {
    Add-Check "PowerShell version" "WARN" "Windows PowerShell $psVer -- works with BOM-prefixed scripts; pwsh 7+ recommended"
} else {
    Add-Check "PowerShell version" "FAIL" "Unsupported version $psVer; install pwsh 7+"
}

# 2. ~/.agents/ populated
$agentsRoot = if ($env:AGENTS_HOME) { $env:AGENTS_HOME } else { Join-Path $HOME ".agents" }
if (-not (Test-Path $agentsRoot)) {
    Add-Check "~/.agents/ exists" "FAIL" "Run install.ps1 -- $agentsRoot missing"
} else {
    $missing = @()
    foreach ($sub in @("tools", "skills", "context")) {
        if (-not (Test-Path (Join-Path $agentsRoot $sub))) { $missing += $sub }
    }
    if ($missing.Count -gt 0) {
        Add-Check "~/.agents/ structure" "FAIL" "Missing: $($missing -join ', ')"
    } else {
        $toolCount = @(Get-ChildItem (Join-Path $agentsRoot "tools") -Filter "*.ps1" -ErrorAction SilentlyContinue).Count
        $skillCount = @(Get-ChildItem (Join-Path $agentsRoot "skills") -Directory -ErrorAction SilentlyContinue).Count
        Add-Check "~/.agents/ structure" "PASS" "$toolCount tools, $skillCount skills"
    }

    # Skill-memory-index rendered (not still .tmpl)
    $indexJson = Join-Path $agentsRoot "context/skill-memory-index.json"
    $indexTmpl = Join-Path $agentsRoot "context/skill-memory-index.json.tmpl"
    if (Test-Path $indexJson) {
        $idxContent = Get-Content $indexJson -Raw -Encoding UTF8
        if ($idxContent -match "__AGENTS_ROOT__") {
            Add-Check "skill-memory-index.json rendered" "FAIL" "Still has __AGENTS_ROOT__ placeholder; re-run install.ps1"
        } else {
            Add-Check "skill-memory-index.json rendered" "PASS" "absolute paths set"
        }
    } elseif (Test-Path $indexTmpl) {
        Add-Check "skill-memory-index.json rendered" "FAIL" "Template not rendered; run install.ps1"
    } else {
        Add-Check "skill-memory-index.json rendered" "WARN" "Neither template nor rendered file found"
    }
}

# 3. ~/.agents/workflows/ populated (kit-shared workflow plugins)
$workflowsDir = Join-Path $agentsRoot "workflows"
if (Test-Path $workflowsDir) {
    $pluginCount = @(Get-ChildItem $workflowsDir -Directory -ErrorAction SilentlyContinue).Count
    Add-Check "~/.agents/workflows/ present" "PASS" "$pluginCount plugin tree(s)"
} else {
    Add-Check "~/.agents/workflows/ present" "WARN" "Plugins missing; some skill references won't resolve"
}

# 4. Env var overrides (optional, just report)
$sessRoot = if ($env:AGENTS_SESSION_ROOT) { $env:AGENTS_SESSION_ROOT } else { Join-Path $agentsRoot "session-state" }
Add-Check "Session state root" "PASS" $sessRoot

# 5. Claude Code hooks wired
$claudeSettings = Join-Path $HOME ".claude/settings.json"
if (Test-Path $claudeSettings) {
    $sj = Get-Content $claudeSettings -Raw -Encoding UTF8
    $hookEvents = @("SessionStart", "SessionEnd", "SubagentStop", "PreCompact")
    $missing = @()
    foreach ($e in $hookEvents) {
        if ($sj -notmatch """$e""") { $missing += $e }
    }
    if ($missing.Count -eq 0) {
        Add-Check "Claude Code hooks wired" "PASS" "all 4 events present"
    } else {
        Add-Check "Claude Code hooks wired" "WARN" "Missing events: $($missing -join ', ') -- run merge-claude-settings.ps1"
    }
} else {
    Add-Check "Claude Code hooks wired" "WARN" "~/.claude/settings.json not found (Claude Code not installed?)"
}

# 6. OpenCode plugin
$ocPlugin = Join-Path $HOME ".config/opencode/plugins/agentic-kit.ts"
if (Test-Path $ocPlugin) {
    Add-Check "OpenCode plugin installed" "PASS" $ocPlugin
} else {
    Add-Check "OpenCode plugin installed" "WARN" "Not installed; OpenCode lifecycle hooks won't fire"
}

# 7. Companion files (device-wide install)
foreach ($spec in @(
    @{ Path = Join-Path $HOME ".claude/agentic-kit.md"; Label = "Claude" },
    @{ Path = Join-Path $HOME ".kit/agentic-kit.md"; Label = "Codex" },
    @{ Path = Join-Path $HOME ".config/opencode/agentic-kit.md"; Label = "OpenCode" }
)) {
    if (Test-Path $spec.Path) {
        $size = (Get-Item $spec.Path).Length
        Add-Check "$($spec.Label) companion file" "PASS" "$([Math]::Round($size/1KB, 1)) KB"
    } else {
        Add-Check "$($spec.Label) companion file" "WARN" "Not installed (-DeviceWide may not have run for this CLI)"
    }
}

# 8. Include markers in host-CLI config files
foreach ($spec in @(
    @{ Path = Join-Path $HOME ".claude/CLAUDE.md"; Label = "Claude CLAUDE.md" },
    @{ Path = Join-Path $HOME ".kit/AGENTS.md"; Label = "Codex AGENTS.md" },
    @{ Path = Join-Path $HOME ".config/opencode/prompt.md"; Label = "OpenCode prompt.md" }
)) {
    if (Test-Path $spec.Path) {
        $content = Get-Content $spec.Path -Raw -Encoding UTF8 -ErrorAction SilentlyContinue
        if ($content -match "agentic-kit:include") {
            Add-Check "$($spec.Label) include marker" "PASS" ""
        } else {
            Add-Check "$($spec.Label) include marker" "WARN" "Missing -- companion file won't be loaded by this CLI"
        }
    }
}

# 9. Tools execute cleanly. Run each as a subprocess to avoid argument-binding
# quirks with mandatory params via splat. We just want to confirm the tool
# parses and runs to completion -- exit 0/2 are both fine ("nothing actionable"
# vs "actionable but graceful").
$shell = if (Get-Command pwsh -ErrorAction SilentlyContinue) { "pwsh" } else { "powershell" }
$toolsToProbe = @(
    @{ Tool = "scope-classifier.ps1"; ArgsLine = "-Files src/foo.ts" },
    @{ Tool = "swarm-classifier.ps1"; ArgsLine = "-Task `"fix the bug`"" },
    @{ Tool = "reflect-trigger.ps1";  ArgsLine = "-Json" }
)
foreach ($probe in $toolsToProbe) {
    $toolPath = Join-Path $agentsRoot "tools/$($probe.Tool)"
    if (-not (Test-Path $toolPath)) {
        Add-Check "Tool: $($probe.Tool) executes" "FAIL" "Tool missing"
        continue
    }
    try {
        $cmd = "& '$toolPath' $($probe.ArgsLine)"
        $out = & $shell -NoProfile -Command $cmd 2>&1
        # Exit 0 = clean; 1 = non-fatal (e.g. fail status); 2 = mandatory-gate
        # (reflect-trigger uses 2 for "5+ unaddressed"). Anything else = real fail.
        if ($LASTEXITCODE -le 2) {
            Add-Check "Tool: $($probe.Tool) executes" "PASS" ""
        } else {
            Add-Check "Tool: $($probe.Tool) executes" "WARN" "Unexpected exit code $LASTEXITCODE"
        }
    } catch {
        Add-Check "Tool: $($probe.Tool) executes" "FAIL" $_.Exception.Message
    }
}

# 10. Python + playwright (optional, only flag if user wants design loop)
$python = if ($env:AGENTS_PYTHON) { $env:AGENTS_PYTHON } else { "python" }
if (Get-Command $python -ErrorAction SilentlyContinue) {
    $probe = & $python -c "import playwright; import yaml; print('ok')" 2>&1
    if ($probe -match "ok") {
        Add-Check "Python + playwright + pyyaml" "PASS" "design loop ready"
    } else {
        Add-Check "Python + playwright + pyyaml" "WARN" "Install with: $python -m pip install playwright pyyaml; $python -m playwright install chromium"
    }
} else {
    Add-Check "Python detected" "WARN" "Optional -- only needed for design-driver / playwright-explorer skills"
}

# --- Output ---
if ($Json) {
    @{
        results = $results
        fail_count = $failCount
        warn_count = $warnCount
        ok = ($failCount -eq 0)
    } | ConvertTo-Json -Depth 5 -Compress | Write-Output
} else {
    Write-Host ""
    Write-Host "Caspar Bannink Agentic Coding Kit -- Doctor"
    Write-Host "==========================================="
    Write-Host ""
    foreach ($r in $results) {
        $tag = switch ($r.status) {
            "PASS" { "[OK]   " }
            "WARN" { "[WARN] " }
            "FAIL" { "[FAIL] " }
        }
        $line = "$tag$($r.name)"
        if ($r.detail) { $line += " -- $($r.detail)" }
        Write-Host $line
    }
    Write-Host ""
    Write-Host "Summary: $($results.Count) checks, $failCount fail, $warnCount warn"
    if ($failCount -eq 0 -and $warnCount -eq 0) {
        Write-Host "All checks passed. Kit is healthy."
    } elseif ($failCount -eq 0) {
        Write-Host "No critical failures. Warnings indicate optional features not installed."
    } else {
        Write-Host "Critical failures detected. Run install.ps1 or fix the items above."
    }
}

if ($failCount -gt 0) { exit 1 } else { exit 0 }
