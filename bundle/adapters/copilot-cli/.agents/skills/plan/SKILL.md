---
name: plan
description: User-typed /plan entry point for Copilot CLI. Runs inline in the current session, prints visible phase progress, and avoids top-level orchestrator delegation. MUST BE USED when the user types `/plan` or asks to plan, scope, or pressure-test a change.
---

# /plan (Copilot CLI inline)

For Copilot CLI, keep `/plan` in the current session. Copilot ships a built-in
`/plan` command, but when this inherited skill is active the current session
should still stay inline rather than spawning `plan-orchestrator`.

## Rules

- Do NOT spawn `plan-orchestrator`.
- Emit visible phase lines before every leaf-agent spawn.
- Spawn only leaf agents (`workflow-explorer`, `workflow-skeptic`,
  `modularity-expert`) when the plan needs outside pressure.
- Keep `kit-plan.(ps1|sh)` wrappers and direct `copilot --agent ...` calls as
  explicit fallback entrypoints, not the default slash path.

## Minimum inline plan flow

1. Clarify the request and success boundary.
2. Explore the relevant files and blast radius.
3. Pressure-test the plan with one skeptic/reviewer only when needed.
4. Write or update the session `plan.md`.
5. Stop for approval instead of implementing.
