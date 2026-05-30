# AGENTS.md — Kilo Code Adapter

Kilo Code reads `AGENTS.md` from repo root plus `.kilocode/rules/*.md` files.
Same operating rules as the rest of the kit. See
`bundle/adapters/_shared/AGENT-INSTRUCTIONS.md` for the canonical body.

## Core operating rules

1. Respect the `.codex` layout (`.kit/context/`, `.kit/workflows/`).
2. `.wiki/features.md` + `.wiki/.features` carry user-visible capabilities.
3. Session handoffs are session-private; repo memory is durable.
4. Prefer the sequenced commands: `/plan` → `/build` → `/review` →
   `/analyze` → `/investigate` → `/refactor`. `/redesign` and
   `/security-review` are swarm-eligible.
5. Default sequential. Swarms require parallel-safe verb + fan-out-able scope
   + explicit opt-in.

## Cost-aware orchestration

The main session is the orchestrator. It may read directly relevant files to
classify scope, pick a workflow, and write a precise handoff, but it should not
absorb sustained worker context.

- Any real exploration, pattern search, unfamiliar code mapping, or ownership
  tracing should go to `workflow-explorer` where available.
- Inline coding is for direct answers, commands, and obvious mechanical edits
  across at most 3 files.
- Coding likely to touch more than 3 files, add new files, cross module
  boundaries, or require unfamiliar conventions should use
  `workflow-implementer` or the host's hard implementer variant.
- Long-running implementation, review, and verification should be delegated to
  leaf agents when the harness supports them.

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
