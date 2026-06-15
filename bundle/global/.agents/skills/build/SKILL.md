---
name: build
description: "Use when the user asks to implement, fix, refactor, change, add, or modify code. Runs the lean loop: minimal context, expected test set, implement, verify, unified review, repair."
---

# /build

Run the lean implementation loop:

1. Load minimal indexed context only when needed.
2. Define the expected test set.
3. Implement with the needed tests.
4. Run fresh verification.
5. Spawn one `code-quality-reviewer`.
6. Spawn `security-reviewer` only for real trust-boundary risk.
7. Repair BLOCKING findings and repeat, max 3 repair cycles.

Completion means requested behavior is done, the meaningful test set covers it
where feasible, tests/build/checks are green, and there is no unhandled
BLOCKING reviewer finding.

## Context

Prefer `.wiki/index.md` first, then the smallest relevant architecture,
codebase, feature, or principles page it points to. Use `workflow-explorer`
only when file ownership, patterns, or call sites are unclear. Repo-local
`.kit/context/patterns.md` is optional focused guidance; legacy
`.kit/context/agent-memory/*.md`, session handoffs, and memory dumps are opt-in
compatibility context.

## Expected Test Set

Before coding, state the tests that should prove the requested behavior:

- unit tests for pure logic
- integration or contract tests for cross-module behavior
- E2E tests for user-visible flows when the repo can run them
- mock data or fixtures for external systems, permissions, and edge cases

If E2E is infeasible, say why and use the nearest integration, contract, or
workflow test. Do not rely only on green existing tests when behavior changed.
For complex changes, load the `test-strategy` skill on demand and pass its
output to the implementer.

## Implementation

Inline only obvious single-file mechanical edits. Spawn `workflow-implementer`
for multi-file changes, new files, unfamiliar logic, or cross-module work.
Pass the expected test set and require test changes, or a clear explanation for
why no test change is appropriate.

## Verification

Run the project verification command directly and read the output. Do not spawn
legacy verifier agents; the orchestrator owns fresh verification evidence.
Use `verification-before-completion` as an on-demand checklist when verification
freshness is unclear.

## Review

After verification passes, spawn `code-quality-reviewer`. It checks correctness,
architecture mismatch, over-abstraction, misplaced files, duplicate logic, AI
slop, weak tests, maintainability regressions, test-set adequacy, E2E
feasibility, mock/fixture realism, and whether the requested behavior was
actually exercised.

Spawn `security-reviewer` only if the diff touches auth/authz, secrets, crypto,
permissions, untrusted input, external HTTP, DB writes, filesystem paths,
command execution, payments, or sensitive data exposure.

Do not run writeback, reflection, memory inbox, prompt improvement, compression,
or auto-consolidation as build gates.
