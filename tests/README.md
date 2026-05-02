# Tests

Smoke tests for the harness. Not exhaustive — they catch regressions in the
five load-bearing scripts whose correctness everything else depends on.

## Requirements

- **PowerShell 7+ (pwsh)** — the whole kit is designed for pwsh 7+, not
  Windows PowerShell 5.1. Shebangs say `pwsh` and files are UTF-8 without
  BOM (the pwsh default). Windows PowerShell 5.1 will fail on the emoji
  characters (`✅`, `📋`, `⚠`, etc.) used throughout the scripts.
- **Pester 5.0+** — `Install-Module Pester -MinimumVersion 5.0.0 -Scope CurrentUser -Force`

## Run

```powershell
pwsh -NoProfile -Command "Invoke-Pester ./tests/Pester/"
```

## What's covered

- `_paths.ps1` — env-var resolution and `Get-SessionDir` composition
- `scope-classifier.ps1` — ISOLATED / SHARED / CRITICAL routing
- `swarm-classifier.ps1` — sequential / swarm-fanout / swarm-review gating
- `state-init.ps1` + `state-gate.ps1` — gate marking and blocking
- `specialist-memory-resolver.ps1` — shared + role memory injection
- `reflect-trigger.ps1` — reflection backlog status + exit codes

## What's NOT covered

- Playwright runner — needs a live dev server; covered manually
- Visual diff — depends on ImageMagick/pixelmatch availability
- Pre/post-session ceremony — too much state surface; smoke-test the parts they call

## Adding tests

Each Describe block sets up its own `BeforeAll` / `AfterAll` to keep tests
isolated. Tests mutate `$env:AGENTS_HOME` to point at a temp dir so they
never touch the real `~/.agents`.
