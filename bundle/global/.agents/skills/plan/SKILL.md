---
name: plan
description: "Use when the user asks to plan, spec, design, or scope a change. Honors router handoff. TARGETED plan: explorer plus pressure test. FULL plan: adds blast-radius and security pressure for high-risk changes. Produces plan artifact and stops for approval."
---

# /plan

Execute these phases in order. The output is a written plan artifact saved to the session directory. Do NOT implement — stop for user approval after Phase 4.

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

## Phase 1 — Clarify

Restate the request in your own words. Identify 2-3 clarifying questions that would change the approach if answered differently. Ask the smallest set — cap at 1 round, then document assumptions and proceed.

## Phase 2 — Exploration

Spawn `workflow-explorer` with the request, the clarified scope, and 3-8 likely files. Ask it to: list relevant files, ownership, integration points, existing patterns to copy, and risks. Read its synthesis.

If `WORKFLOW_MODE=full`, or if the task touches shared types, public API surfaces,
or cross-module contracts, also spawn `modularity-expert` to map blast radius.

## Phase 3 — Pressure-test

Spawn `workflow-skeptic` when the plan has real tradeoffs (architecture choice,
which approach, regression risk). In `WORKFLOW_MODE=full`, run it by default.

If the plan touches auth, user input, secrets, external HTTP, DB writes, or
other trust boundaries, also spawn `security-reviewer` in planning mode to
surface risks the implementation plan must account for.

Aggregate critiques into one planning pressure packet.

## Phase 4 — Write plan artifact

Write a plan to the session path: `${AGENTS_SESSION_ROOT}/{sessionId}/plan.md` (or `.kit/session-state/{sessionId}/plan.md` in a bootstrapped repo).

Include:
- Objective (one sentence)
- Approach (concrete: what files, what pattern, what API/method)
- Files to modify (exact paths)
- What NOT to change (files/services out of scope)
- Risks and mitigations
- Architectural constraints / blast radius
- Verification command

## Phase 5 — Stop for approval

Present the plan to the user. Ask for approval before any implementation begins. Do NOT proceed to implementation unless the user says go or explicitly routes to `/build`.
