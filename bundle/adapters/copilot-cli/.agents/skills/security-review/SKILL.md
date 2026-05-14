---
name: security-review
description: User-typed /security-review entry point for Copilot CLI. Runs inline in the current session, prints visible phase progress, and spawns only leaf agents. MUST BE USED when the user types `/security-review` or asks for a security audit, pentest, or vulnerability review.
---

# /security-review (Copilot CLI inline)

For Copilot CLI, keep `/security-review` in the current session and use the
loaded Copilot instructions as the workflow contract:

- repo override: `.github/copilot-instructions.md` when present
- otherwise: `~/.copilot/copilot-instructions.md`

## Rules

- Do NOT spawn `security-review-orchestrator`.
- Emit visible phase lines before every leaf-agent spawn.
- Spawn only leaf agents (`security-reviewer`, `adversarial-reviewer`,
  `workflow-explorer`, `final-verifier`) that the inline workflow calls for.
- Keep `kit-security-review.(ps1|sh)` wrappers and direct `copilot --agent ...`
  calls as explicit fallback entrypoints, not the default slash path.

## Minimum fallback if the matching `/security-review` section is unavailable

1. Confirm the authorized scope.
2. Fan out only by attack class with leaf reviewers.
3. Verify blocking claims against real evidence.
4. Return a consolidated severity-ranked report.
