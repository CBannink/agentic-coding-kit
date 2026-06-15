---
name: test-strategy
description: "Use before implementation when defining the expected test set for a change, especially when user-visible behavior, integration boundaries, mock data, or E2E feasibility matter."
---

# Test Strategy

Define the smallest test set that would actually prove the requested behavior.
This is a planning aid, not a default agent and not a gate by itself.

## Inputs

- Requested behavior or bug.
- Files or surfaces likely to change.
- Existing test commands and test framework, if known.
- External systems, permissions, auth states, data fixtures, or UI flows involved.

## Rules

1. Start from behavior, not implementation shape.
2. Include E2E coverage when the changed behavior is user-visible and the repo
   has a runnable E2E path.
3. If E2E is infeasible, state why and choose the nearest integration,
   contract, workflow, or smoke test.
4. Use mock data or fixtures for external systems, permissions, time,
   network, databases, and edge cases.
5. Do not accept "existing tests pass" as enough when requested behavior changed.
6. If no test change is appropriate, justify it concretely.

## Output

```text
TEST_STRATEGY:
- Behavior under test:
- Unit tests:
- Integration/contract tests:
- E2E/workflow tests:
- Mock data/fixtures:
- Negative and edge cases:
- Not testing / why:
- Verification command:
```

Keep the output short enough to paste into an implementer handoff.
