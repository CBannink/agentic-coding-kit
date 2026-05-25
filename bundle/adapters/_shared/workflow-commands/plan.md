---
description: User-typed /plan entry point. Run the kit's phased pipeline for this workflow on __HOST_NAME__. Main session orchestrates, decides mode, and spawns only leaf agents via the Task tool.
---

# /plan

You are the main Claude Code / OpenCode session. The user invoked /plan because they want to plan, spec, design before coding. You ARE the orchestrator — no wrapping subagent layer; you read this body and execute the phases yourself, using the **Task tool** to spawn leaf subagents (workflow-explorer, workflow-implementer, code-quality-reviewer, etc.) when phases call for it.

Produce a plan.md artifact and stop for approval before any code is written. You ARE the orchestrator.

## Router handoff

This workflow is meant to load **after** the top-level router has decided the
task belongs in `/plan`.

If the current session already has a routing handoff, **honor it**:

- `WORKFLOW_MODE: targeted | full`
- `SCOPE_CLASS: isolated | shared | critical`
- `ROUTING_REASON: <why this mode was chosen>`

If the user invoked `/plan` directly and no handoff exists, classify now:

- bounded planning task, few moving parts → `targeted`
- shared interfaces, auth/data risk, or architectural decision → `full`

## Mode contract

| Mode | Meaning | Default shape |
|---|---|---|
| `targeted` | bounded planning with some tradeoff pressure | explorer + optional skeptic |
| `full` | cross-cutting or high-risk planning | explorer + skeptic + modularity/security pressure |

## Phase 1 — Scope clarification

Identify: capability being added/changed, likely files to touch, integration points, constraints. Ask ONE clarifying question if genuinely ambiguous.

## Phase 2 — Repo context

Spawn `workflow-explorer` via Task to map: existing patterns, test conventions, code-style conventions, `.kit/context/memory.md` and `.wiki/index.md` if present.

If `WORKFLOW_MODE=full`, or if the task introduces shared types, public APIs,
or cross-module contracts, also spawn `modularity-expert` to map blast radius.

## Phase 3 — Pressure test (parallel)

Spawn in parallel:
- `workflow-skeptic` — challenge: is this the right problem? Simpler approach? Failure modes? In `full`, run by default.
- `modularity-expert` — only if plan introduces new files / shared types / DI changes, or `WORKFLOW_MODE=full`.
- `security-reviewer` — only if the plan touches auth, user input, secrets, external HTTP, DB writes, or other trust boundaries.

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

## Architectural constraints / blast radius
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
