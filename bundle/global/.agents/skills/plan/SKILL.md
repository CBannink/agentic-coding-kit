---
name: plan
description: Use when the user asks to plan, spec, design, or scope a change. Runs clarify, explore, pressure-test, produce plan artifact, stop for approval.  
---

# /plan

Execute these phases in order. The output is a written plan artifact saved to the session directory. Do NOT implement — stop for user approval after Phase 4.

## Phase 1 — Clarify

Restate the request in your own words. Identify 2-3 clarifying questions that would change the approach if answered differently. Ask the smallest set — cap at 1 round, then document assumptions and proceed.

## Phase 2 — Exploration

Spawn `workflow-explorer` with the request, the clarified scope, and 3-8 likely files. Ask it to: list relevant files, ownership, integration points, existing patterns to copy, and risks. Read its synthesis.

If the task touches shared types, public API surfaces, or cross-module contracts, also spawn `modularity-expert` to map blast radius.

## Phase 3 — Pressure-test (optional, skip for trivial plans)

If the plan has tradeoffs (architecture choice, which approach, risk of regression), spawn `workflow-skeptic` with the explorer synthesis and request. Ask it to challenge assumptions and surface hidden failure modes.

## Phase 4 — Write plan artifact

Write a plan to the session path: `${AGENTS_SESSION_ROOT}/{sessionId}/plan.md` (or `.kit/session-state/{sessionId}/plan.md` in a bootstrapped repo).

Include:
- Objective (one sentence)
- Approach (concrete: what files, what pattern, what API/method)
- Files to modify (exact paths)
- What NOT to change (files/services out of scope)
- Risks and mitigations
- Verification command

## Phase 5 — Stop for approval

Present the plan to the user. Ask for approval before any implementation begins. Do NOT proceed to implementation unless the user says go or explicitly routes to `/build`.
