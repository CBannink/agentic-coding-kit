# AGENTS.md — Codex CLI Adapter

This file is read by Codex CLI on session start. Same operating rules apply
across all CLIs that consume this repo. See the shared body for full detail:
`bundle/adapters/_shared/AGENT-INSTRUCTIONS.md` in the kit.

## Core operating rules

1. Respect the `.codex` layout (`.codex/context/`, `.codex/workflows/`).
2. Use `.wiki/features.md` and `.wiki/.features` for user-visible capabilities.
3. Session handoffs are session-private; repo memory is durable.
4. Prefer the sequenced commands: `/plan` → `/build` → `/review` → `/analyze`
   → `/investigate` → `/refactor`. Use `/redesign` and `/security-review` for
   the swarm-eligible cases.
5. Default to sequential execution. Swarms require: parallel-safe verb +
   fan-out-able scope + explicit user opt-in.

## Codex CLI-specific notes

- Workflow definitions live at `.codex/workflows/{name}.md`. The kit ships
  3-line override stubs; full skill bodies live under `~/.agents/skills/{name}/`.
- Session state path is `${AGENTS_SESSION_ROOT}` (default `~/.agents/session-state`).
- The legacy `.copilot/session-state` path is no longer written to.

Run `pwsh ~/.agents/tools/pre-session.ps1 -Mode <mode> -Task "<task>"` to start
a tracked session. The pre-session script emits a brief you should read before
planning. Run `post-session.ps1` to finalize and register the handoff.
