---
description: User-typed /build entry point. Run the kit's lean implementation loop on __HOST_NAME__.
---

# /build

You are the main Claude Code / OpenCode session. The user invoked `/build`
because they want code changed. You are the orchestrator for this session; use
leaf agents only when the phase below calls for them.

Default loop:

1. Load minimal indexed context only when needed.
2. Define the expected test set.
3. Implement with the needed tests.
4. Run fresh verification.
5. Run one unified review with `code-quality-reviewer`.
6. Optionally run `security-reviewer` only when the diff crosses a real trust
   boundary.
7. Repair BLOCKING findings and repeat, max 3 repair cycles.

Completion means: requested behavior is done, the meaningful test set covers it
where feasible, tests/build/checks are green, and there is no unhandled
BLOCKING reviewer finding. Handoffs, memory, wiki updates, writeback warnings,
and reflection backlog are not completion gates.

## Router Handoff

If the current session already has a routing handoff, honor it:

- `WORKFLOW_MODE: inline | targeted | full`
- `SCOPE_CLASS: isolated | shared | critical`
- `ROUTING_REASON: <why this mode was chosen>`

If the user invoked `/build` directly and no handoff exists, classify from
`git status` and `git diff --stat HEAD`:

- `isolated`: one module, no shared contract, obvious low-risk edit.
- `shared`: multiple modules or shared workflow/source contracts.
- `critical`: auth, permissions, crypto, schema/data loss, secrets, payments, or
  another trust boundary.

## Phase 1 - Context

Read the smallest useful local context. Prefer `.wiki/index.md` first, then the
smallest relevant architecture, codebase, feature, or principles page it points
to. Spawn `workflow-explorer` only when file ownership, patterns, or call sites
are unclear. Repo-local `.kit/context/patterns.md` is optional focused guidance;
legacy `.kit/context/agent-memory/*.md`, handoffs, and session context are
compatibility/manual surfaces, not startup context.

## Phase 2 - Expected Test Set

Before coding, state the tests that should prove the change:

- unit tests for pure logic
- integration or contract tests for cross-module behavior
- E2E tests for user-visible flows when the repo can run them
- mock data or fixtures for external systems, permissions, and edge cases

If E2E is infeasible, say why and use the nearest integration, contract, or
workflow test that exercises the requested behavior. Do not rely only on green
existing tests when the request changes behavior.

## Phase 3 - Implementation

Inline edits are allowed only for obvious single-file mechanical work. For
multi-file changes, new files, or unfamiliar logic, spawn `workflow-implementer`
with the user request, scoped files, relevant context, expected test set, and
verification command. The implementer should add or update the tests, or explain
why no test change is appropriate.

Do not run a separate slop cleanup agent by default. The unified reviewer owns
AI slop, misplaced files, over-abstraction, duplicate logic, weak tests, and
maintainability regressions.

## Phase 4 - Fresh Verification

Run the project's build/test/lint command directly in the main session and read
the output. Capture the command and exit code in your notes. If verification
fails, fix the failure before review.

Do not spawn a verifier agent. The orchestrator owns fresh verification evidence
directly.

## Phase 5 - Unified Review

Spawn exactly one `code-quality-reviewer` after fresh verification passes.

The reviewer checks correctness bugs, architecture mismatch, over-abstraction,
misplaced files, duplicate logic, AI slop, weak tests, and obvious
maintainability regressions. It also checks whether the expected test set is
real, whether E2E was added or reasonably ruled out, whether mocks/fixtures are
credible, and whether the requested behavior was actually exercised. Findings
must be tagged `BLOCKING`, `NON-BLOCKING`, or `NIT`.

Spawn `security-reviewer` only when the diff touches at least one trust-boundary
trigger:

- auth/authz
- secrets or credentials
- crypto
- permissions
- untrusted input
- external HTTP
- DB writes
- filesystem paths
- command execution
- payments
- sensitive data exposure

Do not spawn other coding reviewers by default.

## Phase 6 - Repair Loop

If review returns BLOCKING findings, send only those deltas back to the
implementer, rerun fresh verification, then rerun `code-quality-reviewer`.
Repeat at most 3 repair cycles for the same task before surfacing a blocker.

Security BLOCKING findings follow the same loop and require fresh verification
after the fix.

## Handoff

Return a concise summary of files changed, behavior delivered, verification
command and result, reviewer outcome, and any remaining non-blocking risks.

## Not Default

Legacy reviewer and verifier agents are compatibility or manual-specialist
tools. They are not part of the default `/build` loop.

Do not run writeback, reflection, memory inbox, prompt-improvement,
compression, proposal, or auto-consolidation tools as build gates.
