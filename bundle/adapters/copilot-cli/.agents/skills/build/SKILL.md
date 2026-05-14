---
name: build
description: User-typed /build entry point for Copilot CLI. Runs inline in the current session, prints visible phase progress, and spawns only leaf agents. MUST BE USED when the user types `/build` or asks to implement, fix, refactor, change, add, or modify code.
---

# /build (Copilot CLI inline)

For Copilot CLI, the current session owns `/build`. Stay inline and use the
loaded Copilot instructions as the workflow contract:

- repo override: `.github/copilot-instructions.md` when present
- otherwise: `~/.copilot/copilot-instructions.md`

## Rules

- Do NOT spawn `build-orchestrator`.
- Emit visible phase lines before every leaf-agent spawn.
- Spawn only leaf agents (`workflow-explorer`, `workflow-implementer`,
  reviewers, `final-verifier`).
- Keep `kit-build.(ps1|sh)` wrappers and direct `copilot --agent ...` calls as
  explicit fallback entrypoints, not the default slash path.

## Minimum fallback if the matching `/build` section is unavailable

1. Classify scope.
2. Explore only if the codebase is unfamiliar.
3. Implement inline for isolated changes, otherwise use `workflow-implementer`.
4. Run one reviewer by default, add a second only when findings cross lanes.
5. Run verification inline, then `final-verifier`, then hand off.
