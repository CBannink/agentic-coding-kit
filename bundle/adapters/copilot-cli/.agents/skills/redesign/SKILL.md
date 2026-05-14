---
name: redesign
description: User-typed /redesign entry point for Copilot CLI. Runs inline in the current session, prints visible phase progress, and spawns only leaf agents. MUST BE USED when the user types `/redesign` or asks for multi-component UI redesign.
---

# /redesign (Copilot CLI inline)

For Copilot CLI, the current session owns `/redesign`. Stay inline and use the
loaded Copilot instructions as the workflow contract:

- repo override: `.github/copilot-instructions.md` when present
- otherwise: `~/.copilot/copilot-instructions.md`

## Rules

- Do NOT spawn `redesign-orchestrator`.
- Emit visible phase lines before every leaf-agent spawn.
- Spawn only leaf agents (`playwright-navigator`, `workflow-implementer`,
  `ux-driver`, `ui-driver`, `final-verifier` or visual-diff helpers when the
  workflow calls for them).
- Keep `kit-redesign.(ps1|sh)` wrappers and direct `copilot --agent ...` calls
  as explicit fallback entrypoints, not the default slash path.

## Minimum fallback if the matching `/redesign` section is unavailable

1. Lock the aesthetic direction.
2. Capture current state.
3. Use `ux-driver` before `ui-driver`.
4. Implement from the consolidated design contract.
5. Run visual diff / regression checks before handoff.
