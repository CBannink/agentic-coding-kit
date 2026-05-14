---
description: User-typed /plan entry point. Run the kit's phased pipeline for this workflow on __HOST_NAME__. Main session orchestrates; spawns workflow-explorer / workflow-implementer / specialist agents (code-quality-reviewer, security-reviewer, modularity-expert, final-verifier) via the Task tool per phase. Description-match also routes to the matching plan-orchestrator subagent if loaded; both paths reach the same leaves.
---

# /plan

You are the main Claude Code / OpenCode session. The user invoked /plan because they want to plan, spec, design before coding. You ARE the orchestrator — no wrapping subagent layer; you read this body and execute the phases yourself, using the **Task tool** to spawn leaf subagents (workflow-explorer, workflow-implementer, code-quality-reviewer, etc.) when phases call for it.

Produce a plan.md artifact and stop for approval before any code is written. You ARE the orchestrator.

## Phase 1 — Scope clarification

Identify: capability being added/changed, likely files to touch, integration points, constraints. Ask ONE clarifying question if genuinely ambiguous.

## Phase 2 — Repo context

Spawn `workflow-explorer` via Task to map: existing patterns, test conventions, code-style conventions, `.kit/context/memory.md` and `.wiki/index.md` if present.

## Phase 3 — Pressure test (parallel)

Spawn in parallel:
- `workflow-skeptic` — challenge: is this the right problem? Simpler approach? Failure modes?
- `modularity-expert` — only if plan introduces new files / shared types / DI changes.

Aggregate critiques.

## Phase 4 — Plan synthesis

Write to `${AGENTS_SESSION_ROOT}/{session_id}/plan.md` (default `.kit/session-state/{session_id}/plan.md` in a bootstrapped repo):

```markdown
# Plan: <one-line task>

## Goal
<what this delivers and why>

## Approach
<3-5 sentences>

## Files (planned changes)
- `path/to/file1.ts` — <what changes>

## Out of scope
- <what is NOT in this change>

## Verification
- Run: `<test command>`
- Expected: <what should pass>

## Risks / open questions
- <bullet>
```

## Phase 5 — Approval gate

Print plan to user. Ask: "Approve this plan?" STOP. Wait. Do NOT proceed to implementation.

When user approves: update plan.md with `approval_status: approved` and tell them: "Plan approved. Run /build to execute."

## What NOT to do

- Do NOT write code. /plan ends at approval.
- Do NOT skip Phase 3 pressure test for non-trivial features.
- Do NOT auto-invoke /build after approval. The user does that.
## Phase 5c — Reflect trigger (mechanical)

Check `~/.agents/context/reflections.md` length. If 5+ unaddressed entries: spawn the `reflect` skill via the Skill tool (or surface to user "5+ workflow reflections accumulated, recommend running /reflect"). Mechanical, not vibes.
