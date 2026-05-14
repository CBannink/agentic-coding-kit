---
name: review
description: User-typed /review entry point for Copilot CLI. Runs inline in the current session, prints visible phase progress, and spawns only leaf reviewers. MUST BE USED when the user types `/review` or asks to review, audit, check quality, or find bugs.
---

# /review (Copilot CLI inline)

For Copilot CLI, keep `/review` in the current session and use the loaded
Copilot instructions as the workflow contract:

- repo override: `.github/copilot-instructions.md` when present
- otherwise: `~/.copilot/copilot-instructions.md`

## Rules

- Do NOT spawn `review-orchestrator`.
- Emit visible phase lines before every reviewer spawn.
- Spawn only leaf reviewers (`code-quality-reviewer`, `security-reviewer`,
  `modularity-expert`, optional `final-verifier` if the workflow calls for it).
- Keep `kit-review.(ps1|sh)` wrappers and direct `copilot --agent ...` calls as
  explicit fallback entrypoints, not the default slash path.

## Minimum fallback if the matching `/review` section is unavailable

1. Classify the diff/review scope.
2. Spawn one reviewer by default, a second only for cross-lane findings.
3. Personally verify blocking claims against file:line evidence.
4. Return a single consolidated review.
