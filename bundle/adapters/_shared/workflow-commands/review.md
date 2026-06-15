---
description: User-typed /review entry point. Run the kit's lean unified review on __HOST_NAME__.
---

# /review

You are the main Claude Code / OpenCode session. The user invoked `/review` to
audit a diff or existing code. You coordinate the review directly.

## Phase 1 - Scope

Read `git diff HEAD` or the diff range the user named. Load only the local
context needed to judge the changed behavior and tests.

## Phase 2 - Unified Review

Use `code-quality-reviewer` as the single default reviewer for every normal code
review. It covers correctness, architecture mismatch, over-abstraction,
misplaced files, duplicate logic, AI slop, weak tests, and maintainability
regressions.

Use `security-reviewer` only when the reviewed code crosses a real trust
boundary: auth/authz, secrets, crypto, permissions, untrusted input, external
HTTP, DB writes, filesystem paths, command execution, payments, or sensitive
data exposure.

Do not run multi-pass review, adversarial review, final verification agents, or
writeback/reflection gates by default.

## Phase 3 - False-Positive Check

For each BLOCKING finding, read the cited file and nearby code yourself before
presenting it. Downgrade or remove findings that are already mitigated by the
diff or surrounding code.

## Phase 4 - Synthesis

Return one consolidated review:

- BLOCKING findings first, each with file:line and concrete fix.
- NON-BLOCKING findings next.
- NITS only when they are worth the user's attention.
- Overall verdict in one short paragraph.

## Not Default

Legacy reviewer and verifier agents are not part of default `/review`.
