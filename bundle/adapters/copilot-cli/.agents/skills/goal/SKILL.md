---
name: goal
description: User-typed /goal entry point for Copilot CLI. Runs inline in the current session, prints visible phase progress, and spawns only leaf agents. MUST BE USED when the user types `/goal` or says 'achieve this autonomously', 'drive this to completion', or 'iterate until done'.
---

# /goal (Copilot CLI inline)

For Copilot CLI, the current session is the goal orchestrator. Stay in this
session, keep the user-visible phase output, and use the loaded Copilot
instructions as the primary workflow contract:

- repo override: `.github/copilot-instructions.md` when present
- otherwise: `~/.copilot/copilot-instructions.md`

## Rules

- Do NOT spawn `goal-orchestrator`.
- Emit visible phase lines before every leaf-agent spawn.
- Spawn only leaf agents (`workflow-explorer`, `workflow-implementer`,
  reviewers, `final-verifier`, `ux-driver`, `ui-driver`, etc.).
- Keep `kit-goal.(ps1|sh)` wrappers and direct `copilot --agent ...` calls as
  explicit fallback entrypoints, not the default slash path.

## Minimum fallback if the matching `/goal` section is unavailable

1. Triage obvious single-edit work to `/build` inline.
2. Classify goal type and restate the goal with success criteria.
3. Run recon with `workflow-explorer` only if needed.
4. Iterate with `workflow-implementer`, inline verification, and targeted
   reviewers until converged or capped.
5. Finish with `final-verifier` and a concise handoff.
