<!--
  CANONICAL kit content. Source of truth: ~/.agents/global-instructions.md
  Synced into Claude / Gemini / Codex / OpenCode by ~/.agents/tools/sync-all-hosts.ps1
  and the install-*-kit.ps1 helpers. Each writer wraps this content with
  <!-- agentic-kit:begin --> / <!-- agentic-kit:end --> markers at write time --
  the markers are NOT embedded here, to avoid nested-marker corruption.
  DO NOT edit this block in the host file directly -- edit the canonical and re-sync.
  Long-form reference (full agent matrix, lifecycle scripts, memory routing,
  scope/tier classification) lives at <host_root>/agentic-kit.md. Read that
  on demand; this file stays terse so per-session context cost is bounded.
-->

# CASPAR BANNINK AGENTIC CODING KIT — GLOBAL RULES

## Routing

The kit ships orchestrator subagents. Claude Code routes to them via
description-matching when the user's request matches one of these surfaces:

| Intent | Subagent that fires |
|---|---|
| Build / implement / fix / refactor / change code | `build-orchestrator` |
| Review / audit / check quality / find bugs | `review-orchestrator` |
| Debug / diagnose / root-cause / investigate | `investigate-orchestrator` |
| Plan / spec / design / scope a change | `plan-orchestrator` |
| Refactor / restructure / consolidate / clean up | `refactor-orchestrator` |
| Greenfield UI / multi-component visual redesign | `redesign-orchestrator` |
| Security audit / pentest / vuln scan | `security-review-orchestrator` |

Each orchestrator's body delegates to specialist subagents
(`code-quality-reviewer`, `security-reviewer`, `modularity-expert`,
`workflow-implementer`, `workflow-explorer`, `final-verifier`, etc.) via
the Task tool. Orchestrators do NOT make Edit/Write calls themselves.

You can also invoke a specialist directly:
- `MUST BE USED for code review` → `code-quality-reviewer` fires.
- `MUST BE USED for security audit` → `security-reviewer` fires.
- (See each agent's `description:` for the full set of triggers.)

## Iron Law

**No completion claims without fresh verification evidence.**
Run the test, read the output, then claim. "Should work" / "looks correct"
/ "probably passes" are forbidden. The session-end hook enforces this:
marking a workflow complete without recording fresh test/build/lint exit
codes via `workflow-evidence.ps1 -AddVerification -WithExitCode 0
-WithCommand <cmd>` will block the stop. Override only with
`KIT_IRON_LAW_OFF=1` in genuine emergencies.

## Writeback gate

Before claiming completion on any task that shipped user-visible changes
(routes, components, public exports, env vars, schema migrations), run:

```powershell
pwsh ~/.agents/tools/verify-writeback.ps1 -SessionId "{session_id}"
```

Output ends with `OK writeback:` (proceed) or `WARN NO WRITEBACK -- ...`
(either update `.wiki/features.md` / `.kit/context/memory.md` and re-run,
or include the warning in your final response so the user sees the gap).

## Session lifecycle (auto on hooked hosts)

| When | Script |
|---|---|
| Session start | `state-init.ps1` |
| Each subagent spawn | `state-gate.ps1 -AddAgent` + `workflow-evidence.ps1 -AddAgent` |
| Session end | `post-session.ps1` |

On hosts without native hooks (Copilot CLI), the orchestrator subagents
call these scripts inline as part of their phase pipelines.

## Repo wins on conflict

If a repo has its own pipeline (`hand_off.md`, `agents/handoffs/`,
project-scoped `.claude/agents/`, etc.), follow it. The kit augments;
it does not replace. Opt out per-repo by adding
`<!-- agentic-kit:disable-lifecycle -->` to its `CLAUDE.md` / `AGENTS.md`.

## Long-form reference

Full agent matrix, scope/tier classification, swarm gating, frontend
visual gate, memory architecture, and self-improvement loop:
`<host_root>/agentic-kit.md` (mirrored to each host as
`~/.claude/agentic-kit.md`, `~/.codex/agentic-kit.md`, etc.).
