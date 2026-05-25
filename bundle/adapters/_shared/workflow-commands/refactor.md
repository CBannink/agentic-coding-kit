---
description: User-typed /refactor entry point. Run the kit's phased pipeline for this workflow on __HOST_NAME__. Main session orchestrates, decides mode, and spawns only leaf agents via the Task tool.
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

## Simplification policy (revised — fewer spawns by default)

For ISOLATED scope (Phase 0 classified):
- Phase 1 explorer: SKIP if codebase small / already understood.
- Phase 3 reviewers: code-quality-reviewer ONLY.
- Phase 4 adversarial: SKIP.
- Phase 5 final-verifier: orchestrator may run the verification command inline + check status itself; spawn final-verifier only if the change crosses module boundaries.
- Min spawns for ISOLATED: 1 (workflow-implementer if multi-file) or 0 (inline edits + inline verify).

For SHARED scope (default for most multi-file changes):
- Phase 1 explorer: spawn IF codebase unfamiliar.
- Phase 2 workflow-implementer: ALWAYS.
- Phase 3 reviewers: code-quality-reviewer ALWAYS. security-reviewer ONLY if auth/external-HTTP/DB-writes/file-paths/permissions touched. modularity-expert ONLY if new files added OR shared types changed OR DI/container wiring changed.
- Phase 4 adversarial: SKIP. (Was previously also SHARED -- now CRITICAL-only.)
- Phase 5 final-verifier: ALWAYS.
- Typical SHARED spawn count: 4 (explorer + implementer + code-quality + final-verifier). +1 if security trigger fires. +1 if modularity trigger fires. Max 6.

For CRITICAL scope (auth, schema migration, breaking change):
- Full pipeline: explorer + implementer + ALL three reviewers (quality + security + modularity) + adversarial + final-verifier = 7 spawns.
- Plus extra fix-loop iterations if reviewers find blocking issues.

Rule of thumb: prefer 1-line inline edits over implementer spawn. Prefer ONE reviewer over THREE unless there's a real reason. Adversarial pass is expensive; reserve it for CRITICAL changes that warrant the cost.