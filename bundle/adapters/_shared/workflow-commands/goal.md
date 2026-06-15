---
description: "User-typed /goal entry point. The current session owns loop state and convergence until the goal is achieved or blocked."
---

# /goal

You are the __HOST_NAME__ session acting as goal orchestrator. The current
session owns convergence; do not spawn another goal orchestrator.

## Ownership Model

Track:

- success criteria
- scope in / out
- loop state
- test strategy and E2E feasibility for code goals
- verification command
- repair attempts
- blockers

Use `/build`, `/review`, `/refactor`, `/redesign`, `/investigate`, `/analyze`,
or `/bootstrap-harness` as execution subroutines. They do not own convergence.

## Workflow

1. Classify the goal type and choose the primary workflow.
2. State success criteria, scope in/out, assumptions, expected test set, E2E
   feasibility, and verification command.
3. Run one workflow pass.
4. Compare the result against success criteria.
5. Run fresh verification when files changed.
6. If criteria are unmet or review has BLOCKING findings, repair and repeat.

Caps:

- max 3 repair cycles for the same blocker/task
- soft cap 6 total iterations
- hard cap 12 total iterations

Completion means the success criteria are met, the requested behavior is covered
by a meaningful test set where feasible, verification is green, and there is no
unhandled BLOCKING finding from the unified reviewer. Do not use legacy
goal/verifier agents by default; the orchestrator owns the final semantic,
test-strategy, and verification check.

## Goal Type Routing

| Goal type | Primary workflow |
|---|---|
| CODE | `/build` |
| REFACTOR | `/refactor` |
| INVESTIGATION | `/investigate` |
| ANALYSIS | `/analyze` |
| REVIEW | `/review` |
| DESIGN | `/redesign` |
| BOOTSTRAP | `/bootstrap-harness` |
| MULTI | sequence two or more workflows explicitly |

## Handoff

First line:

```
GOAL_STATUS: <ACHIEVED|PARTIAL|FAILED-AT-CAP> | type: <type> | workflow: <workflow used> | iterations: <N>/12
```

Then include the goal, success criteria summary, what changed, verification
status, reviewer outcome, and remaining gaps.

## Not Default

Do not run legacy reviewer/verifier agents, memory inbox collection, writeback
gates, or reflection backlog gates in normal `/goal` execution.
