# Tests

Smoke tests for the harness. Not exhaustive; they catch regressions in the
load-bearing scripts, workflow contracts, and focused installer paths.

## Requirements

- **PowerShell 7+ (pwsh)** - the whole kit is designed for pwsh 7+, not
  Windows PowerShell 5.1. Shebangs say `pwsh` and files are UTF-8 without BOM.
- **Pester 5.0+** - `Install-Module Pester -MinimumVersion 5.0.0 -Scope CurrentUser -Force`

The suite has a version guard. Running it under Windows PowerShell's bundled
Pester 3.4 fails fast with a prerequisite error instead of many false failures.

## Run

```powershell
pwsh -NoProfile -Command "Invoke-Pester ./tests/Pester/"
```

## What's Covered

- `_paths.ps1` - env-var resolution and `Get-SessionDir` composition
- `scope-classifier.ps1` - ISOLATED / SHARED / CRITICAL routing
- `swarm-classifier.ps1` - sequential / swarm-fanout / swarm-review gating
- `state-init.ps1` + `state-gate.ps1` - gate marking and blocking
- lean-loop workflow defaults - per-surface checks for `/build`, `/goal`,
  generated Copilot/OpenCode prompts, Kilo removal, and lifecycle gates
- `pre-session.ps1` - temp-repo behavior proving index-led startup without
  eager handoff/history reads
- focused installers - temp-home smoke checks for Codex, Copilot CLI, and
  OpenCode
- `specialist-memory-resolver.ps1` - repo context patterns plus opt-in legacy
  role memory injection
- `reflect-trigger.ps1` - manual reflection backlog status and exit codes

## What's Not Covered

- Playwright runner - needs a live dev server; covered manually
- Visual diff - depends on ImageMagick/pixelmatch availability
- Full post-session ceremony - broad state surface; smoke-test the load-bearing
  pieces and lifecycle gates instead

## Adding Tests

The suite sets `$env:AGENTS_HOME` to a temp dir so tests never touch the real
`~/.agents`. Individual `Describe` blocks add narrower setup/cleanup when they
need extra fixture repos.
