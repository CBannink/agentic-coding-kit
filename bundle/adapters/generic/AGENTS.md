# AGENTS.md — Caspar Bannink Agentic Coding Kit

Canonical agent instructions. Any CLI that reads `AGENTS.md` (Codex, Kimi,
Aider, Cline, Cursor, Continue, etc.) gets the right behavior from this file.

## Core operating rules

1. Respect the `.codex` layout (`.codex/context/`, `.codex/workflows/`).
2. Use `.wiki/features.md` and `.wiki/.features` for user-visible capabilities.
3. Treat session handoffs as session-private; repo memory is durable.
4. Prefer:
   - `/plan` before non-trivial implementation
   - `/build` for execution
   - `/review` for audits
   - `/analyze` for multi-angle synthesis
   - `/investigate` for unknown-cause debugging
   - `/refactor` for principle-driven restructuring
   - `/redesign` for greenfield UI / multi-component visual work (swarm-eligible)
   - `/security-review` for adversarial audits (swarm-eligible)
5. Use role-specific repo memory only through the mechanical resolver:
   `pwsh ~/.agents/tools/specialist-memory-resolver.ps1 -SessionId {id} -Role {role}`
6. Default execution is **sequential**. Swarms only fire when all three hold:
   parallel-safe verb (audit / explore / port / redesign / pentest), fan-out-able
   scope, explicit user opt-in.

## Memory write routing

| Bucket | Target |
|---|---|
| Durable repo facts | `.codex/context/memory.md` |
| Repo-local specialist guidance | `.codex/context/agent-memory/{role}.md` or `shared.md` |
| Cross-repo skill patterns | `~/.agents/skills/{skill}/memory.md` |
| Session-only | `${AGENTS_SESSION_ROOT}/{id}/handoffs.md` (default `~/.agents/session-state`) |

## File layout to respect

```text
.codex/context/
.codex/workflows/
.wiki/
```

## Lifecycle

```
pre-session.ps1 → /plan or /build or … → state-gate enforcement → post-session.ps1
```

- `pre-session.ps1` classifies scope (`ISOLATED` / `SHARED` / `CRITICAL`),
  recommends a tier (`INLINE` / `TARGETED` / `FULL` / `SWARM`), generates a brief.
- `state-gate.ps1` enforces gates and the agent cap.
- `post-session.ps1` is the single owner of handoff registration and evidence.
