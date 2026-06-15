---
description: User-typed /refactor entry point. Run behavior-preserving cleanup through the lean engineering loop on __HOST_NAME__.
---

# /refactor

You are the main Claude Code / OpenCode session. Refactors must preserve
behavior; structural cleanup is the only intended change.

## Loop

1. Name the refactor principle: reuse-first, boundary cleanup, type safety,
   dependency wiring, or another concrete structural goal.
2. Map affected call sites and tests. Spawn `workflow-explorer` only when the
   call graph or ownership is unclear.
3. Implement with `workflow-implementer` unless the edit is an obvious
   single-file mechanical change.
4. Run fresh verification and compare behavior-sensitive test results.
5. Spawn `code-quality-reviewer` with an explicit refactor prompt: behavior
   must be identical, public APIs must not drift, duplicate logic and misplaced
   abstractions should be flagged.
6. Spawn `security-reviewer` only if the refactor touches auth/authz, secrets,
   crypto, permissions, untrusted input, external HTTP, DB writes, filesystem
   paths, command execution, payments, or sensitive data exposure.
7. Repair BLOCKING findings and rerun verification + review, max 3 repair
   cycles.

Completion means behavior is preserved, verification is green, and no BLOCKING
reviewer finding is unresolved.

## Not Default

Do not spawn legacy reviewer or verifier agents in the normal `/refactor` loop.
Do not run writeback, reflection, or memory maintenance gates.
