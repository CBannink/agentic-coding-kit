# Claude Code Adapter — Caspar Bannink Agentic Coding Kit

Same operating rules as the rest of the kit; see
`bundle/adapters/_shared/AGENT-INSTRUCTIONS.md` for the canonical body.

## Core operating rules

1. Respect the `.kit/` layout (`.kit/context/`, `.kit/workflows/`).
2. Use `.wiki/features.md` and `.wiki/.features` for user-visible capabilities.
3. Treat session handoffs as session-private and repo memory as durable.
4. Prefer:
   - `/plan` before non-trivial implementation
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

## Command semantics

- `/plan` — clarify, explore, map files, pressure-test, stop for approval
- `/build` — execute approved plan, review, verify
- `/review` — hierarchical review (sequential implement, parallel reviewers OK)
- `/analyze` — multi-angle synthesis
- `/investigate` — root-cause-first debugging
- `/refactor` — principle-driven restructuring
- `/redesign` — multi-component UI work (swarm-eligible). Locks aesthetic via `aesthetic-director` if no `DESIGN.md` exists.
- `/security-review` — adversarial audit (swarm-eligible)

## Frontend aesthetic direction

Greenfield UI work in `/build` or `/redesign` automatically checks for `DESIGN.md`. When absent, the `aesthetic-director` skill runs first — proposes 2-3 named directions, user picks, writes a locked `DESIGN.md` (typography, OKLCH palette, density, motion, banned-defaults list). `ux-driver` and `ui-driver` read this and refuse to silently default. Without a locked direction, parallel design agents converge on the same Inter + purple-gradient + rounded-2xl LLM default. The 5-line shortcut: paste an `<always_use_X_theme>` block into this `CLAUDE.md`.

## File layout to respect

```text
.kit/context/         # repo memory + role memory + handoffs index
.kit/workflows/       # repo-specific workflow overrides
.wiki/                  # user-visible feature docs
```

Read the docs in this kit for the full operating model.
