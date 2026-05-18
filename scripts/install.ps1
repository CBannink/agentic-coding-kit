#!/usr/bin/env pwsh
# install.ps1 -- Caspar Bannink Agentic Coding Kit installer.
#
# Quick start (most users):
#   pwsh ./install.ps1 -For claude               # one CLI, device-wide
#   pwsh ./install.ps1 -For "claude,opencode"    # multiple
#   pwsh ./install.ps1 -For all                  # everything
#   pwsh ./install.ps1 -Auto                     # detect CLIs on PATH and install for those
#   pwsh ./install.ps1 -BootstrapHarness -TargetRepo C:\path\to\repo   # one-shot repo bootstrap
#
# Per-repo (advanced):
#   pwsh ./install.ps1 -TargetRepo C:\path\to\repo -InstallRepoTemplate -InstallAdapter claude
#   pwsh ./install.ps1 -TargetRepo C:\path\to\repo -InstallRepoTemplate -InstallAdapter all
#
# Upgrade (preserves customizations via backup):
#   pwsh ./install.ps1 -Upgrade -For claude
#
# Adapters: claude | codex | copilot | opencode | kilocode | generic | all
# `generic` writes a tool-neutral AGENTS.md (Aider, Cline, Cursor, etc. read it).
# `all` writes every adapter's files (they coexist; CLIs pick what they recognize).

param(
    [string]$HomeRoot = $HOME,
    [string]$TargetRepo = "",
    [switch]$InstallGlobal = $true,
    [switch]$InstallRepoTemplate,
    [string]$InstallAdapter = "",
    # The simple path: -For <cli-list> installs global assets + device-wide
    # config for the named CLIs. Same as -DeviceWide; new name is clearer.
    # Examples:
    #   -For claude               # one CLI
    #   -For "claude,opencode"    # multiple
    #   -For all                  # all 5 supported CLIs
    [string]$For = "",
    # Detect which CLIs are on PATH and install for those automatically.
    [switch]$Auto,
    # Legacy flag, kept for back-compat. Same behavior as -For.
    [string]$DeviceWide = "",
    [switch]$Upgrade,
    [switch]$Force,
    [switch]$BootstrapHarness,
    # When set, strips ALL kit blocks (current `:begin/:end` AND legacy `:include`
    # pairs) from every target host's instruction file and rewrites a single
    # canonical block. Use after a marker-schism duplicate accumulates.
    [switch]$RepairKitBlock,
    # When set, after writing kit-managed *.md files at command destinations,
    # prune any pre-existing *.md files that are no longer in the bundle.
    # Closes the f714a3b drift class (per-host commands moved to _shared/ but
    # old files were left orphaned at user destinations). Backs up each pruned
    # file alongside as <name>.pruned-<timestamp> instead of hard deleting.
    [switch]$PruneStaleAssets,
    # Combined with -PruneStaleAssets: list pruning candidates and exit
    # without deleting. Useful before a real prune.
    [switch]$DryRunPrune,
    # Wipe kit-managed destination directories (skills/, agents/, commands/)
    # for each targeted host BEFORE rewriting. User-mutable runtime state
    # (session-state/, context/handoffs.md, context/reflections.md, inspiration/
    # under ~/.agents/) is still preserved via the P3 snapshot/restore. Use
    # this when stale orphans from older kit versions accumulate (different
    # skill names, deleted agents, etc.). Implies -PruneStaleAssets.
    [switch]$CleanReinstall
)

$ScriptRoot   = Split-Path -Parent $MyInvocation.MyCommand.Path
$RepoRoot     = Split-Path -Parent $ScriptRoot
$BundleGlobal = Join-Path $RepoRoot "bundle/global"
$BundleRepo   = Join-Path $RepoRoot "bundle/repo-template"
$AdaptersRoot = Join-Path $RepoRoot "bundle/adapters"
$SharedWorkflowCommandsRoot = Join-Path $AdaptersRoot "_shared/workflow-commands"
$SharedWorkflowAgentsRoot = Join-Path $AdaptersRoot "_shared/workflow-agents"

$AgentsRoot = Join-Path $HomeRoot ".agents"

# Pre-flight: validate the bundle. Refuses to install a broken kit.
$validator = Join-Path $ScriptRoot "validate-bundle.ps1"
if (Test-Path $validator) {
    Write-Host "Pre-flight: running validate-bundle.ps1..."
    & $validator
    if ($LASTEXITCODE -ne 0 -and -not $Force) {
        Write-Error "Bundle validation FAILED. Re-run with -Force to install anyway."
        exit 1
    }
    Write-Host ""
}

function Copy-Tree {
    param(
        [string]$Source,
        [string]$Destination,
        [switch]$ReplaceDestination
    )
    if (-not (Test-Path $Source)) { return }
    if ($ReplaceDestination -and (Test-Path $Destination)) {
        Get-ChildItem -Force -LiteralPath $Destination -ErrorAction SilentlyContinue |
            Remove-Item -Recurse -Force -ErrorAction Stop
    }
    New-Item -ItemType Directory -Path $Destination -Force | Out-Null
    Copy-Item -Recurse -Force (Join-Path $Source '*') $Destination
}

function Render-Template {
    param([string]$Source, [string]$Destination, [hashtable]$Vars)
    if (-not (Test-Path $Source)) { return }
    $content = Get-Content $Source -Raw
    foreach ($k in $Vars.Keys) {
        $content = $content.Replace($k, $Vars[$k])
    }
    New-Item -ItemType Directory -Path (Split-Path -Parent $Destination) -Force | Out-Null
    # Strip BOM from source if present, write UTF-8 NO BOM. Set-Content -Encoding utf8
    # in Windows PowerShell 5.1 writes WITH BOM; Claude Code's YAML frontmatter parser
    # silently rejects agent / skill files that start with BOM. Symptom: the agent
    # appears installed on disk but does NOT show up in `claude -p "list agents"`.
    if ($content.Length -gt 0 -and [int][char]$content[0] -eq 0xFEFF) {
        $content = $content.Substring(1)
    }
    [System.IO.File]::WriteAllText($Destination, $content, (New-Object System.Text.UTF8Encoding($false)))
}

function Get-WorkflowAdapterTemplateVars {
    param([string]$AdapterName)

    switch ($AdapterName) {
        "claude-code" {
            return @{
                "__SKILL_ROOT__" = "~/.claude/skills"
                "__HOST_NAME__" = "Claude"
            }
        }
        "opencode" {
            return @{
                "__SKILL_ROOT__" = "~/.config/opencode/skills"
                "__HOST_NAME__" = "OpenCode"
            }
        }
        "copilot-cli" {
            # Current Copilot CLI builds inherit skills from ~/.agents/skills
            # on this machine. Copilot-specific overrides for slash entry
            # skills are overlaid there during `-For copilot` so inline
            # orchestration can differ from Claude/OpenCode without changing
            # the canonical global skill bundle for other hosts.
            return @{
                "__SKILL_ROOT__" = "~/.agents/skills"
                "__HOST_NAME__" = "Copilot CLI"
            }
        }
        default { return $null }
    }
}

function Get-WorkflowAdapterDestinations {
    param(
        [string]$AdapterName,
        [string]$Root,
        # Device-wide installs use ~/.config/opencode/ (the OpenCode global home).
        # Per-repo installs use <repo>/.opencode/ (the OpenCode project scope).
        # The OpenCode docs make this distinction explicit; mixing them up means
        # `/build` does not appear in a user's repo.
        [switch]$DeviceWideScope
    )

    switch ($AdapterName) {
        "claude-code" {
            return [pscustomobject]@{
                Label = "Claude Code"
                Commands = Join-Path $Root ".claude/commands"
                Agents = Join-Path $Root ".claude/agents"
            }
        }
        "opencode" {
            if ($DeviceWideScope) {
                return [pscustomobject]@{
                    Label = "OpenCode"
                    Commands = Join-Path $Root ".config/opencode/commands"
                    Agents = Join-Path $Root ".config/opencode/agents"
                }
            }
            return [pscustomobject]@{
                Label = "OpenCode"
                Commands = Join-Path $Root ".opencode/commands"
                Agents = Join-Path $Root ".opencode/agents"
            }
        }
        "copilot-cli" {
            # Copilot CLI surfaces (May 2026):
            #   - Custom agents:  ~/.copilot/agents/<name>.agent.md (user)
            #                     <repo>/.github/agents/<name>.agent.md (per-repo)
            #   - Hooks:          <repo>/.github/hooks/*.json (per-repo only;
            #                     no documented user-level hook path)
            #   - User-defined slash commands: NOT supported (issue #1113).
            # Without a slash-command surface, "Commands" returns null; install
            # writes only Agents (and Hooks via Install-CopilotHooks separately).
            if ($DeviceWideScope) {
                return [pscustomobject]@{
                    Label = "Copilot CLI"
                    Commands = $null
                    Agents = Join-Path $Root ".copilot/agents"
                    AgentSuffix = ".agent.md"
                }
            }
            return [pscustomobject]@{
                Label = "Copilot CLI"
                Commands = $null
                Agents = Join-Path $Root ".github/agents"
                Hooks = Join-Path $Root ".github/hooks"
                AgentSuffix = ".agent.md"
            }
        }
        default { return $null }
    }
}

function Install-RenderedMarkdownDirectory {
    param(
        [string]$SourceDir,
        [string]$DestDir,
        [hashtable]$Vars,
        [string]$Label,
        [string]$AssetKind,
        [switch]$SkipIfExists,
        # Override destination filename suffix. Default: keep source's `.md`.
        # Used for Copilot CLI agents which require `.agent.md` extension.
        [string]$OutputSuffix = ".md",
        # When set, enumerate destination *.md files NOT present in $SourceDir
        # and delete them. Closes the f714a3b drift class where the bundle
        # consolidated per-host commands into _shared/ but install left the
        # old per-host files orphaned at user destinations. Off by default
        # because it's only safe when $SourceDir is the SOLE legal source for
        # $DestDir (true for commands; not true for agents -- agents have a
        # specialist source as well, so that union must be considered).
        [switch]$PruneStale,
        # When -PruneStale and -DryRunPrune are both set, list pruning
        # candidates without deleting them. Overrides any deletion. Useful
        # before a destructive run.
        [switch]$DryRunPrune
    )

    if (-not (Test-Path $SourceDir)) { return }
    New-Item -ItemType Directory -Path $DestDir -Force | Out-Null

    # Compute the legal-file set from source BEFORE writing so prune logic
    # below can compare destination against it.
    $legalNames = @{}
    foreach ($f in (Get-ChildItem -Path $SourceDir -Filter "*.md" -File)) {
        $legalNames[$f.Name] = $true
    }

    $count = 0
    foreach ($f in (Get-ChildItem -Path $SourceDir -Filter "*.md" -File | Sort-Object Name)) {
        $outName = if ($OutputSuffix -ne ".md") {
            [System.IO.Path]::GetFileNameWithoutExtension($f.Name) + $OutputSuffix
        } else {
            $f.Name
        }
        $dst = Join-Path $DestDir $outName
        if ($SkipIfExists -and (Test-Path $dst) -and (-not $Force)) {
            Write-Host "  $Label ${AssetKind}: $outName already exists at $dst (skipped, pass -Force to overwrite)"
            continue
        }
        Render-Template -Source $f.FullName -Destination $dst -Vars $Vars
        $count++
    }
    if ($count -gt 0) {
        Write-Host "  $Label ${AssetKind}: $count installed at $DestDir"
    }

    if ($PruneStale) {
        $stale = @(Get-ChildItem -Path $DestDir -Filter "*.md" -File -ErrorAction SilentlyContinue |
                   Where-Object { -not $legalNames.ContainsKey($_.Name) })
        if ($stale.Count -eq 0) { return }
        if ($DryRunPrune) {
            Write-Host "  $Label ${AssetKind}: WOULD prune $($stale.Count) stale file(s) at $DestDir (re-run without -DryRunPrune to delete):"
            foreach ($s in $stale) { Write-Host "    - $($s.Name)" }
            return
        }
        # Backup each pruned file alongside the deletion (one-time stamp per run).
        $stamp = Get-Date -Format 'yyyyMMdd-HHmmss'
        $pruned = 0
        foreach ($s in $stale) {
            $bak = "$($s.FullName).pruned-$stamp"
            Move-Item -Force $s.FullName $bak
            $pruned++
        }
        if ($pruned -gt 0) {
            Write-Host "  $Label ${AssetKind}: pruned $pruned stale file(s) at $DestDir (backups: *.pruned-$stamp)"
        }
    }
}

function Install-WorkflowAdapterAssets {
    param(
        [string]$AdapterName,
        [string]$Root,
        [switch]$SkipExistingCommands,
        # Forward to Get-WorkflowAdapterDestinations: pick global home (~/.config/opencode/)
        # vs project-scope (<repo>/.opencode/) for OpenCode.
        [switch]$DeviceWideScope,
        # Prune stale .md files from the commands destination. SAFE because
        # _shared/workflow-commands/ is the only legal source for that dir.
        # NOT applied to the agents destination -- agents have a specialist
        # source on top of workflow-agents, so naively pruning would delete
        # the specialists. (Tier-C improvement: union-prune.)
        [switch]$PruneStale,
        [switch]$DryRunPrune
    )

    $vars = Get-WorkflowAdapterTemplateVars -AdapterName $AdapterName
    $destinations = Get-WorkflowAdapterDestinations -AdapterName $AdapterName -Root $Root -DeviceWideScope:$DeviceWideScope
    if (-not $vars -or -not $destinations) { return }

    if ($destinations.Commands) {
        Install-RenderedMarkdownDirectory `
            -SourceDir $SharedWorkflowCommandsRoot `
            -DestDir $destinations.Commands `
            -Vars $vars `
            -Label $destinations.Label `
            -AssetKind "commands" `
            -SkipIfExists:$SkipExistingCommands `
            -PruneStale:$PruneStale `
            -DryRunPrune:$DryRunPrune
    }

    # Workflow-agents directory is shared with specialist agents installed by
    # Install-DeviceWideAgents; cannot prune from this side without losing the
    # specialists. Plain write only.
    if ($destinations.Agents) {
        $agentSuffix = if ($destinations.PSObject.Properties['AgentSuffix']) { $destinations.AgentSuffix } else { ".md" }
        Install-RenderedMarkdownDirectory `
            -SourceDir $SharedWorkflowAgentsRoot `
            -DestDir $destinations.Agents `
            -Vars $vars `
            -Label $destinations.Label `
            -AssetKind "workflow agents" `
            -OutputSuffix $agentSuffix

        if ($AdapterName -eq "copilot-cli") {
            foreach ($agent in @("workflow-explorer", "workflow-reviewer", "workflow-skeptic", "workflow-ui-qa")) {
                $agentPath = Join-Path $destinations.Agents "$agent$agentSuffix"
                if (-not (Test-Path $agentPath)) { continue }
                $content = Get-Content -Raw -Encoding utf8 -LiteralPath $agentPath
                $content = [regex]::Replace($content, "(?m)^\s*permissionMode:\s*plan\s*\r?\n", "")
                [System.IO.File]::WriteAllText($agentPath, $content, (New-Object System.Text.UTF8Encoding($false)))
            }
        }
    }
}

function Install-Adapter {
    param([string]$Name, [string]$TargetRepo)
    $src = Join-Path $AdaptersRoot $Name
    if (-not (Test-Path $src)) {
        Write-Host "  Adapter '$Name' not found at $src -- skipping"
        return
    }
    Copy-Tree -Source $src -Destination $TargetRepo
    Install-WorkflowAdapterAssets -AdapterName $Name -Root $TargetRepo -PruneStale:$PruneStaleAssets -DryRunPrune:$DryRunPrune

    # Copilot CLI per-repo: install repo-scope hooks (.github/hooks/*.json).
    # Hooks are repo-scope only on Copilot per the official hooks reference;
    # there is no documented user-level hooks path.
    if ($Name -eq "copilot-cli") {
        $hookSrc = Join-Path $src ".github/hooks"
        $hookDst = Join-Path $TargetRepo ".github/hooks"
        if (Test-Path $hookSrc) {
            New-Item -ItemType Directory -Path $hookDst -Force | Out-Null
            foreach ($f in (Get-ChildItem -Path $hookSrc -Filter "*.json" -File)) {
                Copy-Item -Force $f.FullName (Join-Path $hookDst $f.Name)
            }
            Write-Host "  Installed Copilot CLI hooks into $hookDst"
        }

        $copilotBinSrc = Join-Path $src "bin"

        # Plant repo-local workflow shims under .github/copilot-bin so repo-scoped
        # Copilot agents can invoke the wrapper route without crossing into $HOME.
        # This avoids direct-agent permission denials on hosts that restrict shell
        # access outside the current repository.
        $copilotRepoBinDst = Join-Path $TargetRepo ".github/copilot-bin"
        if (Test-Path $copilotBinSrc) {
            New-Item -ItemType Directory -Path $copilotRepoBinDst -Force | Out-Null
            $repoScriptCount = 0
            foreach ($pattern in @('*.sh', '*.ps1')) {
                foreach ($s in (Get-ChildItem -Path $copilotBinSrc -Filter $pattern -File)) {
                    Copy-Item -Force $s.FullName (Join-Path $copilotRepoBinDst $s.Name)
                    $repoScriptCount++
                }
            }
            if ($repoScriptCount -gt 0) {
                Write-Host "  Copilot repo-local workflow scripts: $repoScriptCount installed at $copilotRepoBinDst"
            }
            $repoKitConfigPath = Join-Path $copilotRepoBinDst "kit-config.sh"
            $kitRootForward = $RepoRoot -replace '\\', '/'
            $kitConfigContent = "# Written by install.ps1 at $(Get-Date -Format 'yyyy-MM-dd') -- do not edit manually`nKIT_ROOT=`"$kitRootForward`"`n"
            [System.IO.File]::WriteAllText($repoKitConfigPath, $kitConfigContent, (New-Object System.Text.UTF8Encoding($false)))
            Write-Host "  Copilot repo-local kit-config.sh: $repoKitConfigPath (KIT_ROOT=$kitRootForward)"
        }

        # Ensure ~/.agents/bin/copilot/*.sh wrappers survive the global
        # Copy-Tree -ReplaceDestination that runs during every install
        # (because $InstallGlobal defaults to $true). Without this, a
        # per-repo adapter install that follows a device-wide copilot
        # install wipes the wrappers, because bundle/global/.agents does
        # not contain bin/copilot.
        $copilotBinDst = Join-Path $AgentsRoot "bin/copilot"
        if (Test-Path $copilotBinSrc) {
            New-Item -ItemType Directory -Path $copilotBinDst -Force | Out-Null
            $scriptCount = 0
            foreach ($pattern in @('*.sh', '*.ps1')) {
                foreach ($s in (Get-ChildItem -Path $copilotBinSrc -Filter $pattern -File)) {
                    Copy-Item -Force $s.FullName (Join-Path $copilotBinDst $s.Name)
                    $scriptCount++
                }
            }
            if ($scriptCount -gt 0) {
                Write-Host "  GitHub Copilot workflow scripts: $scriptCount installed at $copilotBinDst"
            }
            # Write kit-config.sh so kit-bootstrap.sh can find the kit root at runtime
            # without requiring KIT_ROOT to be set in the environment. The kit root is
            # the parent of the scripts/ directory where install.ps1 lives.
            $kitConfigPath = Join-Path $copilotBinDst "kit-config.sh"
            $kitRootForward = $RepoRoot -replace '\\', '/'
            $kitConfigContent = "# Written by install.ps1 at $(Get-Date -Format 'yyyy-MM-dd') -- do not edit manually`nKIT_ROOT=`"$kitRootForward`"`n"
            [System.IO.File]::WriteAllText($kitConfigPath, $kitConfigContent, (New-Object System.Text.UTF8Encoding($false)))
            Write-Host "  GitHub Copilot kit-config.sh: $kitConfigPath (KIT_ROOT=$kitRootForward)"
        }
    }

    Write-Host "  Installed '$Name' adapter into $TargetRepo"
}

function Resolve-AdapterTargets {
    param([string]$Spec)

    if (-not $Spec) { return @() }

    $resolved = [System.Collections.Generic.List[string]]::new()
    $requested = @($Spec -split '[,;]' | ForEach-Object { $_.Trim() } | Where-Object { $_ })

    foreach ($item in $requested) {
        if ($item -eq "all") {
            foreach ($adapter in @("claude-code", "codex-cli", "copilot-cli", "opencode", "kilocode", "generic")) {
                if (-not $resolved.Contains($adapter)) {
                    $resolved.Add($adapter)
                }
            }
            continue
        }

        $adapterName = switch ($item) {
            "claude"   { "claude-code" }
            "codex"    { "codex-cli" }
            "copilot"  { "copilot-cli" }
            "opencode" { "opencode" }
            "kilocode" { "kilocode" }
            "kilo"     { "kilocode" }
            default    { $item }
        }

        if (-not $resolved.Contains($adapterName)) {
            $resolved.Add($adapterName)
        }
    }

    return @($resolved)
}

if ($BootstrapHarness) {
    if (-not $TargetRepo) {
        $TargetRepo = (Get-Location).Path
    }
    $InstallRepoTemplate = $true
    if (-not $InstallAdapter) {
        $InstallAdapter = "claude,copilot,generic"
    }
    if (-not $For -and -not $DeviceWide -and -not $Auto) {
        $For = "claude,copilot,generic"
    }
}

# ── Upgrade mode: backup before overwriting ───────────────────────────────────
# Preserves any user customizations of skill files, memory files, etc., by
# moving the existing ~/.agents to ~/.agents.bak.<timestamp> before installing.
# User can hand-merge customizations from the backup after upgrade.
if ($Upgrade -and (Test-Path $AgentsRoot)) {
    $backup = "$AgentsRoot.bak.$(Get-Date -Format 'yyyyMMdd-HHmmss')"
    Write-Host "Upgrade mode: backing up $AgentsRoot -> $backup"
    Move-Item -Force $AgentsRoot $backup
    Write-Host "  After upgrade, hand-merge any customized files from the backup."
    Write-Host ""
}

# ── Global install ─────────────────────────────────────────────────────────────
# Everything kit-related lives under ~/.agents/. Codex CLI users who want their
# own ~/.codex/ config can set it up separately -- it's not the kit's concern.
if ($InstallGlobal) {
    # Preserve user-mutable runtime state across the Copy-Tree -ReplaceDestination
    # wipe. The bundle does NOT ship these subpaths, so they are 100% user-owned
    # and a non-destructive install must keep them intact:
    #   - session-state/            per-session handoffs.md, plan.md, run-packet.json
    #   - context/handoffs.md       cross-session handoff log
    #   - context/reflections.md    accumulated workflow reflections
    #   - inspiration/              user-fetched design references (bulk-fetch-inspiration.ps1)
    #   - skills/*/memory.md        accumulated cross-repo workflow patterns
    # Snapshot each into a temp location, run the wipe, then restore. User state
    # wins on conflict: if the bundle started shipping any of these (it does not
    # today), the user's copy is kept.
    $preserveRelativePaths = @(
        'session-state',
        'context/handoffs.md',
        'context/reflections.md',
        'inspiration'
    )
    $preserveSnapshots = @{}
    foreach ($rel in $preserveRelativePaths) {
        $abs = Join-Path $AgentsRoot $rel
        if (Test-Path $abs) {
            $tmp = Join-Path ([System.IO.Path]::GetTempPath()) ("agentic-kit-preserve-" + [Guid]::NewGuid().ToString('N'))
            Move-Item -Force $abs $tmp
            $preserveSnapshots[$rel] = $tmp
        }
    }

    # Skill memory files live inside bundle-managed skill directories, so snapshot
    # them separately before the global tree is replaced. Restore only for skills
    # that still ship in the new bundle; this preserves learned patterns without
    # resurrecting removed skills.
    $preserveSkillMemory = @{}
    $skillMemorySnapshotRoot = Join-Path ([System.IO.Path]::GetTempPath()) ("agentic-kit-skill-memory-" + [Guid]::NewGuid().ToString('N'))
    $skillsRootExisting = Join-Path $AgentsRoot 'skills'
    if (Test-Path $skillsRootExisting) {
        foreach ($skillDir in (Get-ChildItem -Path $skillsRootExisting -Directory -ErrorAction SilentlyContinue)) {
            $memoryPath = Join-Path $skillDir.FullName 'memory.md'
            if (-not (Test-Path $memoryPath)) { continue }
            $snapshotDir = Join-Path $skillMemorySnapshotRoot $skillDir.Name
            New-Item -ItemType Directory -Path $snapshotDir -Force | Out-Null
            $snapshotPath = Join-Path $snapshotDir 'memory.md'
            Copy-Item -Force $memoryPath $snapshotPath
            $preserveSkillMemory[$skillDir.Name] = $snapshotPath
        }
    }

    Copy-Tree -Source (Join-Path $BundleGlobal ".agents") -Destination $AgentsRoot -ReplaceDestination

    # Restore preserved subpaths.
    foreach ($rel in $preserveSnapshots.Keys) {
        $tmp = $preserveSnapshots[$rel]
        $abs = Join-Path $AgentsRoot $rel
        New-Item -ItemType Directory -Path (Split-Path -Parent $abs) -Force | Out-Null
        if (Test-Path $abs) {
            # Bundle re-introduced this path during this install. Keep the user's copy;
            # archive the bundle's version alongside for inspection (rare; future-proof).
            $archived = "$abs.bundle-shipped-$(Get-Date -Format 'yyyyMMdd-HHmmss')"
            Move-Item -Force $abs $archived
            Write-Host "  Preserved user state at $rel ; bundle copy archived to $archived"
        }
        Move-Item -Force $tmp $abs
    }
    if ($preserveSnapshots.Count -gt 0) {
        Write-Host "  Preserved $($preserveSnapshots.Count) user-mutable runtime path(s) across install."
    }

    $restoredSkillMemoryCount = 0
    foreach ($skillName in $preserveSkillMemory.Keys) {
        $destSkillDir = Join-Path $AgentsRoot "skills/$skillName"
        if (-not (Test-Path $destSkillDir)) {
            Write-Host "  Skipped preserved skill memory for '$skillName' -- skill no longer ships in this bundle."
            continue
        }
        Copy-Item -Force $preserveSkillMemory[$skillName] (Join-Path $destSkillDir 'memory.md')
        $restoredSkillMemoryCount++
    }
    if ($restoredSkillMemoryCount -gt 0) {
        Write-Host "  Preserved $restoredSkillMemoryCount global skill memory file(s) across install."
    }
    if (Test-Path $skillMemorySnapshotRoot) {
        Remove-Item -Recurse -Force $skillMemorySnapshotRoot -ErrorAction SilentlyContinue
    }

    # Render skill-memory-index.json from template with absolute paths
    $tmpl = Join-Path $AgentsRoot "context/skill-memory-index.json.tmpl"
    $out  = Join-Path $AgentsRoot "context/skill-memory-index.json"
    if (Test-Path $tmpl) {
        $agentsRootAbs = (Resolve-Path $AgentsRoot).Path -replace '\\', '/'
        Render-Template -Source $tmpl -Destination $out -Vars @{
            "__AGENTS_ROOT__" = $agentsRootAbs
        }
        Remove-Item -Force $tmpl
        Write-Host "  Rendered skill-memory-index.json with AGENTS_ROOT=$agentsRootAbs"
    }

    # Stage Copilot CLI's MODEL-ROUTING.md under ~/.agents/copilot/ so the
    # standalone install-copilot-kit.ps1 entry point can find it without a
    # hardcoded repo path. (Pre-fix the script hardcoded $HOME/Downloads/<maintainer-repo-name>.)
    $copilotModelRoutingSrc = Join-Path $AdaptersRoot 'copilot-cli/MODEL-ROUTING.md'
    if (Test-Path $copilotModelRoutingSrc) {
        $copilotStageDir = Join-Path $AgentsRoot 'copilot'
        New-Item -ItemType Directory -Path $copilotStageDir -Force | Out-Null
        Copy-Item -Force $copilotModelRoutingSrc (Join-Path $copilotStageDir 'MODEL-ROUTING.md')
    }

    Write-Host "Installed global assets into $HomeRoot"
}

# ── Repo template install ─────────────────────────────────────────────────────
if ($TargetRepo -and $InstallRepoTemplate) {
    Copy-Tree -Source $BundleRepo -Destination $TargetRepo
    Write-Host "Installed repo template into $TargetRepo"
}

# ── Adapter install ───────────────────────────────────────────────────────────
if ($TargetRepo -and $InstallAdapter) {
    $adapters = Resolve-AdapterTargets -Spec $InstallAdapter

    foreach ($resolved in $adapters) {
        Install-Adapter -Name $resolved -TargetRepo $TargetRepo
    }
}

if (-not $TargetRepo -and -not $DeviceWide -and -not $For -and -not $Auto -and -not $BootstrapHarness) {
    Write-Host ""
    Write-Host "Global assets installed at $AgentsRoot."
    Write-Host ""
    Write-Host "To wire the kit into a CLI on this device, re-run with -For or -Auto:"
    Write-Host "  pwsh ./install.ps1 -For claude                     # one CLI"
    Write-Host "  pwsh ./install.ps1 -For 'claude,opencode'           # multiple"
    Write-Host "  pwsh ./install.ps1 -For all                        # all five"
    Write-Host "  pwsh ./install.ps1 -Auto                            # detect CLIs on PATH"
    Write-Host ""
    Write-Host "Or bootstrap a repo end-to-end:"
    Write-Host "  pwsh ./install.ps1 -BootstrapHarness -TargetRepo <path>"
}

if ($CleanReinstall) { $PruneStaleAssets = $true }

# Helper: wipe kit-managed dest directories before reinstall. Used by
# -CleanReinstall to clear orphans from older kit versions (skills/agents/
# commands that the bundle no longer ships). User-mutable runtime state in
# ~/.agents/{session-state,context/handoffs.md,context/reflections.md,inspiration}
# is preserved by the P3 snapshot/restore around the global Copy-Tree -- not
# by this helper, which only operates on per-host install dirs.
function Clean-HostInstallDirs {
    param(
        [string]$Label,
        [string[]]$Paths
    )
    foreach ($p in $Paths) {
        if (Test-Path $p) {
            Remove-Item -Recurse -Force $p
            Write-Host "  $Label clean-reinstall: wiped $p"
        }
    }
}

# ── Resolve which CLIs to install for (-For, -Auto, -DeviceWide all converge) ─
# -For is the new canonical flag. -DeviceWide is kept as an alias.
# -Auto detects which CLIs are on PATH and installs for those.
$resolvedFor = ""
if ($For)        { $resolvedFor = $For }
elseif ($DeviceWide) { $resolvedFor = $DeviceWide }
elseif ($Auto) {
    $detected = @()
    if (Get-Command claude -ErrorAction SilentlyContinue)   { $detected += "claude" }
    if (Get-Command opencode -ErrorAction SilentlyContinue) { $detected += "opencode" }
    if (Get-Command codex -ErrorAction SilentlyContinue)    { $detected += "codex" }
    if (Get-Command gh -ErrorAction SilentlyContinue) {
        # Copilot CLI is `gh copilot ...`. If gh is present, offer copilot adapter.
        $detected += "copilot"
    }
    if ($detected.Count -gt 0) {
        $resolvedFor = $detected -join ","
        Write-Host ""
        Write-Host "Auto-detected CLIs on PATH: $($detected -join ', ')"
        Write-Host "Installing for those. Pass -For <list> to override."
    } else {
        Write-Host ""
        Write-Host "Auto-detect found no supported CLI on PATH."
        Write-Host "Pass -For <claude|codex|copilot|opencode|kilocode|all> explicitly."
    }
}

# ── Device-wide install ──────────────────────────────────────────────────────
# Industry-standard pattern (matches autoresearch / cc-sdd / superpowers /
# agentic-stack): drop self-contained skills/commands/agents at each CLI's
# native auto-discovery dirs. Do NOT modify user-owned auto-loaded rules
# files (CLAUDE.md / prompt.md / AGENTS.md) -- those are the user's surface,
# not the kit's. Skills with strong `description:` frontmatter self-route via
# the host CLI's skill loader.
if ($resolvedFor) {
    $DeviceWide = $resolvedFor
    $sharedBody = Join-Path $AdaptersRoot "_shared/AGENT-INSTRUCTIONS.md"
    if (-not (Test-Path $sharedBody)) {
        Write-Error "Shared instructions not found at $sharedBody"
        exit 1
    }
    $kitContent = Get-Content $sharedBody -Raw -Encoding UTF8

    # Writes the kit body as a STANDALONE reference doc at ~/.claude/agentic-kit.md
    # (or the equivalent for other CLIs). For long-form reference; not auto-loaded.
    function Install-DeviceWideRulesDoc {
        param(
            [string]$DocPath,    # where to write the standalone reference
            [string]$Label
        )
        New-Item -ItemType Directory -Path (Split-Path -Parent $DocPath) -Force | Out-Null
        Set-Content -Path $DocPath -Value $kitContent -Encoding UTF8
        Write-Host "  $Label rules doc: $DocPath (standalone long-form reference)"
    }

    # Appends a MINIMAL (~12 line) always-on rules block to the user's
    # auto-loaded rules file (CLAUDE.md / prompt.md / AGENTS.md). Only the
    # truly global rules go here -- workflow-specific content stays in skills
    # at native auto-discovery dirs. Idempotent: skips if marker already
    # present. Backs up before appending.
    # Strips every known kit-block marker pair from a given content string.
    # Handles current (:begin/:end) and legacy (:include / /:include) variants
    # plus orphans where one marker was hand-deleted. Returns cleaned content.
    function Strip-AllKitBlocks {
        param([string]$Content)
        if (-not $Content) { return $Content }
        $patterns = @(
            "(?s)<!-- agentic-kit:begin -->.*?<!-- agentic-kit:end -->\s*",
            "(?s)<!-- agentic-kit:include -->.*?<!-- /agentic-kit:include -->\s*",
            "(?s)<!-- agentic-kit:include -->.*?<!-- agentic-kit:end -->\s*",
            "(?s)<!-- agentic-kit:begin -->.*?<!-- /agentic-kit:include -->\s*"
        )
        $cleaned = $Content
        foreach ($p in $patterns) {
            $cleaned = [regex]::Replace($cleaned, $p, '')
        }
        # Collapse a duplicated canonical heading that may have leaked outside
        # all marker pairs (e.g., user manually merged a duplicate at some point).
        $heading = '# CASPAR BANNINK AGENTIC CODING KIT — GLOBAL RULES'
        $hits = [regex]::Matches($cleaned, [regex]::Escape($heading))
        if ($hits.Count -gt 1) {
            $cleaned = $cleaned.Substring(0, $hits[0].Index).TrimEnd() + "`r`n"
        }
        return $cleaned.TrimEnd() + "`r`n"
    }

    function Install-DeviceWideAlwaysOnRules {
        param(
            [string]$ExistingPath,    # user's auto-loaded rules file
            [string]$LongFormPath,    # path to standalone agentic-kit.md (referenced from block)
            [string]$Label
        )
        # Canonical marker pair used by ALL kit writers (install.ps1, sync-all-hosts.ps1,
        # install-{opencode,codex,copilot,gemini}-kit.ps1). Legacy `:include` pairs are
        # stripped via Strip-AllKitBlocks below for backward compat.
        $marker    = "<!-- agentic-kit:begin -->"
        $endMarker = "<!-- agentic-kit:end -->"
        $block = @"

$marker
## Caspar Bannink Agentic Coding Kit (augmentation rules)

This device has the kit installed. Skills, sub-agents, and slash commands
are auto-discovered from your CLI's native dirs. The kit also installs
PreToolUse / PostToolUse hooks that enforce a small set of rules at the
**protocol layer** (cannot be skipped by the agent).

### Precedence: REPO WINS

- **Repo conventions take precedence** when they conflict with the kit's
  defaults. If your repo has its own pipeline (``hand_off.md``,
  ``agents/handoffs/``, ``memory/MEMORY.md``, project-scoped
  ``.claude/agents/``, etc.), follow it. The kit augments; it does not
  replace.
- The kit's runtime artifacts default to ``<repo>/.kit/session-state/`` inside a
  bootstrapped repo (or ``AGENTS_SESSION_ROOT`` if you override it; otherwise
  ``~/.agents/session-state/`` remains the global fallback). They are written
  ALONGSIDE your repo's pipeline as cross-repo audit / memory continuity -- not
  as the source of truth. Your repo's files remain canonical.
- Skills + sub-agents + slash commands + hooks are the kit's contribution.
  Use them where they fit; ignore them where the repo has better.

### Workflow source of truth

- The global workflow skills are the canonical workflow contract.
- Adapter command files are thin wrappers; they should not redefine workflow behavior.
- If a host supports subagents, non-trivial ``/build`` should delegate instead
  of keeping implementation inline in the main session.
- If ``AGENTS_SESSION_ROOT`` is set, session-private artifacts are written
  there; otherwise the default is ``.kit/session-state/`` inside a bootstrapped
  repo and ``~/.agents/session-state/`` elsewhere.

### What the kit enforces (via hooks, not prose)

These rules fire deterministically because they're protocol-layer hooks
(``settings.json`` / OpenCode plugin events). They cannot be skipped by
the agent under conversational pressure -- they fire at every tool call:

- **Dangerous filesystem ops blocked**: ``rm -rf /``, ``sudo rm``,
  ``chmod 777``, redirects to ``/etc/`` -- bash dispatcher refuses.
- **Force-push to main/master blocked** without explicit confirmation.
- **Git commit requires verification evidence**: bash dispatcher checks
  the session's ``state.json`` for ``verification_evidence`` gate. If
  unmarked, commit is blocked with a clear message.
- **Test commands auto-mark verification**: when you run ``npm test`` /
  ``pytest`` / etc. and exit code is 0, the gate marks itself. No agent
  thought required.
- **First-edit-per-file reminder**: surfaces a recommendation to run
  ``wiki-resolver.ps1`` before editing source code for the first time
  this session. (Soft warn, does not block.)
- **Wiki-existence check**: source-code edits in a repo without
  ``.wiki/index.md`` are blocked with a ``/wiki-init`` suggestion.
- **Task tool auto-records sub-agents**: PreToolUse on Task auto-runs
  ``state-gate.ps1 -AddAgent`` and ``workflow-evidence.ps1 -AddAgent``.
  The orchestrator never has to think about bookkeeping.

All hook enforcement respects ``KIT_DISABLED_HOOKS`` env var
(comma-separated rule names) for opt-out per-rule, e.g.:
``KIT_DISABLED_HOOKS=wiki-existence,git-commit-verify``

### Soft conventions (not enforced; suggested when applicable)

These are descriptive, not enforced. Skip them when the repo has its own
better answer:

- ``.wiki/features.md`` documents user-visible capabilities -- useful for
  cross-session memory. Run ``/wiki-init`` to bootstrap.
- ``.kit/context/memory.md`` for durable repo facts the kit's tools can
  read. Run ``/kit-init`` to bootstrap.
- Skills auto-discover via the host CLI -- type ``/<skill>`` or let the
  CLI surface them by description matching.

### Opt-out

If a repo genuinely needs to bypass kit hooks (rare), add
``<!-- agentic-kit:disable-lifecycle -->`` to its ``CLAUDE.md`` /
``AGENTS.md`` -- the SessionStart hook will read this and short-circuit
the lifecycle scripts. Hook-layer rules still apply but become no-ops
when their gates aren't initialized.

For per-rule opt-out: set ``KIT_DISABLED_HOOKS`` env var. Each hook's
script-level documentation lists its rule names.

### Long-form reference

Full command semantics, scope/tier classification, swarm gating, memory
routing, frontend visual gate, session lifecycle details:
``$LongFormPath``
$endMarker
"@

        if (Test-Path $ExistingPath) {
            $existing = Get-Content $ExistingPath -Raw -Encoding UTF8
            $backup = "$ExistingPath.before-agentic-kit-$(Get-Date -Format 'yyyyMMdd-HHmmss')"
            Copy-Item -Force $ExistingPath $backup

            # Always strip ALL prior kit blocks (any marker variant, any number of
            # duplicates) BEFORE writing. This is what fixes the marker-schism bug
            # where install.ps1 used `:include` while sync-all-hosts.ps1 used
            # `:begin/:end`, causing every re-run to append another duplicate.
            $stripped = Strip-AllKitBlocks $existing

            if ($RepairKitBlock) {
                # Repair mode: cleanup only, do not append a new block.
                Set-Content -Path $ExistingPath -Value $stripped -Encoding UTF8
                Write-Host "  $Label always-on rules: REPAIRED -- removed all kit blocks from $ExistingPath (backup: $backup). Re-run without -RepairKitBlock to install fresh."
                return
            }

            $updated = $stripped.TrimEnd() + "`r`n" + $block.TrimEnd() + "`r`n"
            Set-Content -Path $ExistingPath -Value $updated -Encoding UTF8
            $changed = if ($existing -ne $stripped) { "deduped + " } else { "" }
            Write-Host "  $Label always-on rules: ${changed}refreshed managed block in $ExistingPath (backup: $backup)"
        } else {
            if ($RepairKitBlock) {
                Write-Host "  $Label always-on rules: $ExistingPath does not exist; nothing to repair."
                return
            }
            New-Item -ItemType Directory -Path (Split-Path -Parent $ExistingPath) -Force | Out-Null
            Set-Content -Path $ExistingPath -Value $block.TrimStart() -Encoding UTF8
            Write-Host "  $Label always-on rules: created $ExistingPath"
        }
    }

    # Copilot CLI reads ~/.copilot/copilot-instructions.md directly, so the
    # kit should install that file as a kit-managed overwrite instead of
    # layering appended blocks from multiple generations of the kit.
    function Install-DeviceWideInlineInstructions {
        param(
            [string]$SourcePath,
            [string]$ExistingPath,
            [string]$Label
        )
        if (-not (Test-Path $SourcePath)) {
            Write-Host "  $Label inline rules: source not found at $SourcePath"
            return
        }

        if (Test-Path $ExistingPath) {
            $backup = "$ExistingPath.before-agentic-kit-$(Get-Date -Format 'yyyyMMdd-HHmmss')"
            Copy-Item -Force $ExistingPath $backup
            Write-Host "  $Label inline rules: replacing existing file (backup: $backup)"
        }
        New-Item -ItemType Directory -Path (Split-Path -Parent $ExistingPath) -Force | Out-Null
        $body = Get-Content $SourcePath -Raw -Encoding UTF8
        Set-Content -Path $ExistingPath -Value $body -Encoding UTF8
        Write-Host "  $Label inline rules: wrote $ExistingPath"
    }

    # Copies kit skills to a CLI's native auto-discovery skills dir.
    # Each kit skill at bundle/global/.agents/skills/<name>/SKILL.md (plus any
    # sibling files) lands at <dest>/<name>/SKILL.md. Auto-discovery picks
    # them up via the description: frontmatter.
    function Install-DeviceWideSkills {
        param(
            [string]$SourceRoot, # bundle/global/.agents/skills
            [string]$DestRoot,   # ~/.claude/skills or ~/.config/opencode/skills
            [string]$Label
        )
        if (-not (Test-Path $SourceRoot)) { return }
        New-Item -ItemType Directory -Path $DestRoot -Force | Out-Null
        $count = 0
        foreach ($dir in (Get-ChildItem -Path $SourceRoot -Directory)) {
            $skillFile = Join-Path $dir.FullName "SKILL.md"
            if (-not (Test-Path $skillFile)) { continue }
            $destDir = Join-Path $DestRoot $dir.Name
            New-Item -ItemType Directory -Path $destDir -Force | Out-Null
            Copy-Item -Force "$($dir.FullName)/*" $destDir -Recurse
            $count++
        }
        if ($count -gt 0) { Write-Host "  $Label skills: $count installed at $DestRoot" }
    }

    # Copy Copilot CLI hook configs (.github/hooks/*.json). Per docs, hooks
    # are repo-scope only -- there's no documented user-level hook directory.
    # SourceDir: bundle/adapters/copilot-cli/.github/hooks
    # DestDir:   <repo>/.github/hooks
    function Install-CopilotHooks {
        param(
            [string]$SourceDir,
            [string]$DestDir,
            [string]$Label
        )
        if (-not (Test-Path $SourceDir)) { return }
        New-Item -ItemType Directory -Path $DestDir -Force | Out-Null
        $count = 0
        foreach ($f in (Get-ChildItem -Path $SourceDir -Filter "*.json" -File)) {
            Copy-Item -Force $f.FullName (Join-Path $DestDir $f.Name)
            $count++
        }
        if ($count -gt 0) { Write-Host "  $Label hooks: $count installed at $DestDir" }
    }

    # OpenCode's frontmatter parser rejects Claude-format `tools: A, B, C` as
    # "expected object". OpenCode wants either no `tools:` field or its own
    # mapping format. This function reads each agent file, strips Claude-only
    # frontmatter keys (tools, permissionMode, maxTurns) before writing to the
    # OpenCode destination. Keeps name, description, mode, model.
    function Install-OpenCodeAgentsFromSource {
        param(
            [string]$SourceDir,
            [string]$DestDir,
            [string]$Label
        )
        if (-not (Test-Path $SourceDir)) { return }
        New-Item -ItemType Directory -Path $DestDir -Force | Out-Null
        $count = 0
        $utf8NoBom = New-Object System.Text.UTF8Encoding($false)
        foreach ($f in (Get-ChildItem -Path $SourceDir -Filter "*.md" -File)) {
            $raw = Get-Content $f.FullName -Raw -Encoding UTF8
            # Strip BOM if present
            if ($raw.Length -gt 0 -and [int][char]$raw[0] -eq 0xFEFF) { $raw = $raw.Substring(1) }
            if ($raw -notmatch '(?ms)^---\r?\n(.*?)\r?\n---\r?\n(.*)$') { continue }
            $fm = $matches[1]
            $body = $matches[2]
            # Drop Claude-only keys that OpenCode rejects (tools list,
            # permissionMode, maxTurns, disallowedTools).
            $newFmLines = @()
            foreach ($line in ($fm -split "`r?`n")) {
                if ($line -match '^\s*(tools|permissionMode|maxTurns|disallowedTools)\s*:') { continue }
                $newFmLines += $line
            }
            $newFm = ($newFmLines -join "`r`n").TrimEnd()
            $out = "---`r`n$newFm`r`n---`r`n$body"
            $dst = Join-Path $DestDir $f.Name
            [System.IO.File]::WriteAllText($dst, $out, $utf8NoBom)
            $count++
        }
        if ($count -gt 0) { Write-Host "  $Label agents: $count installed at $DestDir (OpenCode-sanitized: tools/permissionMode/maxTurns stripped)" }
    }

    # Convert Claude/OpenCode-format agent .md files into Copilot's `.agent.md`
    # format with minimal documented frontmatter (name + description). Strips
    # Claude-only keys (model: sonnet, permissionMode, maxTurns, tools, mode)
    # which are not in Copilot's documented schema.
    #
    # Empirically observed: Copilot CLI's frontmatter parser silently rejects
    # agent files whose description contains Unicode chars, single-quoted
    # YAML lists in unquoted values, or descriptions over ~300 chars. This
    # function sanitises descriptions to the documented-supported subset:
    # ASCII-only, double-quoted, max 300 chars.
    function Install-CopilotAgentsFromClaudeSource {
        param(
            [string]$SourceDir,
            [string]$DestDir,
            [string]$Label
        )
        if (-not (Test-Path $SourceDir)) { return }
        New-Item -ItemType Directory -Path $DestDir -Force | Out-Null
        # Template variables for Copilot CLI adapter (resolve __HOST_NAME__ and
        # __SKILL_ROOT__ so installed agents never contain unresolved placeholders).
        $copilotTemplateVars = Get-WorkflowAdapterTemplateVars -AdapterName "copilot-cli"
        $count = 0
        foreach ($f in (Get-ChildItem -Path $SourceDir -Filter "*.md" -File)) {
            $raw = Get-Content $f.FullName -Raw -Encoding UTF8
            # Apply template substitution before parsing frontmatter so that
            # __HOST_NAME__ is replaced regardless of where it appears in the file.
            if ($copilotTemplateVars) {
                foreach ($k in $copilotTemplateVars.Keys) {
                    $raw = $raw.Replace($k, $copilotTemplateVars[$k])
                }
            }
            if ($raw -notmatch '(?s)^---\r?\n(.*?)\r?\n---\r?\n(.*)$') { continue }
            $fm = $matches[1]
            $body = $matches[2]
            $name = ''
            $desc = ''
            foreach ($line in ($fm -split "`r?`n")) {
                if ($line -match '^\s*name\s*:\s*(.+?)\s*$')        { $name = $matches[1].Trim('"').Trim("'") }
                elseif ($line -match '^\s*description\s*:\s*(.+?)\s*$') { $desc = $matches[1].Trim('"').Trim("'") }
            }
            if (-not $name) { $name = [System.IO.Path]::GetFileNameWithoutExtension($f.Name) }

            # Sanitise description for Copilot's strict parser:
            #   1. Replace common Unicode (em-dash, en-dash, smart quotes, arrows) with ASCII.
            #   2. Strip any remaining non-ASCII chars.
            #   3. Cap at 300 chars (observed Copilot parser limit).
            #   4. Remove embedded double quotes (would break the YAML wrapping).
            if ($desc) {
                $desc = $desc -replace [char]0x2014, '-'   # em-dash
                $desc = $desc -replace [char]0x2013, '-'   # en-dash
                $desc = $desc -replace [char]0x2192, '->'  # right arrow
                $desc = $desc -replace [char]0x2190, '<-'  # left arrow
                $desc = $desc -replace [char]0x2018, "'"   # left single quote
                $desc = $desc -replace [char]0x2019, "'"   # right single quote
                $desc = $desc -replace [char]0x201C, '"'   # left double quote
                $desc = $desc -replace [char]0x201D, '"'   # right double quote
                $desc = $desc -replace [char]0x2026, '...' # horizontal ellipsis
                $desc = $desc -replace '[^\x20-\x7E]', ''  # strip remaining non-ASCII
                $desc = $desc -replace '"', "'"            # internal double quotes -> single
                if ($desc.Length -gt 300) { $desc = $desc.Substring(0, 297) + '...' }
            }

            $newFm = "---`r`nname: $name"
            if ($desc) { $newFm += "`r`ndescription: ""$desc""" }
            $newFm += "`r`n---`r`n"
            # Compute output filename. If source already ends in `.agent.md` (i.e., it's
            # already a Copilot-format file from bundle/adapters/copilot-cli/.github/agents/),
            # preserve the name. Otherwise (Claude-source `.md`), append `.agent.md`.
            $base = [System.IO.Path]::GetFileNameWithoutExtension($f.Name)
            if ($base.EndsWith('.agent')) {
                $outName = $f.Name  # already has .agent.md
            } else {
                $outName = $base + '.agent.md'
            }
            $dst = Join-Path $DestDir $outName
            # UTF-8 NO BOM. Copilot CLI's agent loader rejects files starting with BOM
            # the same way Claude Code does. Set-Content -Encoding UTF8 in PS 5.1 adds BOM.
            [System.IO.File]::WriteAllText($dst, ($newFm + $body), (New-Object System.Text.UTF8Encoding($false)))
            $count++
        }
        if ($count -gt 0) { Write-Host "  $Label agents: $count installed at $DestDir (.agent.md format, minimal frontmatter, template vars resolved)" }
    }

    # Copies bundled agent definition files to a CLI's native auto-mount agents dir.
    function Install-DeviceWideAgents {
        param(
            [string]$SourceDir,  # bundle/adapters/<cli>/.claude/agents or equivalent
            [string]$DestDir,    # ~/.claude/agents or ~/.config/opencode/agents
            [string]$Label
        )
        if (-not (Test-Path $SourceDir)) { return }
        New-Item -ItemType Directory -Path $DestDir -Force | Out-Null
        $count = 0
        foreach ($f in (Get-ChildItem -Path $SourceDir -Filter "*.md" -File)) {
            $dst = Join-Path $DestDir $f.Name
            Copy-Item -Force $f.FullName $dst
            $count++
        }
        if ($count -gt 0) { Write-Host "  $Label agents: $count installed at $DestDir" }
    }

    function Install-DeviceWideCompanion {
        param(
            [string]$CompanionPath,    # where to write the kit body
            [string]$ExistingPath,     # the user's existing CLI config file (may not exist)
            [string]$Label             # human label for output
        )
        # Write the companion file (always overwrite -- it's the kit's content)
        New-Item -ItemType Directory -Path (Split-Path -Parent $CompanionPath) -Force | Out-Null
        Set-Content -Path $CompanionPath -Value $kitContent -Encoding UTF8
        Write-Host "  $Label companion: $CompanionPath"

        # NOTE: Install-DeviceWideCompanion is currently DEAD CODE -- not invoked
        # from the dispatch switch below. Kept for reference; flagged for removal
        # in TIER-C-TODO.md. Markers unified to :begin/:end for consistency with
        # the live writers (Install-DeviceWideAlwaysOnRules, sync-all-hosts.ps1).
        $marker    = "<!-- agentic-kit:begin -->"
        $endMarker = "<!-- agentic-kit:end -->"
        $includeBlock = @"

$marker
# Caspar Bannink Agentic Coding Kit -- Inline Rules

The kit is installed at ``~/.agents/``. These rules apply to EVERY session in
EVERY repo on this device. The full reference is at ``$CompanionPath`` --
read it for long-form details.

## Workflow commands (slash-mounted; available in every repo)

- ``/plan`` -- clarify scope, map files, trace blast radius, stop for approval
- ``/build`` -- execute approved plan: implement -> review -> verify gates
- ``/review`` -- hierarchical review (surface -> interactions -> synthesis -> adversarial -> false-positive verifier)
- ``/analyze`` -- multi-angle research/synthesis
- ``/investigate`` -- hypothesis-driven root-cause debugging
- ``/refactor`` -- principle-driven restructuring with consequence tracing
- ``/redesign`` -- greenfield UI / multi-component visual rebuild (swarm-eligible)
- ``/security-review`` -- adversarial audit by attack class (swarm-eligible)

## 4-axis classification (the harness picks; do not override casually)

The kit's classifiers decide behavior. Run them before any non-trivial work:

- **Scope** (``pwsh ~/.agents/tools/scope-classifier.ps1``): ISOLATED / SHARED / CRITICAL
- **Tier** (``pwsh ~/.agents/tools/pre-session.ps1 -Mode <build|review|...> -Task "<short>"``): INLINE / TARGETED / FULL / SWARM
- **Mode** (``pwsh ~/.agents/tools/swarm-classifier.ps1 -Task "<short>"``): sequential / swarm-review / swarm-fanout
- **Memory** (4 buckets, see below)

Override scope **upward only** (never downward) and only with concrete evidence.

## Swarm gating (do not fan-out without all three)

Swarms only fire when ALL hold:
1. Verb is parallel-safe (audit, explore, redesign, port, security-review, brainstorm, bulk-migrate)
2. Scope is fan-out-able (ISOLATED + >=4 files OR >=8 files with parallel-safe verb; CRITICAL never swarms)
3. User opted in (``$env:AGENTS_SWARM = "1"`` OR task contains "swarm" OR ``/redesign`` / ``/security-review`` invoked)

If only condition 1 holds: ``swarm-review`` (sequential implementer + parallel reviewers).
Default: sequential.

## Frontend visual gate (auto-fires in /build when UI changes)

When ``pwsh ~/.agents/tools/frontend-detector.ps1`` returns ``visual_loop_recommended=true``:
1. ``dev-server-runner.ps1`` auto-starts the dev server
2. ``playwright-navigator`` discovers route+auth+selectors for any unmapped screen
3. ``playwright-runner.ps1`` captures before/after screenshots
4. ``ux-driver`` runs first (structure: hierarchy/flow/density/a11y) -- BLOCKS if ``structure_ok=false``
5. ``ui-driver`` runs only after UX passes (visuals: typography/color/spacing/slop)
6. ``visual-diff.ps1`` confirms changes, no regressions
7. ``ux-driver`` and ``ui-driver`` read ``~/.agents/context/design-references.md`` and the local cache at ``~/.agents/inspiration/`` (populated by ``bulk-fetch-inspiration.ps1``)

## Memory routing (4 buckets, explicit rules)

| Bucket | Target | Use when |
|---|---|---|
| REPO-FACT | ``.kit/context/memory.md`` | Durable repo architecture, schema, verified commands |
| REPO-SPECIALIST | ``.kit/context/agent-memory/{role}.md`` | Repo-local guidance for one specialist role only |
| SKILL-PATTERN | ``~/.agents/skills/{skill}/memory.md`` | Cross-repo workflow pattern with recurring evidence |
| SESSION-ONLY | ``${AGENTS_SESSION_ROOT}/{id}/handoffs.md`` | Task progress, scratch, session-private notes |

Specialist memory is **lazy-loaded via**:
``pwsh ~/.agents/tools/specialist-memory-resolver.ps1 -SessionId <id> -Role <role> -RepoRoot <repo>``
If ``found=true``, embed its ``prompt_block`` directly in the spawned subagent prompt.
**Never** auto-load the directory at session start.

## Wiki convention (mandatory)

``.wiki/features.md`` is the SST for user-visible capabilities. If the change adds or
modifies a CLI command, API endpoint, UI page, evaluation mode, adapter, or validator:
update ``.wiki/features.md`` AND ``.wiki/.features``. Surgical edits only -- do not
rewrite. Skip only for pure refactors, test-only, bug fixes restoring documented
behavior, or perf with no UX change.

## Verification gate (Iron Law)

NO COMPLETION CLAIMS WITHOUT FRESH VERIFICATION EVIDENCE. Run the test, read the
output, then claim. "Should work now" is never acceptable. Use:
- ``pwsh ~/.agents/tools/test-loop.ps1 -SessionId <id> -Command "<test cmd>"`` -- detects 3-same-signature failures = ``stuck``
- ``pwsh ~/.agents/tools/edit-with-lint.ps1 -Path <file> -Find <s> -Replace <s>`` -- atomic write + revert on syntax fail

## Session lifecycle (auto-fires on Claude Code + OpenCode)

- **pre-session.ps1** -- emits BRIEF block with scope/tier/swarm/reflections
- **state-gate.ps1** -- agent marks ``context_loaded`` -> ``implementation_done`` -> ``verification_evidence`` -> ``handoff_written``
- **post-session.ps1** -- gate check, auto-consolidate, compress-memory, harness-propose, reflect-trigger

Under Codex/Copilot/Kilo/generic: call these manually.

## Tool index (most-used)

- Classification: ``scope-classifier.ps1``, ``swarm-classifier.ps1``, ``frontend-detector.ps1``
- Lifecycle: ``pre-session.ps1``, ``post-session.ps1``, ``state-gate.ps1``
- Edit/test: ``edit-with-lint.ps1``, ``test-loop.ps1``
- Memory: ``specialist-memory-resolver.ps1``, ``auto-consolidate.ps1``, ``compress-memory.ps1``
- Self-improvement: ``harness-propose.ps1``, ``harness-review.ps1``, ``reflect-trigger.ps1``
- Frontend: ``dev-server-runner.ps1``, ``playwright-runner.ps1``, ``visual-diff.ps1``, ``design-fetcher.ps1``, ``bulk-fetch-inspiration.ps1``
- Evidence: ``workflow-evidence.ps1``, ``run-packet.ps1``

## Quick reference

For long-form details (full agent matrix, per-tier policy, edge cases):
``$CompanionPath``
$endMarker
"@

        if (Test-Path $ExistingPath) {
            $existing = Get-Content $ExistingPath -Raw -Encoding UTF8
            if ($existing -match [regex]::Escape($marker)) {
                Write-Host "  $Label include: already present (skipped)"
            } else {
                $backup = "$ExistingPath.before-agentic-kit-$(Get-Date -Format 'yyyyMMdd-HHmmss')"
                Copy-Item -Force $ExistingPath $backup
                Add-Content -Path $ExistingPath -Value $includeBlock -Encoding UTF8
                Write-Host "  $Label include: appended to $ExistingPath (backup: $backup)"
            }
        } else {
            New-Item -ItemType Directory -Path (Split-Path -Parent $ExistingPath) -Force | Out-Null
            Set-Content -Path $ExistingPath -Value $includeBlock.TrimStart() -Encoding UTF8
            Write-Host "  $Label include: created $ExistingPath"
        }
    }

    # `all` covers every CLI that has a meaningful device-wide install location,
    # plus the generic AGENTS.md for any tool that reads the canonical home file.
    # Kilo Code still needs a per-repo install because it reads
    # `.kilocode/rules/*.md` from the workspace.
    $targets = if ($DeviceWide -eq "all") {
        @("claude", "codex", "copilot", "opencode", "generic")
    } else {
        # Allow comma-separated lists too: "claude,opencode"
        @(($DeviceWide -split '[,;]' | ForEach-Object { $_.Trim() } | Where-Object { $_ }))
    }

    Write-Host ""
    Write-Host "Device-wide install ($($targets -join ', ')):"

    $kitSkillsRoot = Join-Path $BundleGlobal ".agents/skills"

    foreach ($t in $targets) {
        switch ($t) {
            "claude" {
                if ($CleanReinstall) {
                    Clean-HostInstallDirs -Label "Claude Code" -Paths @(
                        (Join-Path $HomeRoot ".claude/skills"),
                        (Join-Path $HomeRoot ".claude/agents"),
                        (Join-Path $HomeRoot ".claude/commands")
                    )
                }
                # Standalone reference doc (not auto-loaded; for browsing).
                Install-DeviceWideRulesDoc `
                    -DocPath (Join-Path $HomeRoot ".claude/agentic-kit.md") `
                    -Label   "Claude Code"

                # Minimal always-on rules block (wiki + Iron Law + commands)
                Install-DeviceWideAlwaysOnRules `
                    -ExistingPath  (Join-Path $HomeRoot ".claude/CLAUDE.md") `
                    -LongFormPath  (Join-Path $HomeRoot ".claude/agentic-kit.md") `
                    -Label         "Claude Code"

                Install-WorkflowAdapterAssets `
                    -AdapterName "claude-code" `
                    -Root $HomeRoot `
                    -SkipExistingCommands `
                    -PruneStale:$PruneStaleAssets `
                    -DryRunPrune:$DryRunPrune

                # Skills -- ~/.claude/skills/<name>/SKILL.md is auto-discovered
                # via the `description:` frontmatter. This is THE canonical
                # routing surface; no CLAUDE.md edit needed.
                Install-DeviceWideSkills `
                    -SourceRoot $kitSkillsRoot `
                    -DestRoot   (Join-Path $HomeRoot ".claude/skills") `
                    -Label      "Claude Code"

                # Host-specific reviewer / expert agents. Workflow transport
                # agents are rendered from shared templates above.
                Install-DeviceWideAgents `
                    -SourceDir (Join-Path $AdaptersRoot "claude-code/.claude/agents") `
                    -DestDir   (Join-Path $HomeRoot ".claude/agents") `
                    -Label     "Claude Code"

                # Wire SessionStart/End hooks via the merger (honor HomeRoot)
                $merger  = Join-Path $AgentsRoot "tools/merge-claude-settings.ps1"
                $snippet = Join-Path $AdaptersRoot "claude-code/.claude/settings.snippet.json"
                $settingsPath = Join-Path $HomeRoot ".claude/settings.json"
                if ((Test-Path $merger) -and (Test-Path $snippet)) {
                    Write-Host "  Claude Code hooks: wiring..."
                    $shell = if (Get-Command pwsh -ErrorAction SilentlyContinue) { "pwsh" } else { "powershell" }
                    & $shell -NoProfile -File $merger -SnippetPath $snippet -SettingsPath $settingsPath
                }
            }
            "codex" {
                # Codex CLI auto-loads ~/.codex/AGENTS.md AND ships
                # PreToolUse / PostToolUse hooks via ~/.codex/config.toml
                # (per developers.openai.com/codex/hooks). Same exit-code-2
                # contract as Claude Code; same hook scripts work unchanged.
                # Coverage gap (issue #20204): hooks fire for Bash,
                # apply_patch, MCP -- not list_dir / plan / web_search.
                #
                # NOTE: ~/.codex/ here is the REAL Codex CLI HOME dir, NOT
                # the kit's repo-local .kit/ tree. Do NOT confuse them.
                Install-DeviceWideRulesDoc `
                    -DocPath (Join-Path $HomeRoot ".codex/agentic-kit.md") `
                    -Label   "Codex CLI"

                Install-DeviceWideAlwaysOnRules `
                    -ExistingPath  (Join-Path $HomeRoot ".codex/AGENTS.md") `
                    -LongFormPath  (Join-Path $HomeRoot ".codex/agentic-kit.md") `
                    -Label         "Codex CLI"

                # Wire Codex hooks via the TOML merger
                $codexMerger = Join-Path $AgentsRoot "tools/merge-codex-config.ps1"
                $codexSnippet = Join-Path $AdaptersRoot "codex-cli/.codex/hooks.snippet.toml"
                $codexConfig = Join-Path $HomeRoot ".codex/config.toml"
                if ((Test-Path $codexMerger) -and (Test-Path $codexSnippet)) {
                    Write-Host "  Codex CLI hooks: wiring..."
                    $shell = if (Get-Command pwsh -ErrorAction SilentlyContinue) { "pwsh" } else { "powershell" }
                    & $shell -NoProfile -File $codexMerger -SnippetPath $codexSnippet -ConfigPath $codexConfig
                }
            }
            "opencode" {
                if ($CleanReinstall) {
                    Clean-HostInstallDirs -Label "OpenCode" -Paths @(
                        (Join-Path $HomeRoot ".config/opencode/skills"),
                        (Join-Path $HomeRoot ".config/opencode/agents"),
                        (Join-Path $HomeRoot ".config/opencode/commands"),
                        (Join-Path $HomeRoot ".config/opencode/plugins")
                    )
                }
                # Standalone reference doc.
                Install-DeviceWideRulesDoc `
                    -DocPath (Join-Path $HomeRoot ".config/opencode/agentic-kit.md") `
                    -Label   "OpenCode"

                # Orchestrator prompt in OpenCode's global AGENTS.md.
                # OpenCode auto-loads ~/.config/opencode/AGENTS.md from every
                # session. The orchestrator prompt (adaptive routing, agent
                # toolbox, scope tiers) must be there — not just in per-repo
                # installs — so every new session starts with orchestrator
                # identity even without a repo-level AGENTS.md.
                $ocAgentsPath = Join-Path $HomeRoot ".config/opencode/AGENTS.md"
                $orchestratorSource = Join-Path $AdaptersRoot "opencode/AGENTS.md"
                $orchestratorHeader = "# AGENTS.md -- OpenCode Orchestrator"
                if (Test-Path $ocAgentsPath) {
                    $currentContent = Get-Content $ocAgentsPath -Raw -Encoding UTF8
                    $headerPattern = [regex]::Escape($orchestratorHeader)
                    if ($currentContent -notmatch $headerPattern) {
                        $orchestratorContent = Get-Content $orchestratorSource -Raw -Encoding UTF8
                        $separator = "`r`n`r`n<!-- agentic-kit:begin -->`r`n"
                        $updated = $orchestratorContent.TrimEnd() + $separator + $currentContent
                        [System.IO.File]::WriteAllText($ocAgentsPath, $updated, (New-Object System.Text.UTF8Encoding($false)))
                        Write-Host "  OpenCode AGENTS.md: prepended orchestrator prompt"
                    } else { Write-Host "  OpenCode AGENTS.md: orchestrator prompt already present" }
                } else {
                    Copy-Item -Force $orchestratorSource $ocAgentsPath
                    Write-Host "  OpenCode AGENTS.md: created with orchestrator prompt"
                }
                # Always-on rules block is appended inside the orchestrator
                # content (via marker). Refresh it to ensure latest version.
                Install-DeviceWideAlwaysOnRules `
                    -ExistingPath  $ocAgentsPath `
                    -LongFormPath  (Join-Path $HomeRoot ".config/opencode/agentic-kit.md") `
                    -Label         "OpenCode"

                Install-WorkflowAdapterAssets `
                    -AdapterName "opencode" `
                    -Root $HomeRoot `
                    -SkipExistingCommands `
                    -DeviceWideScope `
                    -PruneStale:$PruneStaleAssets `
                    -DryRunPrune:$DryRunPrune

                # Skills -- ~/.config/opencode/skills/<name>/SKILL.md auto-discovers.
                Install-DeviceWideSkills `
                    -SourceRoot $kitSkillsRoot `
                    -DestRoot   (Join-Path $HomeRoot ".config/opencode/skills") `
                    -Label      "OpenCode"

                # Workflow-agents from _shared/ need OpenCode sanitization.
                # Install-WorkflowAdapterAssets rendered them via Render-Template
                # which preserved Claude format; rewrite through the sanitizer.
                # Install these FIRST so adapter-specific overrides can win below.
                Install-OpenCodeAgentsFromSource `
                    -SourceDir (Join-Path $AdaptersRoot "_shared/workflow-agents") `
                    -DestDir   (Join-Path $HomeRoot ".config/opencode/agents") `
                    -Label     "OpenCode workflow"

                # Host-specific reviewer / expert agents. Use the OpenCode-specific
                # sanitizer so Claude-format `tools:` / `permissionMode:` / `maxTurns:`
                # frontmatter keys (which OpenCode's loader rejects with "expected
                # object") get stripped before writing.
                # Install SECOND so adapter-specific files (with hardcoded host name,
                # no template variables) override the shared workflow-agent versions.
                Install-OpenCodeAgentsFromSource `
                    -SourceDir (Join-Path $AdaptersRoot "opencode/.opencode/agents") `
                    -DestDir   (Join-Path $HomeRoot ".config/opencode/agents") `
                    -Label     "OpenCode"

                # Lifecycle plugin
                $pluginSrc = Join-Path $AdaptersRoot "opencode/.opencode/plugins/agentic-kit.ts"
                $pluginDst = Join-Path $HomeRoot ".config/opencode/plugins/agentic-kit.ts"
                if (Test-Path $pluginSrc) {
                    New-Item -ItemType Directory -Path (Split-Path -Parent $pluginDst) -Force | Out-Null
                    Copy-Item -Force $pluginSrc $pluginDst
                    Write-Host "  OpenCode plugin: $pluginDst"
                }
            }
            "generic" {
                # No standard auto-discovery for generic CLIs (Aider, Cline,
                # Cursor each have their own conventions). Drop standalone
                # reference + the minimal always-on rules block in ~/AGENTS.md
                # (the canonical home file most "agentic" CLIs read).
                Install-DeviceWideRulesDoc `
                    -DocPath (Join-Path $HomeRoot ".agentic-kit/AGENTS.md") `
                    -Label   "Generic"

                Install-DeviceWideAlwaysOnRules `
                    -ExistingPath  (Join-Path $HomeRoot "AGENTS.md") `
                    -LongFormPath  (Join-Path $HomeRoot ".agentic-kit/AGENTS.md") `
                    -Label         "Generic"
            }
            "copilot" {
                if ($CleanReinstall) {
                    Clean-HostInstallDirs -Label "GitHub Copilot" -Paths @(
                        (Join-Path $HomeRoot ".copilot/agents")
                    )
                }
                Install-DeviceWideRulesDoc `
                    -DocPath (Join-Path $HomeRoot ".copilot/agentic-kit.md") `
                    -Label   "GitHub Copilot"

                Install-DeviceWideInlineInstructions `
                    -SourcePath  (Join-Path $AdaptersRoot "copilot-cli/.github/copilot-instructions.md") `
                    -ExistingPath (Join-Path $HomeRoot ".copilot/copilot-instructions.md") `
                    -Label       "GitHub Copilot"

                # Custom agents at user scope (~/.copilot/agents/<name>.agent.md).
                # Bundled agents are pre-converted under copilot-cli/.github/agents/.
                Install-CopilotAgentsFromClaudeSource `
                    -SourceDir (Join-Path $AdaptersRoot "copilot-cli/.github/agents") `
                    -DestDir   (Join-Path $HomeRoot ".copilot/agents") `
                    -Label     "GitHub Copilot"

                # Copilot CLI uses the global skills under ~/.agents/skills/
                # directly. The global skills now reference only leaf agents
                # that Copilot CLI can spawn (workflow-implementer,
                # workflow-explorer, etc.) — no orchestrator-subagent proxies.
                # Copilot-specific rules (progress output, inline execution,
                # leaf-agent-only) live in copilot-instructions.md.
                # No overrides needed.

                # Wrapper scripts remain the explicit compatibility / shell
                # entrypoints for users who prefer terminal commands or older
                # Copilot builds that do not expose inherited skills.
                $copilotBinSrc = Join-Path $AdaptersRoot "copilot-cli/bin"
                $copilotBinDst = Join-Path $AgentsRoot "bin/copilot"
                if (Test-Path $copilotBinSrc) {
                    New-Item -ItemType Directory -Path $copilotBinDst -Force | Out-Null
                    $scriptCount = 0
                    foreach ($pattern in @('*.sh', '*.ps1')) {
                        foreach ($s in (Get-ChildItem -Path $copilotBinSrc -Filter $pattern -File)) {
                            Copy-Item -Force $s.FullName (Join-Path $copilotBinDst $s.Name)
                            $scriptCount++
                        }
                    }
                    if ($scriptCount -gt 0) {
                        Write-Host "  GitHub Copilot workflow scripts: $scriptCount installed at $copilotBinDst"
                        Write-Host "    POSIX:   bash ~/.agents/bin/copilot/kit-build.sh '<request>'"
                        Write-Host "    Windows: pwsh ~/.agents/bin/copilot/kit-build.ps1 '<request>'"
                    }
                    # Write kit-config.sh so kit-bootstrap.sh can locate the kit repo root
                    # at runtime without requiring KIT_ROOT env var to be set manually.
                    $kitConfigPath = Join-Path $copilotBinDst "kit-config.sh"
                    $kitRootForward = $RepoRoot -replace '\\', '/'
                    $kitConfigContent = "# Written by install.ps1 at $(Get-Date -Format 'yyyy-MM-dd') -- do not edit manually`nKIT_ROOT=`"$kitRootForward`"`n"
                    [System.IO.File]::WriteAllText($kitConfigPath, $kitConfigContent, (New-Object System.Text.UTF8Encoding($false)))
                    Write-Host "  GitHub Copilot kit-config.sh: $kitConfigPath"
                }

                Write-Host "  GitHub Copilot CLI hooks are repo-scope only (.github/hooks/*.json)."
                Write-Host "  Per-repo install: pwsh ./install.ps1 -TargetRepo <path> -InstallAdapter copilot"
            }
            "kilocode" {
                Write-Host "  Kilo Code has no device-wide config -- it reads"
                Write-Host "  .kilocode/rules/*.md from each workspace."
                Write-Host "  Per-repo install:"
                Write-Host "    pwsh ./install.ps1 -TargetRepo <path> -InstallAdapter kilocode"
            }
            "kilo" {
                Write-Host "  Kilo Code has no device-wide config -- it reads"
                Write-Host "  .kilocode/rules/*.md from each workspace."
                Write-Host "  Per-repo install:"
                Write-Host "    pwsh ./install.ps1 -TargetRepo <path> -InstallAdapter kilocode"
            }
            default {
                Write-Host "  Unknown target: $t (use claude, codex, opencode, copilot, kilocode, generic, or all)"
            }
        }
    }
    Write-Host ""
    Write-Host "Device-wide install complete."
    Write-Host "Restart your CLI for changes to take effect."
    Write-Host "Verify with: pwsh $ScriptRoot\doctor.ps1"
}

if ($BootstrapHarness) {
    Write-Host ""
    Write-Host "Harness scaffold complete for $TargetRepo"
    Write-Host "Installed:"
    Write-Host "  - global ~/.agents assets"
    Write-Host "  - device-wide rules for claude, copilot, generic"
    Write-Host "  - repo scaffold (.kit/, .wiki/)"
    Write-Host "  - repo adapters (CLAUDE.md, AGENTS.md, .github/copilot-instructions.md)"
    Write-Host ""
    Write-Host "AI phases run automatically from an agent session."
    Write-Host ""
    Write-Host "  From Copilot CLI (recommended -- self-driving, no manual steps):"
    Write-Host "    POSIX:   bash ~/.agents/bin/copilot/kit-bootstrap.sh `"$TargetRepo`""
    Write-Host "    Windows: pwsh ~/.agents/bin/copilot/kit-bootstrap.ps1 `"$TargetRepo`""
    Write-Host "    This script does everything: scaffold (already done) -> git-archaeology"
    Write-Host "    -> kit-init -> wiki-init -> conventions.md with real detected content."
    Write-Host ""
    Write-Host "  From goal-orchestrator (autonomous iteration with review gates):"
    Write-Host "    copilot --agent goal-orchestrator -p `"Bootstrap the harness for $TargetRepo`""
    Write-Host ""
    Write-Host "  From any AI agent (Claude Code, Copilot, Codex, etc.):"
    Write-Host "    Say 'bootstrap this repo' or 'set up the harness for this repo'."
    Write-Host "    The agent reads ~/.agents/skills/bootstrap-harness/SKILL.md and"
    Write-Host "    executes every phase automatically (Phase 1-6, no manual steps)."
    Write-Host ""
    Write-Host "  The kit-bootstrap.sh script is also self-driving when run standalone:"
    Write-Host "    it detects whether the scaffold already exists and skips Phase 0 if so."
    Write-Host ""
    Write-Host "After the AI phases complete, .kit/context/conventions.md will contain"
    Write-Host "detected repo conventions (branch naming, commit style, layering, etc.)"
    Write-Host "that all downstream agents read to follow YOUR repo's actual patterns."
}
