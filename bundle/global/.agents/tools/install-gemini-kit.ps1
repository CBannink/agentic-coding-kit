# install-gemini-kit.ps1
# Installs the Caspar Bannink Agentic Coding Kit into Google's official Gemini CLI.
# Mirrors the Claude Code setup: skills, subagents, commands, hooks, GEMINI.md.
#
# Idempotent: safe to re-run. Backs up any existing files first.
#
# Usage:
#   pwsh ~/.agents/tools/install-gemini-kit.ps1            # install
#   pwsh ~/.agents/tools/install-gemini-kit.ps1 -DryRun    # show what would happen
#   pwsh ~/.agents/tools/install-gemini-kit.ps1 -Force     # overwrite without prompting

[CmdletBinding()]
param(
    [switch]$DryRun,
    [switch]$Force,
    [switch]$NoBackup
)

$ErrorActionPreference = 'Stop'

# ---------- paths ----------
$ClaudeRoot = Join-Path $HOME ".claude"
$GeminiRoot = Join-Path $HOME ".gemini"
$AgentsRoot = Join-Path $HOME ".agents"

$Stamp = Get-Date -Format 'yyyyMMdd-HHmmss'

if (-not (Test-Path $ClaudeRoot)) { throw "No ~/.claude -- nothing to port from." }
if (-not (Test-Path $GeminiRoot)) { New-Item -ItemType Directory -Path $GeminiRoot | Out-Null }

function Say([string]$msg, [string]$color='White') { Write-Host $msg -ForegroundColor $color }
function Skip([string]$msg) { Say "  SKIP  $msg" 'DarkGray' }
function Do-It([string]$msg) { Say "  DO    $msg" 'Green' }
function Warn([string]$msg) { Say "  WARN  $msg" 'Yellow' }

$Utf8NoBom = New-Object System.Text.UTF8Encoding($false)
function Write-NoBom([string]$path, [string]$content) {
    [System.IO.File]::WriteAllText($path, $content, $Utf8NoBom)
}

# ---------- detect existing kit install ----------
# Re-running the installer used to silently pile up `.before-gemini-kit-<stamp>`
# backups for every file it touched -- which Gemini was then double-loading and
# warning about. Detect an existing install up front, ask the user whether to
# overwrite, and (default) clean-overwrite without keeping accumulating backups.
$KitFingerprints = @(
    Join-Path $GeminiRoot 'GEMINI.md'
    Join-Path $GeminiRoot 'agentic-kit.md'
    Join-Path $GeminiRoot 'agents'
    Join-Path $GeminiRoot 'skills'
    Join-Path $GeminiRoot 'commands'
)
$existingKitPaths = @($KitFingerprints | Where-Object { Test-Path $_ })

# Also detect stale `.before-gemini-kit-*` backups so we can clean them up
$staleBackups = @(Get-ChildItem -LiteralPath $GeminiRoot -Filter '*.before-gemini-kit-*' -Force -ErrorAction SilentlyContinue)

if ($existingKitPaths.Count -gt 0 -or $staleBackups.Count -gt 0) {
    Say "`nExisting Gemini kit install detected in $GeminiRoot." 'Yellow'
    if ($existingKitPaths.Count -gt 0) {
        Say "  Live kit files/folders:" 'Yellow'
        foreach ($p in $existingKitPaths) { Say "    - $p" 'DarkYellow' }
    }
    if ($staleBackups.Count -gt 0) {
        Say "  Stale backups from prior installs ($($staleBackups.Count)):" 'Yellow'
        foreach ($b in $staleBackups | Select-Object -First 8) { Say "    - $($b.Name)" 'DarkGray' }
        if ($staleBackups.Count -gt 8) { Say "    ... and $($staleBackups.Count - 8) more" 'DarkGray' }
    }
    Say "  Continuing will OVERWRITE the live kit files and DELETE the stale backups." 'Yellow'

    if ($DryRun) {
        Say "  (dry run -- skipping prompt)" 'DarkGray'
    } elseif ($Force) {
        Say "  -Force given -- proceeding without prompt." 'DarkGray'
    } else {
        $resp = Read-Host "Continue and overwrite? [y/N]"
        if ($resp -notmatch '^(y|yes)$') {
            Say "Aborted." 'Red'
            exit 1
        }
    }

    # Clean up stale backups so they stop accumulating across re-runs.
    if (-not $DryRun -and $staleBackups.Count -gt 0) {
        foreach ($b in $staleBackups) {
            try { Remove-Item -LiteralPath $b.FullName -Recurse -Force -ErrorAction Stop } catch { Warn "could not remove $($b.FullName): $_" }
        }
        Do-It "removed $($staleBackups.Count) stale .before-gemini-kit-* entries"
    }
}

function Backup([string]$path) {
    if (-not (Test-Path $path)) { return }
    if ($NoBackup -or $Force) {
        if ($DryRun) { Skip "would remove $path (no backup)" }
        else { Remove-Item -LiteralPath $path -Recurse -Force; Do-It "removed $path (no backup)" }
        return
    }
    $bk = "$path.before-gemini-kit-$Stamp"
    if ($DryRun) { Skip "would back up $path -> $bk" }
    else { Move-Item -LiteralPath $path -Destination $bk -Force; Do-It "backed up $path -> $bk" }
}

# ---------- 1. GEMINI.md (sync canonical block from ~/.agents/global-instructions.md) ----------
Say "`n[1/6] GEMINI.md (sync canonical block + preserve host preamble)" 'Cyan'
$canonicalPath = Join-Path $AgentsRoot 'global-instructions.md'
$claudeMd = Join-Path $ClaudeRoot 'CLAUDE.md'
$geminiMd = Join-Path $GeminiRoot 'GEMINI.md'

# Source preference: canonical -> CLAUDE.md fallback (for backwards compat).
$sourcePath = if (Test-Path $canonicalPath) { $canonicalPath } else { $claudeMd }

if (Test-Path $sourcePath) {
    if (-not $DryRun) {
        $content = Get-Content -LiteralPath $sourcePath -Raw -Encoding utf8
        # Translate Claude-specific env var references to Gemini equivalents.
        $content = $content -replace 'CLAUDE_SESSION_ID', 'GEMINI_SESSION_ID'
        $content = $content -replace 'CLAUDE_PROJECT_DIR', 'GEMINI_PROJECT_DIR'
        $content = $content -replace 'CLAUDE_SUBAGENT_NAME', 'GEMINI_AGENT_NAME'
        $content = $content -replace 'CLAUDE_SUBAGENT_STATUS', 'GEMINI_AGENT_STATUS'
        $content = $content -replace 'CLAUDE_MODE', 'GEMINI_MODE'

        $preamble = @"
# Gemini CLI Global Instructions (Caspar Bannink Agentic Coding Kit)

Loaded by the official Gemini CLI from `~/.gemini/GEMINI.md`.
Mirrors `~/.claude/CLAUDE.md`. Same kit, same rules, different host.

Hooks env vars use the GEMINI_* namespace (GEMINI_SESSION_ID, GEMINI_PROJECT_DIR).
Hook event names use Gemini's terminology (SessionStart, SessionEnd, AfterAgent,
PreCompress, BeforeTool, AfterTool).

---

## ROUTING (READ FIRST -- applies to every turn)

**You ARE the orchestrator. Default to invoking a workflow command. Do not start
implementing, investigating, or reviewing inline unless the task is trivial.**

When the user gives you a task, your FIRST step is to classify it and route to a
workflow. Pattern-match -- do NOT wait for the user to type a slash command:

- Build, implement, add, fix, refactor, change code -> **invoke ``/build``**
- Investigate, debug, diagnose, trace, root-cause, "why is X broken" -> **invoke ``/investigate``**
- Review, audit, check quality/security of existing code -> **invoke ``/review``**
- Research, compare, evaluate, explore an unfamiliar repo/idea -> **invoke ``/analyze``**
- Ship, push, create PR, merge -> **invoke ``/pr``**
- Plan a feature before coding -> **invoke ``/plan``** or ``/spec``
- Refactor architecture or enforce standards -> **invoke ``/refactor``**
- Greenfield UI / multi-component visual redesign -> **invoke ``/redesign``**
- Security pentest / adversarial audit -> **invoke ``/security-review``**

**ONLY skip the workflow when:**
- Trivial mechanical task (rename, typo, single-line edit, formatting).
- Pure factual / conceptual question with no code change ("what does this do?",
  "explain this snippet", "what's the difference between X and Y").
- The user explicitly asks for a quick/raw change ("just edit the file", "no loop").

**If genuinely ambiguous between two workflows**, ask ONE short routing question,
then invoke. Do not enter a long clarification dialogue -- the workflow's own first
phase handles scoping.

This is non-negotiable. Inline implementation without routing is the most common
failure mode of this setup; the loops exist because they catch what direct
execution misses.

---

"@
        # Marker-based sync: replace canonical block in place, preserve host preamble + any custom user content outside markers.
        # Canonical is marker-less; wrap with markers at write time.
        $beginMarker = '<!-- agentic-kit:begin -->'
        $endMarker   = '<!-- agentic-kit:end -->'
        $wrapped = "$beginMarker`r`n" + $content.TrimEnd() + "`r`n$endMarker"

        if (Test-Path $geminiMd) {
            $current = Get-Content -Raw -Encoding utf8 -LiteralPath $geminiMd

            # Strip every known kit-block variant first; prevents marker-schism
            # duplicates from older kit versions accumulating.
            $stripPatterns = @(
                "(?s)<!-- agentic-kit:begin -->.*?<!-- agentic-kit:end -->\s*",
                "(?s)<!-- agentic-kit:include -->.*?<!-- /agentic-kit:include -->\s*",
                "(?s)<!-- agentic-kit:include -->.*?<!-- agentic-kit:end -->\s*",
                "(?s)<!-- agentic-kit:begin -->.*?<!-- /agentic-kit:include -->\s*"
            )
            $hadKitBlock = $false
            $cleaned = $current
            foreach ($p in $stripPatterns) {
                $before = $cleaned
                $cleaned = [regex]::Replace($cleaned, $p, '')
                if ($before -ne $cleaned) { $hadKitBlock = $true }
            }

            if ($hadKitBlock) {
                # Reuse cleaned host content, prepend fresh wrapped canonical block.
                $updated = $wrapped.TrimEnd() + "`r`n`r`n" + $cleaned.TrimStart()
                Write-NoBom $geminiMd $updated
                Do-It "replaced canonical block in $geminiMd (host preamble preserved)"
            } else {
                # No prior kit block: full rewrite with preamble + wrapped canonical.
                Backup $geminiMd
                Write-NoBom $geminiMd ($preamble + $wrapped)
                Do-It "wrote $geminiMd (full rewrite -- canonical wrapped with begin/end markers)"
            }
        } else {
            Write-NoBom $geminiMd ($preamble + $wrapped)
            Do-It "created $geminiMd"
        }
    } else { Skip "would generate $geminiMd" }
} else { Warn "no canonical or CLAUDE.md source found -- skipping GEMINI.md" }

# Copy agentic-kit reference doc
$kitRefSrc = Join-Path $ClaudeRoot 'agentic-kit.md'
$kitRefDst = Join-Path $GeminiRoot 'agentic-kit.md'
if (Test-Path $kitRefSrc) {
    if ($DryRun) { Skip "would copy agentic-kit.md" }
    else { Copy-Item -LiteralPath $kitRefSrc -Destination $kitRefDst -Force; Do-It "copied agentic-kit.md" }
}

# ---------- 2. skills (selective junctions: filter by frontmatter `name:`, not dir name) ----------
# Gemini matches skills by the `name:` field inside SKILL.md, NOT by directory name.
# Many skills have name != dir (e.g. dir "connect-chrome" defines name "open-gstack-browser").
# Earlier versions of this installer filtered by dir name and missed cross-dir name
# collisions, so users saw "Skill conflict detected" warnings on every launch. The
# correct rule: parse each SKILL.md's `name:` and skip any skill whose name is
# already provided by ~/.agents/skills (auto-loaded by Gemini's built-in alias).
Say "`n[2/6] Skills (selective: filter by frontmatter name, dedupe vs ~/.agents/skills)" 'Cyan'
$claudeSkills = Join-Path $ClaudeRoot 'skills'
$agentsSkills = Join-Path $AgentsRoot 'skills'
$geminiSkills = Join-Path $GeminiRoot 'skills'

function Get-SkillName([string]$skillDir) {
    $skillFile = Join-Path $skillDir 'SKILL.md'
    if (-not (Test-Path $skillFile)) { return $null }
    $raw = Get-Content -Raw -Encoding utf8 -LiteralPath $skillFile
    if ($raw -match '(?ms)^---\s*\r?\n(.*?)\r?\n---') {
        $fm = $matches[1]
        if ($fm -match '(?m)^name:\s*(\S+)') {
            return ($matches[1].Trim() -replace '^["'']|["'']$','')
        }
    }
    return (Split-Path $skillDir -Leaf)
}

if (Test-Path $claudeSkills) {
    if (Test-Path $geminiSkills) {
        if ($DryRun) { Skip "would remove existing $geminiSkills" }
        else { Remove-Item -LiteralPath $geminiSkills -Recurse -Force; Do-It "removed prior $geminiSkills" }
    }

    # Names already provided by ~/.agents/skills (Gemini auto-loads these)
    $autoNames = @{}
    if (Test-Path $agentsSkills) {
        Get-ChildItem -LiteralPath $agentsSkills -Directory | ForEach-Object {
            $n = Get-SkillName $_.FullName
            if ($n) { $autoNames[$n] = $_.FullName }
        }
    }

    if (-not $DryRun) { New-Item -ItemType Directory -Path $geminiSkills -Force | Out-Null }

    $linked = 0; $skippedAuto = 0; $skippedDup = 0
    $linkedNames = @{}
    Get-ChildItem -LiteralPath $claudeSkills -Directory | ForEach-Object {
        $name = Get-SkillName $_.FullName
        if (-not $name) { return }
        if ($autoNames.ContainsKey($name))   { $skippedAuto++; return }
        if ($linkedNames.ContainsKey($name)) {
            # Two Claude dirs define the same skill name. Prefer the one whose dir matches the name.
            $existingDir = Split-Path $linkedNames[$name] -Leaf
            if ($existingDir -eq $name) { $skippedDup++; return }
            if ($_.Name -eq $name) {
                # Replace the previously-linked entry with this better-matched one.
                $oldTgt = Join-Path $geminiSkills (Split-Path $linkedNames[$name] -Leaf)
                if (-not $DryRun -and (Test-Path $oldTgt)) { Remove-Item -LiteralPath $oldTgt -Recurse -Force }
                $skippedDup++
            } else {
                $skippedDup++; return
            }
        }
        $tgt = Join-Path $geminiSkills $_.Name
        if ($DryRun) { Skip "would junction $tgt" }
        else { New-Item -ItemType Junction -Path $tgt -Target $_.FullName | Out-Null }
        $linkedNames[$name] = $_.FullName
        $linked++
    }
    Do-It "$linked Claude-only skill junctions linked"
    if ($skippedAuto -gt 0) { Say "  skipped $skippedAuto already provided by ~/.agents/skills" 'DarkGray' }
    if ($skippedDup  -gt 0) { Say "  skipped $skippedDup duplicate-name in-repo collisions"     'DarkGray' }
} else { Warn "no ~/.claude/skills found" }

# ---------- 3. agents (subagents) ----------
Say "`n[3/6] Subagents (junction link from ~/.claude/agents)" 'Cyan'
$claudeAgents = Join-Path $ClaudeRoot 'agents'
$geminiAgents = Join-Path $GeminiRoot 'agents'
if (Test-Path $claudeAgents) {
    Backup $geminiAgents
    if ($DryRun) { Skip "would junction $geminiAgents -> $claudeAgents" }
    else {
        New-Item -ItemType Junction -Path $geminiAgents -Target $claudeAgents | Out-Null
        Do-It "junction $geminiAgents -> $claudeAgents"
    }
} else { Warn "no ~/.claude/agents found" }

# ---------- 4. commands (DISABLED -- skills already expose slash commands) ----------
# Every .md in ~/.claude/commands has the same name as a skill (/build, /plan, /review, ...).
# Gemini exposes each skill as a slash command automatically, so generating .toml here
# creates "Conflicts detected" warnings that rename every command to /buildN, /user.build, etc.
# Skip the entire step. If a host genuinely needs commands separate from skills, re-enable
# selectively here.
Say "`n[4/6] Commands (SKIPPED -- duplicates skill-exposed slash commands on Gemini)" 'Cyan'
$geminiCommands = Join-Path $GeminiRoot 'commands'
if (Test-Path $geminiCommands) {
    if ($DryRun) { Skip "would remove $geminiCommands (no longer generated)" }
    else { Remove-Item -LiteralPath $geminiCommands -Recurse -Force; Do-It "removed $geminiCommands (was duplicating skill commands)" }
}
# (commands generation block removed -- skills already expose every slash command on Gemini)

# ---------- 5. settings.json (merge hooks) ----------
Say "`n[5/6] settings.json (merge hooks, preserve OAuth)" 'Cyan'
$geminiSettings = Join-Path $GeminiRoot 'settings.json'

# Map Claude hook event names -> Gemini event names
$eventMap = @{
    'SessionStart' = 'SessionStart'
    'SessionEnd'   = 'SessionEnd'
    'SubagentStop' = 'AfterAgent'
    'PreCompact'   = 'PreCompress'
    'PreToolUse'   = 'BeforeTool'
    'PostToolUse'  = 'AfterTool'
    'Stop'         = 'AfterAgent'
}

# --- helpers: PS5.1-safe JSON <-> hashtable conversion ---
function ConvertTo-Hashtable($obj) {
    if ($null -eq $obj) { return $null }
    if ($obj -is [System.Collections.IDictionary]) {
        $h = @{}
        foreach ($k in $obj.Keys) { $h[$k] = ConvertTo-Hashtable $obj[$k] }
        return $h
    }
    if ($obj -is [System.Management.Automation.PSCustomObject]) {
        $h = @{}
        foreach ($p in $obj.PSObject.Properties) { $h[$p.Name] = ConvertTo-Hashtable $p.Value }
        return $h
    }
    if ($obj -is [System.Collections.IEnumerable] -and -not ($obj -is [string])) {
        return @($obj | ForEach-Object { ConvertTo-Hashtable $_ })
    }
    return $obj
}

# Load existing Gemini settings BEFORE backup/remove so non-hook keys survive.
# Earlier this loaded from the backup file, but with -Force the backup is skipped
# (Backup-Or-Remove deletes outright), so user customizations like model.name,
# general.plan.modelRouting, and security.auth would silently disappear on every
# re-install. Read first, then back up.
$existing = @{}
if (Test-Path $geminiSettings) {
    try {
        $raw = Get-Content -Raw -Encoding utf8 -LiteralPath $geminiSettings
        $existing = ConvertTo-Hashtable (ConvertFrom-Json $raw)
        if ($null -eq $existing) { $existing = @{} }
    } catch { $existing = @{} }
    Backup $geminiSettings
}

# Load Claude settings to read hooks
$claudeSettingsPath = Join-Path $ClaudeRoot 'settings.json'
if (-not (Test-Path $claudeSettingsPath)) { Warn "no ~/.claude/settings.json -- skipping hook port" }
else {
    $claudeCfg = ConvertTo-Hashtable (Get-Content -Raw -LiteralPath $claudeSettingsPath | ConvertFrom-Json)

    # Translate hooks
    $newHooks = @{}
    if ($claudeCfg.hooks) {
        foreach ($k in @($claudeCfg.hooks.Keys)) {
            $geminiEvent = if ($eventMap.ContainsKey($k)) { $eventMap[$k] } else { $k }
            $entries = @($claudeCfg.hooks[$k])
            $translated = @()
            foreach ($entry in $entries) {
                $hooksOut = @()
                foreach ($h in @($entry.hooks)) {
                    $cmd = [string]$h.command
                    $cmd = $cmd -replace 'CLAUDE_SESSION_ID', 'GEMINI_SESSION_ID'
                    $cmd = $cmd -replace 'CLAUDE_PROJECT_DIR', 'GEMINI_PROJECT_DIR'
                    $cmd = $cmd -replace 'CLAUDE_SUBAGENT_NAME', 'GEMINI_AGENT_NAME'
                    $cmd = $cmd -replace 'CLAUDE_SUBAGENT_STATUS', 'GEMINI_AGENT_STATUS'
                    $cmd = $cmd -replace 'CLAUDE_MODE', 'GEMINI_MODE'
                    $hooksOut += @{ type = [string]$h.type; command = $cmd }
                }
                $translated += @{ matcher = [string]$entry.matcher; hooks = $hooksOut }
            }
            $newHooks[$geminiEvent] = $translated
        }
    }

    if (-not $existing) { $existing = @{} }
    $existing['hooks'] = $newHooks
    if (-not $existing.ContainsKey('security')) {
        $existing['security'] = @{ auth = @{ selectedType = 'oauth-personal' } }
    }

    if ($DryRun) {
        Skip "would write merged settings.json with $($newHooks.Keys.Count) hook events"
        foreach ($evt in $newHooks.Keys) { Skip "  hook event: $evt" }
    } else {
        $json = $existing | ConvertTo-Json -Depth 20
        Write-NoBom $geminiSettings $json
        Do-It "wrote settings.json with hooks: $($newHooks.Keys -join ', ')"
    }
}

# ---------- 6. verify ----------
Say "`n[6/6] Verify" 'Cyan'
if ($DryRun) { Say "  (dry run -- skipping live checks)" 'DarkGray' }
else {
    Say "  -> Run 'gemini' and try: /skills list, /agents list, /commands list" 'DarkGray'
    Say "  -> If a command collides with a Gemini built-in it was renamed to /kit-<name>" 'DarkGray'
    Say "  -> Hooks fire on SessionStart / SessionEnd / AfterAgent / PreCompress / BeforeTool / AfterTool" 'DarkGray'
}

Say "`nDone." 'Green'
