---
description: User-typed /redesign entry point. Run UI redesign work through the lean engineering loop on __HOST_NAME__.
---

# /redesign

You are the main Claude Code / OpenCode session. Use visual specialists for UI
judgment, but keep code review and completion on the lean loop.

## Loop

1. Lock the design direction. If no usable direction exists, run
   `aesthetic-director`.
2. Capture current screens when a runnable UI exists.
3. Use `ux-driver` and `ui-driver` for structure and visual critique when the
   task needs design judgment.
4. Implement with `workflow-implementer` unless the edit is a trivial single
   file change.
5. Run fresh build/test/lint and relevant visual checks.
6. Spawn `code-quality-reviewer` for the code diff. It also checks AI slop,
   misplaced files, duplicate logic, weak tests, and maintainability.
7. Spawn `security-reviewer` only if the UI work touches a trust boundary such
   as auth, permissions, untrusted input, external HTTP, DB writes, filesystem
   paths, command execution, payments, or sensitive data exposure.
8. Repair BLOCKING findings and rerun verification + review, max 3 repair
   cycles.

Completion means the requested UI behavior/visual change is present, relevant
checks are green, and no BLOCKING reviewer finding remains.

## Not Default

Do not spawn legacy reviewer or verifier agents as normal `/redesign` gates. Do
not run writeback, reflection, or memory maintenance gates.
