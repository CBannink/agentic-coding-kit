# Gemini CLI Adapter — Caspar Bannink Agentic Coding Kit

Same operating rules as the rest of the kit; see
`bundle/adapters/_shared/AGENT-INSTRUCTIONS.md` for the canonical body.

This adapter targets Google's official Gemini CLI. The installer is
`~/.agents/tools/install-gemini-kit.ps1`. The kit is wired through Gemini's
hook surface (`SessionStart`, `SessionEnd`, `AfterAgent`, `PreCompress`,
`BeforeTool`, `AfterTool`) using `GEMINI_*` env vars in place of `CLAUDE_*`.

## Core operating rules

1. Respect the `.kit/` layout (`.kit/context/`, `.kit/workflows/`).
2. Use `.wiki/features.md` and `.wiki/.features` for user-visible capabilities.
3. Treat session handoffs as session-private and repo memory as durable.
4. Prefer:
   - `/plan` (or `/kit-plan` if Gemini renamed it for builtin collision) before non-trivial implementation
   - `/build` for execution
   - `/review` for audits
   - `/analyze` for multi-angle synthesis
   - `/investigate` for unknown-cause debugging
   - `/refactor` for principle-driven restructuring
   - `/redesign` for greenfield UI / multi-component visual work (swarm-eligible)
   - `/security-review` for adversarial audits (swarm-eligible)
5. Use role-specific repo memory only through the mechanical resolver path:
   `pwsh ~/.agents/tools/specialist-memory-resolver.ps1 -SessionId {id} -Role {role}`
6. Default execution is **sequential**. Swarms only fire when verb is
   parallel-safe, scope is fan-out-able, and the user opts in.

## Filesystem-truth enforcement (the Iron Law applied to memory)

Gemini CLI sessions historically batched durable-memory writebacks to the very
end of `/build`, creating "context debt" for mid-run subagents. As of
`feat/harness-enforcement-filesystem-truth`, the kit's hooks enforce
filesystem truth:

- `state-gate.ps1 -Mark <protected_gate>` rejects the mark unless the
  corresponding artifact (handoff file, `.kit/context/memory.md`, or
  `workflow-evidence.json` verification array) actually changed during this
  session. Protected gates: `handoff_written`, `implementation_done`,
  `verification_evidence`. Bypass with `-Waiver "<reason>"` (logged).
- `subagent-stop-hook.ps1` (wired to Gemini's `AfterAgent`) compares the
  sha256 of the writeback files against the previous AfterAgent snapshot. If
  nothing changed, a `subagent_no_writebacks` warning is appended to
  `subagent-events.jsonl` and stderr.
- `session-end-hook.ps1` (wired to Gemini's `SessionEnd`) diffs the baseline
  written by `session-start-hook.ps1`. A session that ends with NO durable
  writebacks records a `compliance_violation` to
  `~/.agents/compliance-history.jsonl`. Set `AGENTS_ENFORCEMENT=strict` to
  exit non-zero and have the harness reject the session as failed; default
  is warning-mode so existing flows keep working while you migrate.

These checks live in `bundle/global/.agents/tools/`; they apply to every
adapter, but Gemini exposes the failure mode most clearly because of its
turn-budget pressure and tendency to defer record-keeping.

## Hook event mapping (Claude → Gemini)

| Claude event   | Gemini event   | Purpose                                  |
|----------------|----------------|------------------------------------------|
| SessionStart   | SessionStart   | write baseline.json, init state          |
| SessionEnd     | SessionEnd     | filesystem-truth audit, post-session     |
| SubagentStop   | AfterAgent     | per-subagent writeback diff              |
| Stop           | AfterAgent     | (collapses into AfterAgent on Gemini)    |
| PreCompact     | PreCompress    | precompact-hook.ps1                      |
| PreToolUse     | BeforeTool     | pretool dispatchers                      |
| PostToolUse    | AfterTool      | posttool verifiers                       |

## Known Gemini-specific quirks

1. **`/plan` builtin collision.** Gemini CLI ships its own `/plan`. The
   installer renames the kit's command to `/kit-plan` automatically. Prefer
   the renamed form on Gemini.
2. **Skill duplication.** Both `~/.agents/skills/` and `~/.gemini/skills/` are
   loaded. The installer junctions `~/.gemini/skills` to `~/.claude/skills`
   and the `.agents/` copy auto-loads alongside; you may see "overriding the
   same skill" warnings on startup. Run `~/.agents/tools/dedupe-gemini-kit.ps1`
   to clean up.
3. **`cmd.exe` window flashes.** Gemini spawns child shells without
   `CREATE_NO_WINDOW` on Windows; every hook script causes a brief flash.
   Use Windows Terminal + `pwsh` host to minimize, or set
   `AGENTS_ENFORCEMENT=off` on machines where the flicker is unacceptable
   (loses enforcement).
4. **No first-party `Stop` event.** Subagent-end and session-end overlap on
   `AfterAgent`. The hooks are idempotent so this is safe but produces
   duplicate per-subagent records when a session ends mid-agent.

## File layout to respect

```text
.kit/context/         # repo memory + role memory + handoffs index
.kit/workflows/       # repo-specific workflow overrides
.wiki/                # user-visible feature docs
```

Read the docs in this kit for the full operating model.
