# File Layout

## Source repository

```text
core/
  manifest.yaml
  orchestrator.md
  opencode-primary.md
  agents/
  skills/
  schemas/
packs/
  ui/
cli/
  src/
  tests/
adapters/
scripts/
benchmarks/
```

- Edit `core/` and `packs/` as canonical prompt sources.
- Edit `cli/src/` for management behavior and `cli/tests/` for durable
  behavioral coverage.
- Regenerate `adapters/`; never edit them as source.
- Treat `bundle/` and old `.kit` material as legacy unless a current release
  path explicitly proves otherwise.

## Installed host surfaces

| Host | User agents | User skills | ACK primary policy |
|---|---|---|---|
| Codex | `~/.codex/agents/` | `~/.agents/skills/` | `developer_instructions` in `~/.codex/config.toml` |
| Claude Code | `~/.claude/agents/` | `~/.claude/skills/` | managed `CLAUDE.md` block |
| OpenCode | `~/.config/opencode/agents/` | `~/.config/opencode/skills/` | `agents/agentic-kit.md` |
| Copilot CLI | `~/.copilot/agents/` | `~/.copilot/skills/` | managed Copilot instruction file |

Project-specific agent and skill directories use each host's native locations.
OpenCode also receives `agents/agentic-kit.md` as a managed primary. ACK leaves
Codex and OpenCode `AGENTS.md` files untouched; repositories may still provide
their own native instructions independently.

## Repository knowledge

Explicit wiki init/reinit creates:

```text
.wiki/
  index.md
  repository-map.md
  engineering.md
  coding.md
  reviewing.md
  testing.md
  security.md
```

`.wiki` is source-backed repository navigation and coding guidance. It is not
session state, reflection, task history, or a feature-memory database. The
primary writes these pages directly with ordinary host file tools; no CLI or
temporary `.kit`/`.git` workflow state is required. Reinitialization preserves
unrelated or unclear human files and content, while initialization fills missing
required pages without replacing existing work.
