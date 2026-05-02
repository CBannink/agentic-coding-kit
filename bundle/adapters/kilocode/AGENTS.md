# AGENTS.md — Kilo Code Adapter

Kilo Code reads `AGENTS.md` from repo root plus `.kilocode/rules/*.md` files.
Same operating rules as the rest of the kit. See
`bundle/adapters/_shared/AGENT-INSTRUCTIONS.md` for the canonical body.

## Core operating rules

1. Respect the `.codex` layout (`.codex/context/`, `.codex/workflows/`).
2. `.wiki/features.md` + `.wiki/.features` carry user-visible capabilities.
3. Session handoffs are session-private; repo memory is durable.
4. Prefer the sequenced commands: `/plan` → `/build` → `/review` →
   `/analyze` → `/investigate` → `/refactor`. `/redesign` and
   `/security-review` are swarm-eligible.
5. Default sequential. Swarms require parallel-safe verb + fan-out-able scope
   + explicit opt-in.

## Kilo Code-specific notes

- Custom modes live in `.kilocode/rules/` — one .md file per mode. The
  adapter ships per-command rule files so Kilo Code surfaces `/plan`,
  `/build`, `/review`, `/redesign`, `/security-review` as native modes.
- Kilo Code supports MCP servers; the kit's tool scripts can be exposed
  via the optional `agentic-kit-mcp` server (not shipped — wire your own
  if you want MCP-based tool calls).
- Provider-agnostic: works with Kimi K2, Anthropic, OpenAI, OpenRouter,
  any OpenAI-compatible endpoint.

## Lifecycle

Kilo Code (VSCode extension) doesn't expose explicit session-end hooks
the way OpenCode does. Run lifecycle manually OR wire it via tasks.json:

```
pwsh ~/.agents/tools/pre-session.ps1 -Mode build -Task "..."
# ... work in Kilo Code ...
pwsh ~/.agents/tools/post-session.ps1 -SessionId "..."
```

For more automation, add a VSCode `tasks.json` entry that runs post-session
when you trigger "End Agentic Session" from the command palette.
