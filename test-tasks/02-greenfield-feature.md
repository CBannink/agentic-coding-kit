# Test 02: Greenfield feature work in an empty repo

**What this tests**: when a user opens an empty repo and asks for a
non-trivial feature, does the agent fire `/wiki-init` + `/kit-init` first,
update `.wiki/features.md` after the feature ships, and run the full
lifecycle ceremony?

**Compliance items checked**:
- Wiki bootstrapped: `.wiki/index.md` and `.wiki/features.md` exist
- Wiki updated: `features.md` mtime > session start (proves the agent
  updated the wiki AFTER adding the feature, not just at bootstrap)
- Kit tree present: `.kit/context/memory.md` exists
- Lifecycle gates marked: all required gates fired
- Iron Law: verification commands recorded
- Workflow evidence: at least one agent recorded

## Setup (run first)

```powershell
$testdir = Join-Path $env:TEMP "kit-test-02-$(Get-Random)"
New-Item -ItemType Directory -Path $testdir -Force | Out-Null
Set-Location $testdir
git init -q

# Minimal Python project shell -- no existing kit/wiki state
@"
[tool.poetry]
name = "test-cli"
version = "0.1.0"
description = "Test CLI for kit compliance"
"@ | Set-Content pyproject.toml -Encoding UTF8

New-Item -ItemType Directory -Path src/test_cli -Force | Out-Null
@"
def cli():
    print('hello')
"@ | Set-Content src/test_cli/__init__.py -Encoding UTF8

git add -A; git commit -q -m "initial scaffold"
"Test repo at: $testdir"
```

## Task prompt (paste into the agent)

```
This is a fresh Python project. Add a new CLI subcommand `greet --name X`
that prints `Hello, X!`. It should be invokable as `python -m test_cli greet --name Alice`.

The kit's always-on rules apply:
- .wiki/ doesn't exist yet -- bootstrap it via /wiki-init before non-trivial work
- .kit/ doesn't exist yet -- bootstrap it via /kit-init
- Update .wiki/features.md after the feature ships
- All lifecycle scripts (state-init, state-gate, workflow-evidence, post-session) must run
- Iron Law: provide fresh verification evidence (run the CLI, capture output)

Complete the task. Report what you did, including which kit lifecycle
scripts ran and whether you updated the wiki AFTER the feature shipped
(not just at bootstrap).
```

## Acceptance criteria

After the agent reports done, run:

```powershell
pwsh ./scripts/test-compliance.ps1 `
    -SessionId <session-id-from-state-json> `
    -RepoRoot $testdir `
    -ExpectWiki `
    -ExpectFeatureChange `
    -ExpectKitTree `
    -MinAgentsRecorded 1
```

**PASS** = score >=80% AND zero CRITICAL fails.
**FAIL** = `wiki_present` FAIL (no /wiki-init), OR `features_md_updated` FAIL
(wiki bootstrapped but never updated after feature added -- this is the
exact failure pattern the field reflection identified), OR
`iron_law_verification` FAIL.

## Cleanup

```powershell
Remove-Item -Recurse -Force $testdir
```
