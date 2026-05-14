---
name: refactor
description: User-typed /refactor entry point for Copilot CLI. Runs inline in the current session, prints visible phase progress, and spawns only leaf agents. MUST BE USED when the user types `/refactor` or asks for behavior-preserving restructuring.
---

# /refactor (Copilot CLI inline)

For Copilot CLI, keep `/refactor` in the current session and use the loaded
Copilot instructions as the workflow contract:

- repo override: `.github/copilot-instructions.md` when present
- otherwise: `~/.copilot/copilot-instructions.md`

## Rules

- Do NOT spawn `refactor-orchestrator`.
- Emit visible phase lines before every leaf-agent spawn.
- Spawn only leaf agents (`workflow-explorer`, `workflow-implementer`,
  `code-quality-reviewer`, `modularity-expert`, `final-verifier`).
- Keep `kit-refactor.(ps1|sh)` wrappers and direct `copilot --agent ...` calls
  as explicit fallback entrypoints, not the default slash path.

## Minimum fallback if the matching `/refactor` section is unavailable

1. Lock the refactor principle.
2. Map call sites and public surfaces with `workflow-explorer`.
3. Implement with explicit behavior-equivalence constraints.
4. Review for semantic drift and modularity.
5. Verify equivalence before handoff.
