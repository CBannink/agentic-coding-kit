# Claude Code Adapter — Caspar Bannink Agentic Coding Kit

Same operating rules as the rest of the kit; see
`bundle/adapters/_shared/AGENT-INSTRUCTIONS.md` for the canonical body.

## Core operating rules

1. Start from the current request and current code.
2. Do not preload `.kit`, `.wiki`, memory, history, or handoff files.
3. Use `.wiki/index.md` only as an on-demand index when current code is not enough.
4. Prefer:
   - `/plan` before non-trivial implementation
   - `/build` for execution
   - `/review` for audits
   - `/analyze` for multi-angle synthesis
   - `/investigate` for unknown-cause debugging
   - `/refactor` for principle-driven restructuring
   - `/redesign` for greenfield UI / multi-component visual work (swarm-eligible)
   - `/security-review` for adversarial audits (swarm-eligible)
5. Default execution is **sequential**. Swarms only fire when verb is
   parallel-safe, scope is fan-out-able, and the user opts in.

## Command semantics

- `/plan` — clarify, explore, map files, pressure-test, stop for approval
- `/build` — execute approved plan, review, verify
- `/review` — unified review with `code-quality-reviewer`; add `security-reviewer` only for trust-boundary risk
- `/analyze` — multi-angle synthesis
- `/investigate` — root-cause-first debugging
- `/refactor` — principle-driven restructuring
- `/redesign` — multi-component UI work (swarm-eligible). Locks aesthetic via `aesthetic-director` if no `DESIGN.md` exists.
- `/security-review` — adversarial audit (swarm-eligible)

## Frontend aesthetic direction

Greenfield UI work in `/build` or `/redesign` automatically checks for `DESIGN.md`. When absent, the `aesthetic-director` skill runs first — proposes 2-3 named directions, user picks, writes a locked `DESIGN.md` (typography, OKLCH palette, density, motion, banned-defaults list). `ux-driver` and `ui-driver` read this and refuse to silently default. Without a locked direction, parallel design agents converge on the same Inter + purple-gradient + rounded-2xl LLM default. The 5-line shortcut: paste an `<always_use_X_theme>` block into this `CLAUDE.md`.

## Verification freshness

If files change after verification, rerun verification before you claim completion. Do not reuse stale evidence across later edits.

## Claude `/build` execution discipline

For Claude Code, `/build` should normally use the main session as a **coordinator**
and push actual exploration/coding/review into the installed workflow agents.

- If the task needs more than **two source-file reads** to understand, spawn
  `workflow-explorer`.
- If the task changes more than one source file, or anything beyond a one-file
  mechanical fix, spawn `workflow-implementer`.
- Use `code-quality-reviewer` as the single default review pass after fresh
  verification. Add `security-reviewer` only when a real trust boundary is
  present.
- After exploration synthesis, the main session should stop reading source
  files. Downstream reads belong in the delegated subagents.
- If the main session is using an expensive/reasoning-heavy runtime, direct repo-code editing should be
  treated as the exception, not the default.

## File layout to respect

```text
.kit/context/patterns.md # optional focused repo guidance
.kit/workflows/       # repo-specific workflow overrides
.wiki/index.md         # on-demand index into architecture/features/principles
```

Read the docs in this kit for the full operating model.
