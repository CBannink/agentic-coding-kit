---
description: User-typed /refactor entry point. Run the kit's phased pipeline for this workflow on __HOST_NAME__. Main session orchestrates; spawns workflow-explorer / workflow-implementer / specialist agents (code-quality-reviewer, security-reviewer, modularity-expert, final-verifier) via the Task tool per phase. Description-match also routes to the matching refactor-orchestrator subagent if loaded; both paths reach the same leaves.
---

# /refactor

You are the main Claude Code / OpenCode session. The user invoked /refactor because they want to restructure, clean up, enforce conventions. You ARE the orchestrator — no wrapping subagent layer; you read this body and execute the phases yourself, using the **Task tool** to spawn leaf subagents (workflow-explorer, workflow-implementer, code-quality-reviewer, etc.) when phases call for it.

Refactors look like /build but with a different gate: behavior MUST be IDENTICAL after, only structure changes. You ARE the orchestrator.

## Phase 1 — Identify the principle

Confirm with user OR infer: reuse-first / boundary cleanup / type safety / DI rewiring / layered-architecture compliance? State explicitly. Without a named principle, refactors drift into rewrites.

## Phase 2 — Consequence trace

Spawn `workflow-explorer` to map: all call sites of the code being restructured, test files affected, public exports/APIs/types that must NOT change. Refactors fail when call sites are missed.

## Phase 3 — Implementation

Spawn `workflow-implementer` with the call-site map and explicit instruction: "Behavior must be identical. Run the test suite before and after; both must pass with the SAME pass count and coverage."

## Phase 4 — Behavior-equivalence check

Spawn `code-quality-reviewer` with explicit prompt: "This is a REFACTOR. Verify behavior is unchanged. Check: original test cases still asserting? Public APIs untouched? Implementer preserved every error path? Look for accidental simplifications that change semantics."

## Phase 5 — Modularity verification

Spawn `modularity-expert` to confirm the refactor achieved the principle from Phase 1.

## Phase 6 — Iron Law

Spawn `final-verifier` to confirm tests are green AND no source changed after the last test run.

## What NOT to do

- Do NOT add features during a refactor. If the user asks for X (refactor) AND Y (new behavior), surface that and split.
- Do NOT skip Phase 4 behavior-equivalence checks.
## Phase 5b — Mechanical writeback gate (run this, do not skip)

After verification passes, run the writeback gate via Bash:

```
pwsh ~/.agents/tools/verify-writeback.ps1 -SessionId "$CLAUDE_SESSION_ID"
```

Output ends with `OK writeback: ...` (proceed) or `WARN NO WRITEBACK -- ...`. If WARN: either update `.wiki/features.md` / `.kit/context/memory.md` and re-run, OR include the warning in your final response so the user sees the gap. Do NOT silently skip.

## Phase 5c — Reflect trigger (mechanical)

Check `~/.agents/context/reflections.md` length. If 5+ unaddressed entries: spawn the `reflect` skill via the Skill tool (or surface to user "5+ workflow reflections accumulated, recommend running /reflect"). Mechanical, not vibes.

## Simplification policy

For ISOLATED scope (Phase 0 classified) you may compress:
- Phase 1 (explorer): skip if codebase is small / already understood.
- Phase 3 (reviewers): code-quality-reviewer only (skip security + modularity unless triggers fire).
- Phase 4 (adversarial): SKIP entirely.

Min spawns for ISOLATED: 2 (workflow-implementer + final-verifier). Max for SHARED: 7. CRITICAL adds 1-2 more iterations on the fix-loop.