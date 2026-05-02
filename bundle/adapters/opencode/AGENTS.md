# AGENTS.md — OpenCode Adapter

OpenCode reads `AGENTS.md` from repo root automatically. Same operating
rules as the rest of the kit. See `bundle/adapters/_shared/AGENT-INSTRUCTIONS.md`
for the canonical body.

## Core operating rules

1. Respect the `.codex` layout (`.kit/context/`, `.kit/workflows/`).
2. `.wiki/features.md` + `.wiki/.features` carry user-visible capabilities.
3. Session handoffs are session-private; repo memory is durable.
4. Prefer the sequenced commands: `/plan` → `/build` → `/review` →
   `/analyze` → `/investigate` → `/refactor`. `/redesign` and
   `/security-review` are swarm-eligible.
5. Default sequential. Swarms require parallel-safe verb + fan-out-able
   scope + explicit opt-in (`--swarm` or task containing "swarm").

## OpenCode-specific notes

- OpenCode honors AGENTS.md as the primary system prompt and supports
  per-agent overrides via `.opencode/agent/{name}.md`.
- Plugin hooks live in `.opencode/plugins/` and can wire `pre-session.ps1` /
  `post-session.ps1` automatically — see `.opencode/plugins/agentic-kit.ts`
  in this adapter for the lifecycle plugin.
- Session state path is `${AGENTS_SESSION_ROOT}` (default `~/.agents/session-state`).
- Provider-agnostic: works with Kimi K2, Anthropic, OpenAI, or any
  OpenAI-compatible endpoint. The kit doesn't care which model — the harness
  rules are the same.

## Memory routing

| Bucket | Target |
|---|---|
| Durable repo facts | `.kit/context/memory.md` |
| Repo-local specialist guidance | `.kit/context/agent-memory/{role}.md` |
| Cross-repo skill patterns | `~/.agents/skills/{skill}/memory.md` |
| Session-only | `${AGENTS_SESSION_ROOT}/{id}/handoffs.md` |

## Lifecycle

If you have not installed the OpenCode plugin (`.opencode/plugins/agentic-kit.ts`),
run lifecycle manually:

```
pwsh ~/.agents/tools/pre-session.ps1 -Mode build -Task "..."
# ... do work ...
pwsh ~/.agents/tools/post-session.ps1 -SessionId "..."
```

With the plugin installed, OpenCode invokes these automatically on session
start / end / subagent stop.
