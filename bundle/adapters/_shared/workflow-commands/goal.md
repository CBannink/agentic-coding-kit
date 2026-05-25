---
description: "User-typed /goal entry point. The current session becomes the goal orchestrator, classifies the goal, runs workflow passes, and keeps iterating until the goal is provably achieved. Hard cap: 12 iterations."
---

# /goal

You are the __HOST_NAME__ session acting as goal orchestrator. The user invoked
`/goal` because they want autonomous, end-to-end achievement of a multi-step
goal. The **current session** owns convergence; do NOT spawn another
goal-orchestrator or build-orchestrator.

## Ownership model

The current session owns:

- success criteria
- scope in / out
- iteration count
- approach notes
- convergence judgment

The workflows you route into (`/build`, `/refactor`, `/investigate`,
`/analyze`, `/review`, `/redesign`, `/bootstrap-harness`) are execution
subroutines, not new owners.

## Router handoff

This workflow is meant to load **after** the top-level router has decided the
task belongs in `/goal` rather than staying inline.

If the current session already has a routing handoff, **honor it**:

- `WORKFLOW_MODE: targeted | full`
- `SCOPE_CLASS: isolated | shared | critical`
- `ROUTING_REASON: <why this mode was chosen>`

If the user invoked `/goal` directly and no handoff exists, classify now:

- trivial isolated task -> redirect to `/build`
- normal autonomous goal -> `targeted`
- cross-cutting / risky / ambiguous goal -> `full`

Do **not** spawn another goal orchestrator. `/goal` is already the ownership
layer for this session.

## Mode contract

| Mode | Meaning |
|---|---|
| `targeted` | one primary workflow at a time, minimal extra pressure |
| `full` | optional planning/recon first, then broader iteration pressure |

## Goal type -> workflow routing

| Goal type | Primary workflow |
|---|---|
| **CODE** | `/build` |
| **REFACTOR** | `/refactor` |
| **INVESTIGATION** | `/investigate` |
| **ANALYSIS** | `/analyze` |
| **REVIEW** | `/review` |
| **DESIGN** | `/redesign` |
| **BOOTSTRAP** | `/bootstrap-harness` |
| **MULTI** | sequence two or more of the above explicitly |

## Workflow

### Phase 0 - Triage

- If this is a small obvious execution task, redirect to `/build`.
- Otherwise classify the primary goal type and name the workflow you will use.

Output:

```
GOAL_TYPE: <type> | workflow: </command> | mode: <targeted|full>
```

### Phase 1 - Goal contract

Restate the goal and lock:

- **Success criteria**
- **Scope IN**
- **Scope OUT**
- **Verification command**
- **Assumptions** only when needed

Ask only the smallest clarification that changes workflow choice or success
criteria. If still underspecified after one clarification round, state an
assumption and continue.

### Phase 2 - Prep only when needed

Use prep sparingly:

- run `/plan` only when the approach is unclear or the change is cross-cutting
- run `workflow-explorer` only when the relevant surface is unfamiliar
- in `targeted` mode, prefer at most one prep step before execution
- in `full` mode, use both only when they materially reduce thrash

### Phase 3 - Iterate by workflow pass

For each iteration:

1. Run **one pass** of the chosen workflow.
2. Compare the result against the success criteria.
3. Re-run the verification command when files changed.
4. If the same blocker repeats twice, change approach or add `/plan` if you skipped it.
5. Stop when the criteria are met and verification is green.

Caps:

- soft cap: 6 iterations
- hard cap: 12 iterations

### Phase 4 - Independent check

Before declaring success, run one independent check:

- use `final-verifier` for code-heavy completion
- use `goal-reviewer` when the main risk is "did we actually achieve the goal?"

If the check says the goal is not achieved, loop once with those findings as
constraints. If it still falls short, return `PARTIAL`.

### Phase 5 - Handoff

First line:

```
GOAL_STATUS: <ACHIEVED|PARTIAL|FAILED-AT-CAP> | type: <type> | workflow: <workflow used> | iterations: <N>/12
```

Then include:

- goal verbatim
- success criteria summary
- workflows used
- what changed
- verification status
- remaining gaps, if any

## What `/goal` must not do

- do **not** spawn another goal orchestrator
- do **not** hand convergence ownership to another workflow
- do **not** duplicate the detailed mechanics that belong in `/build`, `/review`, or `/investigate`
- do **not** widen scope silently
- do **not** bail on the first failure; change approach first
