#!/usr/bin/env pwsh
# harness.Tests.ps1 — Pester smoke tests for the kit's load-bearing scripts.
#
# Run with:
#   Invoke-Pester ./tests/Pester/
#
# Covers the 5 scripts whose correctness the whole harness depends on:
#   _paths.ps1, scope-classifier.ps1, swarm-classifier.ps1,
#   state-init.ps1 + state-gate.ps1, specialist-memory-resolver.ps1, reflect-trigger.ps1
#
# These are smoke tests — happy paths and obvious failure modes only.
# Deeper behavior tests live with each tool's documented contract.

BeforeAll {
    $script:RepoRoot   = (Resolve-Path (Join-Path $PSScriptRoot "../..")).Path
    $script:ToolsDir   = Join-Path $script:RepoRoot "bundle/global/.agents/tools"
    # Use a temp AGENTS_HOME so tests don't pollute the real user dir
    $script:TestAgents = Join-Path ([System.IO.Path]::GetTempPath()) "agents-pester-$([guid]::NewGuid().ToString('N').Substring(0,8))"
    $env:AGENTS_HOME           = $script:TestAgents
    $env:AGENTS_SESSION_ROOT   = Join-Path $script:TestAgents "session-state"
    New-Item -ItemType Directory -Path $env:AGENTS_SESSION_ROOT -Force | Out-Null
}

AfterAll {
    if (Test-Path $script:TestAgents) {
        Remove-Item -Recurse -Force $script:TestAgents -ErrorAction SilentlyContinue
    }
    Remove-Item env:AGENTS_HOME -ErrorAction SilentlyContinue
    Remove-Item env:AGENTS_SESSION_ROOT -ErrorAction SilentlyContinue
}

Describe "_paths.ps1" {
    It "honors AGENTS_HOME env var" {
        . (Join-Path $script:ToolsDir "_paths.ps1")
        $script:AgentsRoot | Should -Be $env:AGENTS_HOME
    }
    It "computes session root under AGENTS_HOME by default" {
        . (Join-Path $script:ToolsDir "_paths.ps1")
        $script:SessionRoot | Should -Be $env:AGENTS_SESSION_ROOT
    }
    It "Get-SessionDir composes the session id" {
        . (Join-Path $script:ToolsDir "_paths.ps1")
        $dir = Get-SessionDir "abc123"
        $dir | Should -BeLike "*abc123*"
    }
    It "defaults session root to repo-local .kit/session-state in a bootstrapped repo" {
        $savedSessionRoot = $env:AGENTS_SESSION_ROOT
        Remove-Item env:AGENTS_SESSION_ROOT -ErrorAction SilentlyContinue
        $repoTmp = Join-Path $script:TestAgents "repo-$([guid]::NewGuid().ToString('N').Substring(0,8))"
        New-Item -ItemType Directory -Path (Join-Path $repoTmp ".kit/context") -Force | Out-Null
        Push-Location $repoTmp
        try {
            . (Join-Path $script:ToolsDir "_paths.ps1")
            $script:SessionRoot | Should -Be (Join-Path $repoTmp ".kit/session-state")
            $script:GlobalSessionRoot | Should -Be (Join-Path $script:TestAgents "session-state")
        } finally {
            Pop-Location
            $env:AGENTS_SESSION_ROOT = $savedSessionRoot
        }
    }
    It "falls back to global session root outside a bootstrapped repo" {
        $savedSessionRoot = $env:AGENTS_SESSION_ROOT
        Remove-Item env:AGENTS_SESSION_ROOT -ErrorAction SilentlyContinue
        $plainTmp = Join-Path $script:TestAgents "plain-$([guid]::NewGuid().ToString('N').Substring(0,8))"
        New-Item -ItemType Directory -Path $plainTmp -Force | Out-Null
        Push-Location $plainTmp
        try {
            . (Join-Path $script:ToolsDir "_paths.ps1")
            $script:SessionRoot | Should -Be (Join-Path $script:TestAgents "session-state")
        } finally {
            Pop-Location
            $env:AGENTS_SESSION_ROOT = $savedSessionRoot
        }
    }
}

Describe "scope-classifier.ps1" {
    It "classifies single component file as ISOLATED" {
        $out = & (Join-Path $script:ToolsDir "scope-classifier.ps1") -Files "src/components/Button.tsx" 2>$null | ConvertFrom-Json
        $out.scope | Should -Be "ISOLATED"
    }
    It "classifies migration file as CRITICAL" {
        $out = & (Join-Path $script:ToolsDir "scope-classifier.ps1") -Files "db/migrations/0042_add_users.sql" 2>$null | ConvertFrom-Json
        $out.scope | Should -Be "CRITICAL"
    }
    It "classifies shared utils as SHARED" {
        $out = & (Join-Path $script:ToolsDir "scope-classifier.ps1") -Files "packages/utils/index.ts" 2>$null | ConvertFrom-Json
        $out.scope | Should -Be "SHARED"
    }
    It "pushes large file count to SHARED even if all isolated" {
        $files = 1..7 | ForEach-Object { "src/component$_.tsx" }
        $out = & (Join-Path $script:ToolsDir "scope-classifier.ps1") -Files $files 2>$null | ConvertFrom-Json
        $out.scope | Should -Be "SHARED"
    }
}

Describe "swarm-classifier.ps1" {
    It "rejects sequential verbs" {
        $out = & (Join-Path $script:ToolsDir "swarm-classifier.ps1") -Task "fix the login bug" 2>$null | ConvertFrom-Json
        $out.mode | Should -Be "sequential"
    }
    It "rejects CRITICAL scope even with parallel verb" {
        $out = & (Join-Path $script:ToolsDir "swarm-classifier.ps1") -Task "audit the schema" -Scope CRITICAL 2>$null | ConvertFrom-Json
        $out.mode | Should -Be "sequential"
    }
    It "honors -OptIn for swarm-fanout" {
        $out = & (Join-Path $script:ToolsDir "swarm-classifier.ps1") -Task "redesign dashboard" -OptIn 2>$null | ConvertFrom-Json
        $out.mode | Should -Be "swarm-fanout"
    }
    It "returns swarm-review for parallel verb without strong fan-out signal" {
        $out = & (Join-Path $script:ToolsDir "swarm-classifier.ps1") -Task "review the diff" -Scope SHARED -FileCount 2 2>$null | ConvertFrom-Json
        $out.mode | Should -Be "swarm-review"
    }
}

Describe "state-init + state-gate" {
    BeforeAll {
        $script:Sid = "pester-$([guid]::NewGuid().ToString('N').Substring(0,8))"
        & (Join-Path $script:ToolsDir "state-init.ps1") -SessionId $script:Sid -Task "test-task" -Scope SHARED -ScopeReason "test" | Out-Null
    }
    It "creates state.json under session root" {
        $statePath = Join-Path $env:AGENTS_SESSION_ROOT "$($script:Sid)/state.json"
        Test-Path $statePath | Should -Be $true
    }
    It "state-gate accepts a known gate mark" {
        & (Join-Path $script:ToolsDir "state-gate.ps1") -SessionId $script:Sid -Mark "context_loaded" 2>&1 | Out-Null
        $LASTEXITCODE | Should -Be 0
    }
    It "state-gate rejects an unknown gate" {
        & (Join-Path $script:ToolsDir "state-gate.ps1") -SessionId $script:Sid -Mark "not_a_real_gate" 2>&1 | Out-Null
        $LASTEXITCODE | Should -Be 1
    }
    It "state-gate blocks an unmarked required gate check" {
        & (Join-Path $script:ToolsDir "state-gate.ps1") -SessionId $script:Sid -Gate "verification_evidence" 2>&1 | Out-Null
        $LASTEXITCODE | Should -Be 1
    }
}

Describe "specialist-memory-resolver.ps1" {
    BeforeAll {
        $script:Sid2     = "pester-spec-$([guid]::NewGuid().ToString('N').Substring(0,8))"
        $script:RepoTmp  = Join-Path ([System.IO.Path]::GetTempPath()) "agents-pester-repo-$([guid]::NewGuid().ToString('N').Substring(0,8))"
        $memDir = Join-Path $script:RepoTmp ".kit/context/agent-memory"
        New-Item -ItemType Directory -Path $memDir -Force | Out-Null
        Set-Content -Path (Join-Path $memDir "shared.md")     -Value "shared rule: always X"
        Set-Content -Path (Join-Path $memDir "implementer.md") -Value "implementer rule: always Y"
    }
    AfterAll {
        if (Test-Path $script:RepoTmp) { Remove-Item -Recurse -Force $script:RepoTmp -ErrorAction SilentlyContinue }
    }
    It "returns found=true with both shared + role file" {
        $out = & (Join-Path $script:ToolsDir "specialist-memory-resolver.ps1") -SessionId $script:Sid2 -Role "implementer" -RepoRoot $script:RepoTmp 2>$null | ConvertFrom-Json
        $out.found | Should -Be $true
        $out.files.Count | Should -BeGreaterOrEqual 2
        $out.prompt_block | Should -Match "shared rule"
        $out.prompt_block | Should -Match "implementer rule"
    }
    It "returns found=false when role memory is missing" {
        # Use a brand new role with no file
        $out = & (Join-Path $script:ToolsDir "specialist-memory-resolver.ps1") -SessionId $script:Sid2 -Role "no-such-role" -RepoRoot (Join-Path ([System.IO.Path]::GetTempPath()) "empty-$([guid]::NewGuid())") 2>$null | ConvertFrom-Json
        $out.found | Should -Be $false
    }
}

Describe "reflect-trigger.ps1" {
    BeforeAll {
        $script:RepoTmp2 = Join-Path ([System.IO.Path]::GetTempPath()) "agents-pester-reflect-$([guid]::NewGuid().ToString('N').Substring(0,8))"
        New-Item -ItemType Directory -Path (Join-Path $script:RepoTmp2 ".kit/context") -Force | Out-Null
    }
    AfterAll {
        if (Test-Path $script:RepoTmp2) { Remove-Item -Recurse -Force $script:RepoTmp2 -ErrorAction SilentlyContinue }
    }
    It "returns ok status with no entries" {
        $out = & (Join-Path $script:ToolsDir "reflect-trigger.ps1") -RepoRoot $script:RepoTmp2 -Json 2>$null | ConvertFrom-Json
        $out.status | Should -Be "ok"
        $out.count_total | Should -Be 0
    }
    It "returns mandatory and exit 2 when count >= 5" {
        $rPath = Join-Path $script:RepoTmp2 ".kit/context/reflections.md"
        $entries = 1..5 | ForEach-Object {
@"
- [2026-05-01] [source:harness-auto] [scope:repo] [class:gating]
  Pattern: test pattern $_
  Evidence: test evidence $_
  Suggested target: .kit/workflows/build.md
"@
        }
        Set-Content -Path $rPath -Value ($entries -join "`n`n")
        & (Join-Path $script:ToolsDir "reflect-trigger.ps1") -RepoRoot $script:RepoTmp2 -Json 2>$null | Out-Null
        $LASTEXITCODE | Should -Be 2
    }
}

Describe "install.ps1 copilot bin preservation" {
    # Regression: per-repo copilot adapter install after device-wide install
    # must keep ~/.agents/bin/copilot/*.sh intact.
    # The global Copy-Tree -ReplaceDestination wipes ~/.agents; Install-Adapter
    # for copilot-cli must re-plant the bin wrappers into $AgentsRoot/bin/copilot.

    BeforeAll {
        $script:InstallScript = Join-Path $script:RepoRoot "scripts/install.ps1"
        $script:HomeRootTmp   = Join-Path ([System.IO.Path]::GetTempPath()) "agents-pester-install-$([guid]::NewGuid().ToString('N').Substring(0,8))"
        $script:RepoTmpInst   = Join-Path ([System.IO.Path]::GetTempPath()) "agents-pester-repo-$([guid]::NewGuid().ToString('N').Substring(0,8))"
        New-Item -ItemType Directory -Path $script:HomeRootTmp -Force | Out-Null
        New-Item -ItemType Directory -Path $script:RepoTmpInst -Force | Out-Null
    }
    AfterAll {
        Remove-Item -Recurse -Force $script:HomeRootTmp -ErrorAction SilentlyContinue
        Remove-Item -Recurse -Force $script:RepoTmpInst -ErrorAction SilentlyContinue
    }

    It "per-repo copilot adapter install plants bin/copilot wrappers in AgentsRoot" {
        # Simulate only a per-repo adapter install (no -For copilot device-wide block).
        # The global install runs by default and wipes ~/.agents, so the fix must
        # re-plant bin/copilot wrappers as part of Install-Adapter.
        & $script:InstallScript `
            -HomeRoot $script:HomeRootTmp `
            -TargetRepo $script:RepoTmpInst `
            -InstallAdapter "copilot" `
            -Force 2>&1 | Out-Null

        $binDir = Join-Path $script:HomeRootTmp ".agents/bin/copilot"
        (Test-Path $binDir) | Should -Be $true
        (Test-Path (Join-Path $script:RepoTmpInst ".github/copilot-bin/kit-build.ps1")) | Should -Be $true
        $shFiles = @(Get-ChildItem -Path $binDir -Filter "*.sh" -File -ErrorAction SilentlyContinue)
        $ps1Files = @(Get-ChildItem -Path $binDir -Filter "*.ps1" -File -ErrorAction SilentlyContinue)
        $shFiles.Count | Should -BeGreaterThan 0
        $ps1Files.Count | Should -BeGreaterThan 0
    }

    It "bin/copilot wrappers survive a subsequent per-repo install after device-wide" {
        # Step 1: device-wide copilot install
        & $script:InstallScript `
            -HomeRoot $script:HomeRootTmp `
            -For "copilot" `
            -Force 2>&1 | Out-Null

        $binDir = Join-Path $script:HomeRootTmp ".agents/bin/copilot"
        $afterDeviceWideSh = @(Get-ChildItem -Path $binDir -Filter "*.sh" -File -ErrorAction SilentlyContinue).Count
        $afterDeviceWidePs1 = @(Get-ChildItem -Path $binDir -Filter "*.ps1" -File -ErrorAction SilentlyContinue).Count
        $afterDeviceWideSh | Should -BeGreaterThan 0
        $afterDeviceWidePs1 | Should -BeGreaterThan 0

        # Step 2: per-repo copilot adapter install (the sequence that previously wiped the wrappers)
        & $script:InstallScript `
            -HomeRoot $script:HomeRootTmp `
            -TargetRepo $script:RepoTmpInst `
            -InstallAdapter "copilot" `
            -Force 2>&1 | Out-Null

        $afterRepoSh = @(Get-ChildItem -Path $binDir -Filter "*.sh" -File -ErrorAction SilentlyContinue).Count
        $afterRepoPs1 = @(Get-ChildItem -Path $binDir -Filter "*.ps1" -File -ErrorAction SilentlyContinue).Count
        $afterRepoSh | Should -Be $afterDeviceWideSh
        $afterRepoPs1 | Should -Be $afterDeviceWidePs1
        (Test-Path (Join-Path $script:RepoTmpInst ".github/copilot-bin/kit-build.ps1")) | Should -Be $true
    }
}

Describe "install.ps1 preserves user skill memory across reinstall" {
    BeforeAll {
        $script:InstallScriptMem = Join-Path $script:RepoRoot "scripts/install.ps1"
        $script:HomeRootMem      = Join-Path ([System.IO.Path]::GetTempPath()) "agents-pester-mem-home-$([guid]::NewGuid().ToString('N').Substring(0,8))"
        New-Item -ItemType Directory -Path $script:HomeRootMem -Force | Out-Null

        & $script:InstallScriptMem `
            -HomeRoot $script:HomeRootMem `
            -For "copilot" `
            -Force 2>&1 | Out-Null

        $script:BuildSkillMemoryPath = Join-Path $script:HomeRootMem ".agents/skills/build/memory.md"
        Add-Content -Path $script:BuildSkillMemoryPath -Value @"

- [2099-01-01] [H confidence] [domain: tooling]
  Pattern: preserve-me-build-pattern
  Evidence: pester regression seed
  Apply when: reinstalling the kit
"@

        & $script:InstallScriptMem `
            -HomeRoot $script:HomeRootMem `
            -For "copilot" `
            -Force 2>&1 | Out-Null
    }
    AfterAll {
        Remove-Item -Recurse -Force $script:HomeRootMem -ErrorAction SilentlyContinue
    }

    It "keeps custom build skill memory entries after reinstall" {
        $content = Get-Content $script:BuildSkillMemoryPath -Raw -ErrorAction SilentlyContinue
        $content | Should -Match "preserve-me-build-pattern"
    }
}

Describe "install.ps1 -BootstrapHarness scaffolds conventions.md" {
    # Verify that a -BootstrapHarness install plants .kit/context/conventions.md
    # in the target repo. The file starts as a placeholder; bootstrap-harness
    # (the AI skill) then overwrites it with real content in Phase 1.

    BeforeAll {
        $script:InstallScriptBH = Join-Path $script:RepoRoot "scripts/install.ps1"
        $script:HomeRootBH      = Join-Path ([System.IO.Path]::GetTempPath()) "agents-pester-bh-home-$([guid]::NewGuid().ToString('N').Substring(0,8))"
        $script:RepoTmpBH       = Join-Path ([System.IO.Path]::GetTempPath()) "agents-pester-bh-repo-$([guid]::NewGuid().ToString('N').Substring(0,8))"
        New-Item -ItemType Directory -Path $script:HomeRootBH -Force | Out-Null
        New-Item -ItemType Directory -Path $script:RepoTmpBH  -Force | Out-Null
        # Run the bootstrap harness install (scaffold only — no AI phases run in tests)
        & $script:InstallScriptBH `
            -HomeRoot $script:HomeRootBH `
            -TargetRepo $script:RepoTmpBH `
            -BootstrapHarness `
            -Force 2>&1 | Out-Null
    }
    AfterAll {
        Remove-Item -Recurse -Force $script:HomeRootBH -ErrorAction SilentlyContinue
        Remove-Item -Recurse -Force $script:RepoTmpBH  -ErrorAction SilentlyContinue
    }

    It "plants .kit/context/conventions.md in the target repo" {
        $conventionsPath = Join-Path $script:RepoTmpBH ".kit/context/conventions.md"
        Test-Path $conventionsPath | Should -Be $true
    }

    It "conventions.md mentions /bootstrap-harness so readers know how to populate it" {
        $conventionsPath = Join-Path $script:RepoTmpBH ".kit/context/conventions.md"
        $content = Get-Content $conventionsPath -Raw -ErrorAction SilentlyContinue
        $content | Should -Match "bootstrap-harness"
    }

    It "plants .wiki/architecture.md in the target repo" {
        $archPath = Join-Path $script:RepoTmpBH ".wiki/architecture.md"
        Test-Path $archPath | Should -Be $true
    }

    It "plants .wiki/features.md in the target repo" {
        $featPath = Join-Path $script:RepoTmpBH ".wiki/features.md"
        Test-Path $featPath | Should -Be $true
    }

    It "install.ps1 -BootstrapHarness output mentions AI phases next step" {
        # Re-run capturing output to verify the next-step guidance is present.
        # Use *>&1 to capture Write-Host (Information stream 6) alongside stdout/stderr.
        $output = & $script:InstallScriptBH `
            -HomeRoot $script:HomeRootBH `
            -TargetRepo $script:RepoTmpBH `
            -BootstrapHarness `
            -Force *>&1 | Out-String
        $output | Should -Match "kit-bootstrap"
    }

    It "install.ps1 -BootstrapHarness output documents self-driving behavior" {
        $output = & $script:InstallScriptBH `
            -HomeRoot $script:HomeRootBH `
            -TargetRepo $script:RepoTmpBH `
            -BootstrapHarness `
            -Force *>&1 | Out-String
        # Must mention that agents run phases automatically, not just point to manual options
        $output | Should -Match "automatically|self-driving|automatically"
    }
}

Describe "kit-bootstrap.sh exists in bundle" {
    # Verify the kit-bootstrap.sh wrapper is present in the bundle so it
    # gets planted in ~/.agents/bin/copilot/ during install.

    It "bundle/adapters/copilot-cli/bin/kit-bootstrap.sh exists" {
        $bootstrapPath = Join-Path $script:RepoRoot "bundle/adapters/copilot-cli/bin/kit-bootstrap.sh"
        Test-Path $bootstrapPath | Should -Be $true
    }

    It "kit-bootstrap.sh references workflow-implementer for AI phases" {
        $bootstrapPath = Join-Path $script:RepoRoot "bundle/adapters/copilot-cli/bin/kit-bootstrap.sh"
        $content = Get-Content $bootstrapPath -Raw -ErrorAction SilentlyContinue
        $content | Should -Match "workflow-implementer"
    }

    It "kit-bootstrap.sh references git-archaeology skill" {
        $bootstrapPath = Join-Path $script:RepoRoot "bundle/adapters/copilot-cli/bin/kit-bootstrap.sh"
        $content = Get-Content $bootstrapPath -Raw -ErrorAction SilentlyContinue
        $content | Should -Match "git-archaeology"
    }

    It "kit-bootstrap.sh references kit-init skill" {
        $bootstrapPath = Join-Path $script:RepoRoot "bundle/adapters/copilot-cli/bin/kit-bootstrap.sh"
        $content = Get-Content $bootstrapPath -Raw -ErrorAction SilentlyContinue
        $content | Should -Match "kit-init"
    }

    It "kit-bootstrap.sh references wiki-init skill" {
        $bootstrapPath = Join-Path $script:RepoRoot "bundle/adapters/copilot-cli/bin/kit-bootstrap.sh"
        $content = Get-Content $bootstrapPath -Raw -ErrorAction SilentlyContinue
        $content | Should -Match "wiki-init"
    }

    It "kit-bootstrap.sh includes Phase 0 self-driving scaffold step" {
        $bootstrapPath = Join-Path $script:RepoRoot "bundle/adapters/copilot-cli/bin/kit-bootstrap.sh"
        $content = Get-Content $bootstrapPath -Raw -ErrorAction SilentlyContinue
        # Must attempt the scaffold itself rather than requiring it to pre-exist
        $content | Should -Match "install\.ps1"
        $content | Should -Match "Phase 0"
    }

    It "kit-bootstrap.sh reads kit-config.sh for KIT_ROOT" {
        $bootstrapPath = Join-Path $script:RepoRoot "bundle/adapters/copilot-cli/bin/kit-bootstrap.sh"
        $content = Get-Content $bootstrapPath -Raw -ErrorAction SilentlyContinue
        $content | Should -Match "kit-config\.sh"
    }
}

Describe "install.ps1 -For copilot plants kit-bootstrap.sh in bin/copilot" {
    BeforeAll {
        $script:HomeRootKB = Join-Path ([System.IO.Path]::GetTempPath()) "agents-pester-kb-home-$([guid]::NewGuid().ToString('N').Substring(0,8))"
        New-Item -ItemType Directory -Path $script:HomeRootKB -Force | Out-Null
        & (Join-Path $script:RepoRoot "scripts/install.ps1") `
            -HomeRoot $script:HomeRootKB `
            -For "copilot" `
            -Force 2>&1 | Out-Null
    }
    AfterAll {
        Remove-Item -Recurse -Force $script:HomeRootKB -ErrorAction SilentlyContinue
    }

    It "kit-bootstrap.sh is planted in bin/copilot after -For copilot install" {
        $p = Join-Path $script:HomeRootKB ".agents/bin/copilot/kit-bootstrap.sh"
        Test-Path $p | Should -Be $true
    }

    It "kit-config.sh is planted in bin/copilot after -For copilot install" {
        $p = Join-Path $script:HomeRootKB ".agents/bin/copilot/kit-config.sh"
        Test-Path $p | Should -Be $true
    }

    It "kit-copilot-common.sh is planted in bin/copilot after -For copilot install" {
        $p = Join-Path $script:HomeRootKB ".agents/bin/copilot/kit-copilot-common.sh"
        Test-Path $p | Should -Be $true
    }

    It "kit-config.sh contains KIT_ROOT pointing to the kit repo" {
        $p = Join-Path $script:HomeRootKB ".agents/bin/copilot/kit-config.sh"
        $content = Get-Content $p -Raw -ErrorAction SilentlyContinue
        $content | Should -Match "KIT_ROOT="
        # Should point to a real directory containing scripts/install.ps1
        $kitRoot = ($content -split "`n" | Where-Object { $_ -match "^KIT_ROOT=" } | Select-Object -First 1) -replace '^KIT_ROOT="(.+)".*', '$1' -replace '/', [System.IO.Path]::DirectorySeparatorChar
        Test-Path (Join-Path $kitRoot "scripts/install.ps1") | Should -Be $true
    }
}

Describe "kit-goal.sh routes through kit workflow wrappers" {
    # Verify that kit-goal.sh is wired to route each goal type through the
    # correct kit shell wrapper rather than calling leaf agents directly.

    It "bundle/adapters/copilot-cli/bin/kit-goal.sh exists" {
        $goalPath = Join-Path $script:RepoRoot "bundle/adapters/copilot-cli/bin/kit-goal.sh"
        Test-Path $goalPath | Should -Be $true
    }

    It "kit-goal.sh routes CODE goals through kit-build.sh" {
        $content = Get-Content (Join-Path $script:RepoRoot "bundle/adapters/copilot-cli/bin/kit-goal.sh") -Raw
        $content | Should -Match "kit-build\.sh"
    }

    It "kit-goal.sh routes INVESTIGATION goals through kit-investigate.sh" {
        $content = Get-Content (Join-Path $script:RepoRoot "bundle/adapters/copilot-cli/bin/kit-goal.sh") -Raw
        $content | Should -Match "kit-investigate\.sh"
    }

    It "kit-goal.sh routes ANALYSIS goals through kit-analyze.sh" {
        $content = Get-Content (Join-Path $script:RepoRoot "bundle/adapters/copilot-cli/bin/kit-goal.sh") -Raw
        $content | Should -Match "kit-analyze\.sh"
    }

    It "kit-goal.sh routes REVIEW goals through kit-review.sh" {
        $content = Get-Content (Join-Path $script:RepoRoot "bundle/adapters/copilot-cli/bin/kit-goal.sh") -Raw
        $content | Should -Match "REVIEW\)"
        $content | Should -Match "kit-review\.sh"
    }

    It "kit-goal.sh routes BOOTSTRAP goals through kit-bootstrap.sh" {
        $content = Get-Content (Join-Path $script:RepoRoot "bundle/adapters/copilot-cli/bin/kit-goal.sh") -Raw
        $content | Should -Match "kit-bootstrap\.sh"
    }

    It "kit-goal.sh calls pre-session lifecycle script" {
        $content = Get-Content (Join-Path $script:RepoRoot "bundle/adapters/copilot-cli/bin/kit-goal.sh") -Raw
        $content | Should -Match "pre-session\.ps1"
    }

    It "kit-goal.sh uses a valid pre-session mode for goal entry" {
        $content = Get-Content (Join-Path $script:RepoRoot "bundle/adapters/copilot-cli/bin/kit-goal.sh") -Raw
        $content | Should -Not -Match "-Mode goal"
        $content | Should -Match "-Mode analyze"
    }

    It "kit-goal.sh calls post-session lifecycle script" {
        $content = Get-Content (Join-Path $script:RepoRoot "bundle/adapters/copilot-cli/bin/kit-goal.sh") -Raw
        $content | Should -Match "post-session\.ps1"
    }

    It "kit-goal.sh falls back to powershell for lifecycle scripts when pwsh is unavailable" {
        $content = Get-Content (Join-Path $script:RepoRoot "bundle/adapters/copilot-cli/bin/kit-goal.sh") -Raw
        $content | Should -Match 'PWSH="\$\(command -v pwsh 2>/dev/null \|\| command -v powershell 2>/dev/null \|\| true\)"'
        $content | Should -Match '"\$PWSH" -NoProfile -File "\$HOME/\.agents/tools/pre-session\.ps1"'
        $content | Should -Match '"\$PWSH" -NoProfile -File "\$HOME/\.agents/tools/post-session\.ps1"'
    }

    It "kit-build.sh sources the shared Copilot helper" {
        $content = Get-Content (Join-Path $script:RepoRoot "bundle/adapters/copilot-cli/bin/kit-build.sh") -Raw
        $content | Should -Match "kit-copilot-common\.sh"
    }

    It "kit-build.sh records live Copilot progress" {
        $content = Get-Content (Join-Path $script:RepoRoot "bundle/adapters/copilot-cli/bin/kit-build.sh") -Raw
        $content | Should -Match "kit_announce_agent"
        $content | Should -Match "kit_heartbeat_start"
    }

    It "goal.md shared workflow command exists in _shared/workflow-commands" {
        $goalMd = Join-Path $script:RepoRoot "bundle/adapters/_shared/workflow-commands/goal.md"
        Test-Path $goalMd | Should -Be $true
    }

    It "goal.md routes CODE goals to /build" {
        $goalMd = Join-Path $script:RepoRoot "bundle/adapters/_shared/workflow-commands/goal.md"
        $content = Get-Content $goalMd -Raw -ErrorAction SilentlyContinue
        $content | Should -Match "/build"
    }

    It "goal.md routes INVESTIGATION goals to /investigate" {
        $goalMd = Join-Path $script:RepoRoot "bundle/adapters/_shared/workflow-commands/goal.md"
        $content = Get-Content $goalMd -Raw -ErrorAction SilentlyContinue
        $content | Should -Match "/investigate"
    }

    It "goal.md routes BOOTSTRAP goals to /bootstrap-harness" {
        $goalMd = Join-Path $script:RepoRoot "bundle/adapters/_shared/workflow-commands/goal.md"
        $content = Get-Content $goalMd -Raw -ErrorAction SilentlyContinue
        $content | Should -Match "/bootstrap-harness"
    }

    It "copilot goal-orchestrator agent references kit-build.sh" {
        $agentPath = Join-Path $script:RepoRoot "bundle/adapters/copilot-cli/.github/agents/goal-orchestrator.agent.md"
        $content = Get-Content $agentPath -Raw -ErrorAction SilentlyContinue
        $content | Should -Match "kit-build\.sh"
    }

    It "copilot goal-orchestrator agent references kit-investigate.sh" {
        $agentPath = Join-Path $script:RepoRoot "bundle/adapters/copilot-cli/.github/agents/goal-orchestrator.agent.md"
        $content = Get-Content $agentPath -Raw -ErrorAction SilentlyContinue
        $content | Should -Match "kit-investigate\.sh"
    }

    It "copilot goal-orchestrator agent references kit-analyze.sh" {
        $agentPath = Join-Path $script:RepoRoot "bundle/adapters/copilot-cli/.github/agents/goal-orchestrator.agent.md"
        $content = Get-Content $agentPath -Raw -ErrorAction SilentlyContinue
        $content | Should -Match "kit-analyze\.sh"
    }

    It "copilot goal-orchestrator agent references lifecycle pre-session" {
        $agentPath = Join-Path $script:RepoRoot "bundle/adapters/copilot-cli/.github/agents/goal-orchestrator.agent.md"
        $content = Get-Content $agentPath -Raw -ErrorAction SilentlyContinue
        $content | Should -Match "pre-session\.ps1"
    }

    It "copilot goal-orchestrator agent uses a valid pre-session mode" {
        $agentPath = Join-Path $script:RepoRoot "bundle/adapters/copilot-cli/.github/agents/goal-orchestrator.agent.md"
        $content = Get-Content $agentPath -Raw -ErrorAction SilentlyContinue
        $content | Should -Not -Match "-Mode goal"
        $content | Should -Match "-Mode analyze"
    }

    It "claude-code goal-orchestrator agent routes CODE to /build" {
        $agentPath = Join-Path $script:RepoRoot "bundle/adapters/claude-code/.claude/agents/goal-orchestrator.md"
        $content = Get-Content $agentPath -Raw -ErrorAction SilentlyContinue
        $content | Should -Match "/build"
        $content | Should -Match "/investigate"
    }
}

Describe "kit-copilot-common.sh progress helpers" {
    # Verify that the shared progress/recording helpers introduced for CLI
    # visibility live in the shared Copilot helper and are used by wrappers.

    BeforeAll {
        $script:CopilotCommonSh = Join-Path $script:RepoRoot "bundle/adapters/copilot-cli/bin/kit-copilot-common.sh"
        $script:CopilotCommonContent = Get-Content $script:CopilotCommonSh -Raw -ErrorAction SilentlyContinue
        $script:BuildSh = Join-Path $script:RepoRoot "bundle/adapters/copilot-cli/bin/kit-build.sh"
        $script:BuildContent = Get-Content $script:BuildSh -Raw -ErrorAction SilentlyContinue
        $script:ReviewSh = Join-Path $script:RepoRoot "bundle/adapters/copilot-cli/bin/kit-review.sh"
        $script:ReviewContent = Get-Content $script:ReviewSh -Raw -ErrorAction SilentlyContinue
        $script:AnalyzeSh = Join-Path $script:RepoRoot "bundle/adapters/copilot-cli/bin/kit-analyze.sh"
        $script:AnalyzeContent = Get-Content $script:AnalyzeSh -Raw -ErrorAction SilentlyContinue
        $script:PlanSh = Join-Path $script:RepoRoot "bundle/adapters/copilot-cli/bin/kit-plan.sh"
        $script:PlanContent = Get-Content $script:PlanSh -Raw -ErrorAction SilentlyContinue
        $script:GoalSh = Join-Path $script:RepoRoot "bundle/adapters/copilot-cli/bin/kit-goal.sh"
        $script:GoalContent = Get-Content $script:GoalSh -Raw -ErrorAction SilentlyContinue
    }

    It "kit-copilot-common.sh defines kit_announce_agent" {
        $script:CopilotCommonContent | Should -Match "kit_announce_agent\(\)"
    }

    It "kit-copilot-common.sh defines kit_heartbeat_start" {
        $script:CopilotCommonContent | Should -Match "kit_heartbeat_start\(\)"
    }

    It "kit-copilot-common.sh defines kit_heartbeat_stop" {
        $script:CopilotCommonContent | Should -Match "kit_heartbeat_stop\(\)"
    }

    It "kit-copilot-common.sh defines kit_record_subagent" {
        $script:CopilotCommonContent | Should -Match "kit_record_subagent\(\)"
    }

    It "kit_record_subagent records local status and workflow evidence" {
        $script:CopilotCommonContent | Should -Match "agent-status\.tsv"
        $script:CopilotCommonContent | Should -Match "workflow-evidence\.ps1"
        $script:CopilotCommonContent | Should -Match "AddAgent"
        $script:CopilotCommonContent | Should -Match "AddNote"
    }

    It "kit_run_ps_tool warns once when _run-ps.sh is unavailable" {
        $script:CopilotCommonContent | Should -Match 'kit_warn_ps_runner_unavailable\(\)'
        $script:CopilotCommonContent | Should -Match "KIT_PS_RUNNER_WARNED"
        $script:CopilotCommonContent | Should -Match 'if \[ ! -x "\$runner" \]; then\s+kit_warn_ps_runner_unavailable "\$runner"'
        $script:CopilotCommonContent | Should -Match "durable recording unavailable"
    }

    It "kit_announce_agent emits agent name and working-on line" {
        # The banner must include both the agent label and a task description
        $script:CopilotCommonContent | Should -Match 'Agent:'
        $script:CopilotCommonContent | Should -Match 'Working:'
    }

    It "kit_record_subagent updates state-gate agents_run when state exists" {
        $script:CopilotCommonContent | Should -Match "state-gate\.ps1"
        $script:CopilotCommonContent | Should -Match "state\.json"
        $script:CopilotCommonContent | Should -Match "AddAgent"
    }

    It "kit-build.sh calls kit_announce_agent" {
        $script:BuildContent | Should -Match "kit_announce_agent"
    }

    It "kit-build.sh calls kit_record_subagent" {
        $script:BuildContent | Should -Match "kit_record_subagent"
    }

    It "kit-build.sh calls kit_heartbeat_start" {
        $script:BuildContent | Should -Match "kit_heartbeat_start"
    }

    It "kit-build.sh calls kit_heartbeat_stop" {
        $script:BuildContent | Should -Match "kit_heartbeat_stop"
    }

    It "kit-review.sh calls kit_announce_agent" {
        $script:ReviewContent | Should -Match "kit_announce_agent"
    }

    It "kit-review.sh calls kit_record_subagent" {
        $script:ReviewContent | Should -Match "kit_record_subagent"
    }

    It "kit-review.sh calls kit_heartbeat_start for parallel phase" {
        $script:ReviewContent | Should -Match "kit_heartbeat_start"
    }

    It "kit-build.sh waits for each parallel reviewer without bare multi-wait" {
        $script:BuildContent | Should -Match 'if wait "\$QPID"; then'
        $script:BuildContent | Should -Match 'if wait "\$SPID"; then'
        $script:BuildContent | Should -Not -Match 'wait \$QPID \$SPID'
        $script:BuildContent | Should -Not -Match 'wait "\$QPID" "\$SPID"'
    }

    It "kit-review.sh waits for each parallel reviewer without bare multi-wait" {
        $script:ReviewContent | Should -Match 'if wait "\$QPID"; then'
        $script:ReviewContent | Should -Match 'if wait "\$SPID"; then'
        $script:ReviewContent | Should -Match 'if wait "\$MPID"; then'
        $script:ReviewContent | Should -Not -Match 'wait \$QPID \$SPID \$MPID'
        $script:ReviewContent | Should -Not -Match 'wait "\$QPID" "\$SPID" "\$MPID"'
    }

    It "kit-analyze.sh keeps heartbeat coverage through synthesis" {
        $script:AnalyzeContent | Should -Match '(?s)kit_announce_agent "copilot \(synthesis\)".*?kit_record_subagent "\$SESSION_DIR" "copilot" "synthesize analysis report" "started".*?_hb=\$\(kit_heartbeat_start\).*?if copilot -p .*?kit_heartbeat_stop "\$_hb".*?kit_record_subagent "\$SESSION_DIR" "copilot" "\$_synth_task" "\$_synth_status".*?kit_done_agent "copilot \(synthesis\)"'
    }

    It "kit-plan.sh keeps heartbeat coverage through synthesis" {
        $script:PlanContent | Should -Match '(?s)kit_announce_agent "copilot \(synthesis\)".*?kit_record_subagent "\$SESSION_DIR" "copilot" "write plan" "started".*?_hb=\$\(kit_heartbeat_start\).*?if copilot -p .*?kit_heartbeat_stop "\$_hb".*?kit_record_subagent "\$SESSION_DIR" "copilot" "\$_plan_task" "\$_plan_status".*?kit_done_agent "copilot \(synthesis\)"'
    }

    It "kit-goal.sh calls kit_announce_agent for classify phase" {
        $script:GoalContent | Should -Match "kit_announce_agent"
    }

    It "kit-goal.sh classification prompt includes REVIEW" {
        $script:GoalContent | Should -Match "GOAL_TYPE: <CODE\|DESIGN\|INVESTIGATION\|ANALYSIS\|REVIEW\|REFACTOR\|BOOTSTRAP\|MULTI>"
    }

    It "kit-bootstrap.sh calls kit_announce_agent for each phase" {
        $bootstrapContent = Get-Content (Join-Path $script:RepoRoot "bundle/adapters/copilot-cli/bin/kit-bootstrap.sh") -Raw
        # Should appear at least 3 times (phases 1, 2, 3)
        $count = ([regex]::Matches($bootstrapContent, "kit_announce_agent")).Count
        $count | Should -BeGreaterOrEqual 3
    }

    It "kit-bootstrap.sh records subagent events for all 3 phases" {
        $bootstrapContent = Get-Content (Join-Path $script:RepoRoot "bundle/adapters/copilot-cli/bin/kit-bootstrap.sh") -Raw
        $count = ([regex]::Matches($bootstrapContent, "kit_record_subagent")).Count
        # 2 records per phase (started + done) x 3 phases = 6
        $count | Should -BeGreaterOrEqual 6
    }

    It "kit-investigate.sh calls kit_announce_agent" {
        $content = Get-Content (Join-Path $script:RepoRoot "bundle/adapters/copilot-cli/bin/kit-investigate.sh") -Raw
        $content | Should -Match "kit_announce_agent"
    }
}

Describe "kit-goal.sh routing determinism" {
    # Verify that kit-goal.sh behaves like a deterministic wrapper-first router:
    # - Never calls goal-orchestrator agent for classification (would cause recursion)
    # - Routes every supported type to a dedicated wrapper (no silent generic fallback)
    # - Fails closed for MULTI and unrecognized types

    BeforeAll {
        $script:GoalShPath = Join-Path $script:RepoRoot "bundle/adapters/copilot-cli/bin/kit-goal.sh"
        $script:GoalShContent = Get-Content $script:GoalShPath -Raw -ErrorAction SilentlyContinue
        $script:AgentPath = Join-Path $script:RepoRoot "bundle/adapters/copilot-cli/.github/agents/goal-orchestrator.agent.md"
        $script:AgentContent = Get-Content $script:AgentPath -Raw -ErrorAction SilentlyContinue
    }

    It "kit-goal.sh classify phase does not invoke goal-orchestrator agent (no recursion)" {
        # The classify call must NOT use --agent goal-orchestrator
        # (that would recurse: kit-goal -> goal-orchestrator -> kit-goal)
        $script:GoalShContent | Should -Not -Match "copilot --agent goal-orchestrator\s+-p.*[Cc]lassify"
        $script:GoalShContent | Should -Not -Match "--agent goal-orchestrator.*[Cc]lassify"
    }

    It "kit-goal.sh classify uses inline copilot -p (no agent) for classification" {
        # Inline classify: uses -p "Classify this goal..." (no --agent); timeout wrapper (kit_copilot_timed) is allowed.
        $script:GoalShContent | Should -Match '-p "Classify this goal'
        $script:GoalShContent | Should -Not -Match '--agent.*Classify this goal'
    }

    It "kit-goal.sh routes DESIGN goals through kit-redesign.sh" {
        $script:GoalShContent | Should -Match "DESIGN\)"
        $script:GoalShContent | Should -Match "kit-redesign\.sh"
    }

    It "kit-goal.sh routes REFACTOR goals through kit-build.sh" {
        # REFACTOR is in the same CODE|REFACTOR case
        $script:GoalShContent | Should -Match "CODE\|REFACTOR\)"
        # And both route to kit-build.sh
        $lines = $script:GoalShContent -split "`n"
        $codeRefactorIdx = ($lines | Select-String "CODE\|REFACTOR\)" | Select-Object -First 1).LineNumber
        $buildCallIdx = ($lines | Select-String "kit-build\.sh" | Select-Object -First 1).LineNumber
        $buildCallIdx | Should -BeGreaterThan $codeRefactorIdx
    }

    It "kit-goal.sh CODE/REFACTOR NEEDS_PLAN=YES routes to kit-build.sh (not goal-orchestrator agent)" {
        # The planning prefix path must call kit-build.sh, not goal-orchestrator
        $script:GoalShContent | Should -Match '"Plan before building:'
        $script:GoalShContent | Should -Not -Match '--agent goal-orchestrator.*[Pp]lan'
    }

    It "kit-goal.sh fails closed for MULTI type (UNROUTABLE)" {
        $script:GoalShContent | Should -Match "MULTI\)"
        $script:GoalShContent | Should -Match "UNROUTABLE.*MULTI"
    }

    It "kit-goal.sh fails closed for unrecognized goal type" {
        # The wildcard case must not silently delegate -- it must exit 1
        $script:GoalShContent | Should -Match "UNROUTABLE"
        $script:GoalShContent | Should -Match '_route_exit=1'
    }

    It "kit-goal.sh fails closed when classifier output omits INFO_CHECK" {
        # The heuristic may set INFO_CHECK="SUFFICIENT" internally; the LLM path must
        # validate the parsed value through a case statement (fail-closed if missing/invalid).
        $script:GoalShContent | Should -Match "missing INFO_CHECK"
        $script:GoalShContent | Should -Match 'case "\$INFO_CHECK" in\s+SUFFICIENT\|NEEDED'
    }

    It "kit-goal.sh fails closed when classifier output omits NEEDS_PLAN" {
        # The heuristic may use a local needs-plan variable internally; the LLM path must
        # validate the parsed value through a case statement (fail-closed if missing/invalid).
        $script:GoalShContent | Should -Match "missing NEEDS_PLAN"
        $script:GoalShContent | Should -Match 'case "\$NEEDS_PLAN" in\s+YES\|NO'
    }

    It "kit-goal.sh self-evaluation does not call goal-orchestrator agent" {
        # The verdict pass must use plain copilot -p, not --agent goal-orchestrator
        $script:GoalShContent | Should -Not -Match "--agent goal-orchestrator.*[Vv]erdict\|[Ss]elf-[Ee]valuate"
        $script:GoalShContent | Should -Not -Match "--agent goal-orchestrator.*GOAL_VERDICT"
    }

    It "kit-goal.sh self-evaluation only runs on successful routes (_route_exit -eq 0)" {
        $script:GoalShContent | Should -Match '_route_exit.*-eq.*0'
    }

    It "goal-orchestrator agent does not advise redirecting simple tasks to user" {
        # Phase 0 must not contain the advisory 'STOP and redirect if single-edit task'
        $script:AgentContent | Should -Not -Match "STOP and redirect if"
        $script:AgentContent | Should -Not -Match "tell user to use.*kit-build"
        $script:AgentContent | Should -Not -Match "Single-edit task with obvious scope"
    }

    It "goal-orchestrator agent routes DESIGN through kit-redesign.sh" {
        $script:AgentContent | Should -Match "kit-redesign\.sh"
    }

    It "goal-orchestrator agent lists kit-redesign wrapper in shell wrappers table" {
        $script:AgentContent | Should -Match "kit-redesign\.\(ps1\\\|sh\)"
    }

    It "goal-orchestrator agent description does not mention triaging simple tasks" {
        $script:AgentContent | Should -Not -Match "Triages simple tasks"
    }

    It "goal-orchestrator agent no longer describes DESIGN as having no dedicated wrapper" {
        $script:AgentContent | Should -Not -Match "For DESIGN \(no dedicated wrapper\)"
        $script:AgentContent | Should -Not -Match "### For DESIGN \(no dedicated wrapper\)"
    }

    It "repo-local kit-goal mirrors stay synced with bundled adapter" {
        $bundleGoal = Get-Content (Join-Path $script:RepoRoot "bundle/adapters/copilot-cli/bin/kit-goal.sh") -Raw
        foreach ($mirror in @("bin/kit-goal.sh", ".github/copilot-bin/kit-goal.sh")) {
            (Get-Content (Join-Path $script:RepoRoot $mirror) -Raw) | Should -Be $bundleGoal
        }
    }

    It "goal-e2e-smoke fixture kit-goal mirrors stay synced with bundled adapter" {
        $bundleGoal = Get-Content (Join-Path $script:RepoRoot "bundle/adapters/copilot-cli/bin/kit-goal.sh") -Raw
        foreach ($mirror in @("goal-e2e-smoke/bin/kit-goal.sh", "goal-e2e-smoke/.github/copilot-bin/kit-goal.sh")) {
            (Get-Content (Join-Path $script:RepoRoot $mirror) -Raw) | Should -Be $bundleGoal
        }
    }

    It "goal-e2e-smoke fixture has multiple Python test files for substantive coverage" {
        $smokeTestDir = Join-Path $script:RepoRoot "goal-e2e-smoke/tests"
        $testFiles = @(Get-ChildItem -Path $smokeTestDir -Filter "test_*.py" -File -ErrorAction SilentlyContinue)
        $testFiles.Count | Should -BeGreaterThan 1
    }

    It "goal-e2e-smoke fixture has src modules beyond the trivial calculator" {
        $smokeSrcDir = Join-Path $script:RepoRoot "goal-e2e-smoke/src"
        $srcFiles = @(Get-ChildItem -Path $smokeSrcDir -Filter "*.py" -File -ErrorAction SilentlyContinue)
        $srcFiles.Count | Should -BeGreaterOrEqual 2
    }
}
