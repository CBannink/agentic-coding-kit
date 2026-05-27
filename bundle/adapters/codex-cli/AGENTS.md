# AGENTS.md — Codex CLI Adapter

This file is read by Codex CLI on session start. Same operating rules apply
across all CLIs that consume this repo. See the shared body for full detail:
`bundle/adapters/_shared/AGENT-INSTRUCTIONS.md` in the kit.

## Core operating rules

1. Respect the `.kit` layout (`.kit/context/`, `.kit/workflows/`).
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

## Hook enforcement (Codex CLI has hooks now)

Codex CLI ships PreToolUse / PostToolUse hooks via `~/.codex/config.toml`
(see https://developers.openai.com/codex/hooks). Same exit-code-2 + reason
contract as Claude Code, same matcher syntax. The kit installs its hook
scripts to fire under Codex automatically when you run `pwsh ./install.ps1
-For codex` (or `-For all`).

What gets enforced under Codex CLI:
- **Bash dispatcher** (PreToolUse, matcher `^Bash$`): dangerous fs ops,
  force-push to main, git-commit-verify gate, test-command tagging
- **Write/Edit gateguard** (PreToolUse, matcher `^apply_patch$`): wiki-
  existence block, first-edit soft-warn (Codex uses `apply_patch` for
  writes; `Write` / `Edit` aren't separate tools)
- **Bash post-verify-mark** (PostToolUse, matcher `^Bash$`): auto-marks
  verification_evidence on test-pass

Coverage caveat (Codex issue #20204, late 2026): hooks fire for Bash,
`apply_patch` (writes), and MCP tools. They do NOT fire for `list_dir`,
`view_image`, `plan`, `goal`, `agent_jobs`, `web_search`. Reads + planning
are silent. Roughly the same enforcement as Claude Code for the events
that matter (write + execute), narrower for read-only + planning events.

The kit also installs:
- Prompt-layer always-on rules in `~/.codex/AGENTS.md`
- Standalone reference doc at `~/.codex/agentic-kit.md`
- Native Codex agents in `~/.codex/agents/*.toml`
- Kit skills in `~/.codex/skills/`
- Non-interactive Codex runtime config in `~/.codex/config.toml`:
  `approval_policy = "never"` and `sandbox_mode = "danger-full-access"`.
  This keeps Codex from asking for permissions in CLI and IDE-backed sessions.

Universal opt-out via `KIT_DISABLED_HOOKS` env var (comma-separated rule
names) — same as Claude / OpenCode.

Codex does not expose the same slash-command surface as Claude/OpenCode, so
workflow routing is prompt/skill/agent based rather than slash-command based.

When the user asks to use a workflow by name, including "build workflow",
"builder workflow", "review workflow", or "goal workflow", that is explicit
permission to use the workflow's normal leaf agents. Do not reinterpret it as
"load the workflow text but keep all work inline." Inline work is only for
single-file mechanical edits or direct answers.

Run `pwsh ~/.agents/tools/pre-session.ps1 -Mode <mode> -Task "<task>"` to start
a tracked session. The pre-session script emits a brief you should read before
planning. Run `post-session.ps1` to finalize and register the handoff.
