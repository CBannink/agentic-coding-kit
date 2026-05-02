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
        $memDir = Join-Path $script:RepoTmp ".codex/context/agent-memory"
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
        New-Item -ItemType Directory -Path (Join-Path $script:RepoTmp2 ".codex/context") -Force | Out-Null
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
        $rPath = Join-Path $script:RepoTmp2 ".codex/context/reflections.md"
        $entries = 1..5 | ForEach-Object {
@"
- [2026-05-01] [source:harness-auto] [scope:repo] [class:gating]
  Pattern: test pattern $_
  Evidence: test evidence $_
  Suggested target: .codex/workflows/build.md
"@
        }
        Set-Content -Path $rPath -Value ($entries -join "`n`n")
        & (Join-Path $script:ToolsDir "reflect-trigger.ps1") -RepoRoot $script:RepoTmp2 -Json 2>$null | Out-Null
        $LASTEXITCODE | Should -Be 2
    }
}
