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
| `claude-code/` | Primary | `~/.claude/CLAUDE.md` | (handled directly by `sync-all-hosts.ps1`; no separate installer) |
| `codex-cli/` | Primary | `~/.codex/AGENTS.md` | `install-codex-kit.ps1` (agents as TOML, multi_agent flag) |
| `opencode/` | Primary | `~/.config/opencode/prompt.md` | `install-opencode-kit.ps1` (frontmatter normalization) |
| `copilot-cli/` | Primary | `~/.copilot/copilot-instructions.md` | `install-copilot-kit.ps1` (no native hooks; workflows self-instrument) |

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
- **Agent files** live as `.md` with YAML frontmatter at the kit's
  canonical location (`bundle/adapters/claude-code/.claude/agents/`).
  Per-host installers translate to host-specific format on install:
  - Claude Code: copy as-is.
  - Gemini CLI / OpenCode: copy or junction `.md` files; OpenCode
    normalizes frontmatter (drops `tools:`, unquotes description).
  - Codex CLI: convert to `.toml` (`name`, `description`,
    `developer_instructions` body).
  - Copilot CLI: no native subagent system; agent prompts are referenced
    inside skill bodies instead.
- **No machine-generated content** lives in adapter dirs. If a file is
  output of an installer, it goes in the user's host config dir, not in
  the repo.
