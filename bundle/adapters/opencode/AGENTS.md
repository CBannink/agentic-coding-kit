# AGENTS.md — OpenCode Adapter

OpenCode reads `AGENTS.md` from repo root automatically. Same operating
rules as the rest of the kit. See `bundle/adapters/_shared/AGENT-INSTRUCTIONS.md`
for the canonical body.

## Core operating rules

1. Respect the `.kit` layout (`.kit/context/`, `.kit/workflows/`).
2. `.wiki/features.md` + `.wiki/.features` carry user-visible capabilities.
3. Session handoffs are session-private; repo memory is durable.
4. Prefer the sequenced commands: `/plan` → `/build` → `/review` →
   `/analyze` → `/investigate` → `/refactor`. `/redesign` and
   `/security-review` are swarm-eligible.
5. Default sequential. Swarms require parallel-safe verb + fan-out-able
   scope + explicit opt-in (`--swarm` or task containing "swarm").

## Frontend aesthetic direction

Greenfield UI in `/build` or `/redesign` checks for `DESIGN.md` first. If missing, `aesthetic-director` skill runs — proposes 2-3 named directions (Swiss Minimalism, Editorial, Brutalism, Glassmorphism, Dark OLED Luxury, etc.), user picks, locks `DESIGN.md` with typography + OKLCH palette + density + motion + a mandatory **banned-defaults list**. `ux-driver` and `ui-driver` then read this; they refuse to silently substitute generic taste when DESIGN.md is missing. Without it, parallel design agents converge on the same LLM default look. Lightweight alternative: paste a 5-line `<always_use_X_theme>` block into this `AGENTS.md`.

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

## Workflow source of truth

The global workflow skills in `~/.agents/skills/` are the canonical workflow
contract. OpenCode command and agent files are transport layers that should
point back to that shared contract rather than redefining workflow semantics.

## Non-trivial `/build` discipline

When OpenCode has the workflow agents installed, non-trivial `/build` work
should delegate instead of staying inline in the main session.

- one-file mechanical fixes may stay inline
- anything needing more than two source-file reads should delegate exploration
- anything beyond a one-file mechanical edit should delegate implementation
- non-trivial review should delegate reviewer agents when available
- after exploration synthesis, the main session should stop reading source files

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
