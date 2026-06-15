# Setup and Install Guide

This is the shortest reliable path to get the kit working across all supported
CLI adapters.

## 1. Machine install

From the kit repo, install for your preferred CLI:

```powershell
# Claude Code (recommended — fullest hook integration)
pwsh ./scripts/install-claude.ps1

# GitHub Copilot CLI
pwsh ./scripts/install-copilot.ps1

# OpenCode
pwsh ./scripts/install-opencode.ps1

# Codex
pwsh ./scripts/install-codex.ps1

# Multiple CLIs at once
pwsh ./scripts/install.ps1 -For "claude,copilot"

# All supported CLIs
pwsh ./scripts/install.ps1 -For all

# Verify
pwsh ./scripts/doctor.ps1
```

## 2. Reinstall safely

If you want a clean refresh after updating this repo:

```powershell
pwsh ./scripts/install-copilot.ps1 -Force
pwsh ./scripts/doctor.ps1
```

Normal reinstalls preserve:
- session state
- reflections / handoffs
- accumulated cross-repo skill memory

## 3. Per-repo setup

### New repo or repo that is not bootstrapped yet

```powershell
pwsh ~/.agents/bin/copilot/kit-bootstrap.ps1 "C:\path\to\repo"
```

That one command handles:
- scaffold
- git-archaeology
- kit-init
- wiki-init

### Existing repo that already has agent rules

1. Do the machine install first.
2. Install the repo-local Copilot surface:

```powershell
pwsh ./scripts/install-copilot.ps1 -TargetRepo C:\path\to\repo -InstallRepoTemplate
```

3. Open the repo in your preferred host.
4. Run `/kit-migrate` if the repo already has a competing pipeline.

## 4. Daily usage

### Claude Code

```
/build "add JWT auth"
/review
/goal "achieve this autonomously: ..."
```

### GitHub Copilot CLI

```powershell
pwsh ~/.agents/bin/copilot/kit-build.ps1 "add JWT auth"
pwsh ~/.agents/bin/copilot/kit-plan.ps1 "<request>"
pwsh ~/.agents/bin/copilot/kit-review.ps1 "<request>"
pwsh ~/.agents/bin/copilot/kit-goal.ps1 "achieve this autonomously: ..."
```

On current Copilot CLI builds, the same install also exposes inherited skills
from `~/.agents/skills/`. That means `/skills` can list `goal`, `build`,
`investigate`, `analyze`, `gstack-*`, `test-strategy`,
`silent-failure-hunter`, `verification-before-completion`, `skill-import`, and
similar kit skills directly. The Copilot-specific slash entry skills are
installed to keep orchestration inline in the main session and only spawn leaf
agents; the wrapper commands above remain the explicit fallback path.

If the repo has a per-repo Copilot adapter installed, prefer:

```powershell
pwsh .github\copilot-bin\kit-build.ps1 "<request>"
```

### OpenCode

```
/build "add JWT auth"
/review
/goal "achieve this autonomously: ..."
```

OpenCode receives host-native skills at `~/.config/opencode/skills/`. Slash
commands map to those installed global skill files.

## 5. Quick repo checklist

For a repo to be fully ready, expect:

- `.kit/context/patterns.md`
- `.kit/context/conventions.md`
- `.wiki/index.md`
- `.wiki/features.md`
- `.github/copilot-instructions.md` (optional but recommended for repo-specific override)
- `.github/agents/` and `.github/hooks/` when the Copilot adapter is installed per repo

> **Note**: The `.kit/` directory is the canonical location for all kit
> artifacts. Do not use `.codex/` — that path is no longer supported.

## 6. If something looks off

Run:

```powershell
pwsh ./scripts/doctor.ps1
Invoke-Pester ./tests/Pester/
```

Then check:
- is `~/.agents/bin/copilot/` populated?
- did `~/.copilot/copilot-instructions.md` get rewritten?
- is the repo actually bootstrapped, or only globally installed?
