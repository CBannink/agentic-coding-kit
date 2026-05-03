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

- Workflow definitions live at `.kit/workflows/{name}.md`. The kit ships
  3-line override stubs; full skill bodies live under `~/.agents/skills/{name}/`.
- Session state path is `${AGENTS_SESSION_ROOT}` (default `~/.agents/session-state`).
- The legacy `.copilot/session-state` path is no longer written to.

## Hook enforcement (limited on Codex CLI)

Unlike Claude Code (which has `PreToolUse` / `PostToolUse` hooks via
`settings.json`) and OpenCode (which has `tool.execute.before` / `.after`
plugin events), **Codex CLI does not provide a per-tool-call hook surface**.
The kit's protocol-layer enforcement (bash dispatcher, write gateguard,
git-commit-verify gate, auto-record sub-agents, verify-auto-mark) is
NOT available under Codex CLI.

What you do get under Codex CLI:
- Codex's native sandbox / approval mode (`approval_policy = "untrusted"` in
  `~/.codex/config.toml`) — protocol-layer prompt-before-tool-call, but coarser
  than the kit's pattern-matching hooks.
- The kit's prompt-layer rules (always-on block in `~/.codex/AGENTS.md`)
  — descriptive, agent reads and obeys at its discretion.
- Manual lifecycle scripts: `pwsh ~/.agents/tools/pre-session.ps1 ...` at
  session start, `post-session.ps1 ...` at end, `state-gate.ps1 -Mark <gate>`
  as you progress. Agent has to remember to invoke these.

For users who want the kit's full protocol-layer enforcement: switch to
Claude Code or OpenCode for sessions that need it. Use Codex for tasks
where the prompt-layer rules + Codex's own sandbox are sufficient.

Run `pwsh ~/.agents/tools/pre-session.ps1 -Mode <mode> -Task "<task>"` to start
a tracked session. The pre-session script emits a brief you should read before
planning. Run `post-session.ps1` to finalize and register the handoff.
