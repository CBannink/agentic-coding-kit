# Adapters

Per-host adaptation of the kit. Each adapter contains the host-specific
files (instruction file, agents, plugins, hooks) that complement the
shared content under `bundle/global/.agents/`.

The single source of truth for kit rules is
`bundle/global/.agents/global-instructions.md`. Each host's instruction
file holds the canonical kit block between
`<!-- agentic-kit:begin --> ... <!-- agentic-kit:end -->` markers, plus
optional host-specific preamble outside the markers.

The recommended install path is one dedicated script per primary host. The
shared `scripts/install.ps1` backend remains available for intentional
multi-host installs.

## Primary hosts (kit targets these first-class)

| Adapter | Status | Instruction file (user-global) | Installer |
|---|---|---|---|
| `claude-code/` | Primary | `~/.claude/CLAUDE.md` | `scripts/install-claude.ps1` |
| `codex-cli/` | Primary | `~/.codex/AGENTS.md` | `scripts/install-codex.ps1` |
| `opencode/` | Primary | `~/.config/opencode/AGENTS.md` | `scripts/install-opencode.ps1` |
| `copilot-cli/` | Primary | `~/.copilot/copilot-instructions.md` | `scripts/install-copilot.ps1` |

## Experimental hosts

| Adapter | Status | Notes |
|---|---|---|
| `gemini-cli/` | Experimental | Kit installs but Gemini's auto-delegation is effectively non-functional and mid-flight kit lifecycle does not fire. See `global-instructions.md` §0b for the evidence + GitHub issue references. Re-evaluate every ~2 months as Gemini CLI stabilizes. The `gemini.cmd` shim auto-rolls back the npm install to `0.38.2` if anything bumps it to `0.39+` (those releases have known regressions). |

## Common install flow

From a clean machine:

```powershell
pwsh .\scripts\install-codex.ps1
pwsh .\scripts\install-copilot.ps1
pwsh .\scripts\install-claude.ps1
pwsh .\scripts\install-opencode.ps1
```

Each dedicated script pins one host and delegates to `scripts/install.ps1` with
the matching `-For` value. Use the shared backend only when you intentionally
want a multi-host install, for example
`pwsh .\scripts\install.ps1 -For "codex,copilot"`.

## Adapter conventions

- **Instruction file lives in the adapter dir** so it can be diffed and
  reviewed; the installer renders + injects it into the user's host
  config dir on install.
- **Shared workflow transport assets** (Claude/OpenCode command wrappers +
  `workflow-*` agents) live once under
  `bundle/adapters/_shared/{workflow-commands,workflow-agents}/` and are
  rendered into host-native dirs by the installer.
- **Shared specialist agents** now live once under
  `bundle/adapters/_shared/specialist-agents/` and are converted/sanitized per
  host at install time.
- **Host-specific agent files** stay in adapter dirs only when they are truly
  single-host surfaces (for example OpenCode's primary `orchestrator.md`).
- **Primary orchestrator agent** is rendered once from
  `_shared/orchestrator/primary-agent.template.md` into each host's native agent
  location: Claude `.md`, OpenCode primary `.md`, Copilot `.agent.md`, and
  Codex `.toml`.
- Per-host installers translate to host-specific format on install:
  - Claude Code: copy shared specialist agents as-is and render shared workflow
    markdown into `~/.claude/...`.
  - OpenCode: sanitize shared workflow + specialist markdown into
    `~/.config/opencode/...`, then overlay OpenCode-only primary-agent files and
    normalize plugin payloads.
  - Copilot CLI: convert shared workflow + specialist markdown into `.agent.md`
    files at install time.
  - Codex CLI: convert to `.toml` (`name`, `description`,
    `developer_instructions` body).
  - Copilot CLI: install custom agents natively, but user-defined slash
    commands are still unsupported; workflows compose via shell wrappers in
    `~/.agents/bin/copilot/` and direct `copilot --agent <name> -p ...`
    calls.
- **No machine-generated content** lives in adapter dirs. If a file is
  output of an installer, it goes in the user's host config dir, not in
  the repo.
