# Adapters

Per-host adaptation of the kit. Each adapter contains the host-specific
files (instruction file, agents, plugins, hooks) that complement the
shared content under `bundle/global/.agents/`.

The single source of truth for kit rules is
`bundle/global/.agents/global-instructions.md`. Each host's instruction
file holds the canonical kit block between
`<!-- agentic-kit:begin --> ... <!-- agentic-kit:end -->` markers, plus
optional host-specific preamble outside the markers.

`bundle/global/.agents/tools/sync-all-hosts.ps1` orchestrates installation
across all primary hosts in one command.

## Primary hosts (kit targets these first-class)

| Adapter | Status | Instruction file (user-global) | Installer |
|---|---|---|---|
| `claude-code/` | Primary | `~/.claude/CLAUDE.md` | `install-claude-kit.ps1` (shim over `scripts/install.ps1 -For claude`) |
| `codex-cli/` | Primary | `~/.codex/AGENTS.md` | `install-codex-kit.ps1` (agents as TOML, multi_agent flag) |
| `opencode/` | Primary | `~/.config/opencode/AGENTS.md` | `install-opencode-kit.ps1` (shim over `scripts/install.ps1 -For opencode`) |
| `copilot-cli/` | Primary | `~/.copilot/copilot-instructions.md` | `install-copilot-kit.ps1` (shim over `scripts/install.ps1 -For copilot`) |

## Experimental hosts

| Adapter | Status | Notes |
|---|---|---|
| `gemini-cli/` | Experimental | Kit installs but Gemini's auto-delegation is effectively non-functional and mid-flight kit lifecycle does not fire. See `global-instructions.md` §0b for the evidence + GitHub issue references. Re-evaluate every ~2 months as Gemini CLI stabilizes. The `gemini.cmd` shim auto-rolls back the npm install to `0.38.2` if anything bumps it to `0.39+` (those releases have known regressions). |

## Common install flow

From a clean machine:

```powershell
pwsh ~/.agents/tools/sync-all-hosts.ps1 -Force
```

This:
1. Reads `~/.agents/global-instructions.md` (canonical block).
2. For each primary host, runs the host installer to:
   - Sync the canonical block into the host's instruction file via marker
     replacement (preserves any host preamble outside markers).
   - Copy or symlink agent definitions in the host's expected format.
   - Wire host-level hooks where supported (Claude / Gemini / OpenCode /
     Codex).

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
