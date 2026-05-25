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

## Router-first execution model

The top-level session is the router. Before loading any heavy workflow:

1. **Classify intent** — which workflow owns the request?
2. **Classify scope** — `isolated`, `shared`, or `critical`
3. **Map scope to execution mode**

| Scope | Mode | Default behavior |
|---|---|---|
| `isolated` | `inline` | answer directly or do a one-file mechanical edit |
| `shared` | `targeted` | load the chosen workflow and use the minimal leaf-agent set |
| `critical` | `full` | load the chosen workflow with extra exploration/review pressure |

### Inline path

- Stay in the main session.
- Do **not** load `/build`, `/goal`, or another heavy workflow just to bless a
  trivial change.
- The first edit gate still applies: multi-file or new-file work escalates out
  of inline immediately.

### Workflow path

Load the matching workflow only after routing decides the request is not inline.
Pass the handoff explicitly:

- `WORKFLOW_MODE: targeted | full`
- `SCOPE_CLASS: isolated | shared | critical`
- `ROUTING_REASON: <why this mode was chosen>`

The workflow may escalate its mode with evidence, but it should not re-decide
whether the task belonged inline in the first place unless the user invoked the
workflow directly and no router handoff exists.

### Clarification gate

Before routing into a heavy workflow, decide whether the request is clear enough
to classify safely.

- If ambiguity would materially change **scope**, **workflow choice**,
  **success criteria**, or the **verification command**, ask **one focused
  clarification** first.
- If the ambiguity is minor and does not change execution materially, state the
  assumption and continue.
- Clarification belongs to the **router**, not to `prompt-synthesizer` or the
  downstream worker.

### Direct specialist use

You can still invoke a specialist directly when the request is already narrow:
- code review → `code-quality-reviewer`
- security audit → `security-reviewer`
- architecture / modularity → `modularity-expert`
- focused file discovery → `workflow-explorer`

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

On hosts without native hooks, the active workflow calls these scripts inline as
part of its phase pipeline.

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
